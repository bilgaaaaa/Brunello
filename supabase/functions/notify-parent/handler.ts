// Tells the other parent about something new, in the pet's voice.
// Called by the app right after it saves a diary entry or an expense:
// POST { "entry_id": "<uuid>" } or { "expense_id": "<uuid>" } with the caller's session.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { ApnsAlert, ApnsConfig, ApnsEnvironment, ApnsResult } from "./apns.ts";
import { expenseVoiceLine, notificationBody, notificationTitle, voiceLine } from "./petVoice.ts";

export interface NotifyParentDependencies {
  admin: SupabaseClient;
  apnsConfig: ApnsConfig | null;
  makeJwt: (config: ApnsConfig) => Promise<string>;
  send: (config: ApnsConfig, jwt: string, deviceToken: string, environment: ApnsEnvironment, alert: ApnsAlert) => Promise<ApnsResult>;
}

interface DeviceToken {
  token: string;
  user_id: string;
  environment: ApnsEnvironment;
}

interface Parent {
  id: string;
  user_id: string;
  name: string;
  nickname: string;
}

interface Pet {
  name: string;
  species: string;
  currency_code: string;
}

/** The new thing to announce: where it belongs, who wrote it and how the pet words it. */
interface News {
  petId: string;
  parentId: string;
  makeLine: (author: Parent, pet: Pet) => string | null;
}

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const otherEnvironment = (environment: ApnsEnvironment): ApnsEnvironment =>
  environment === "sandbox" ? "production" : "sandbox";

/** Loads the entry or expense named in the request. */
async function loadNews(admin: SupabaseClient, body: Record<string, unknown>): Promise<News | null> {
  if (typeof body.entry_id === "string") {
    const { data: entry } = await admin.from("entries")
      .select("pet_id, parent_id, kind, detail").eq("id", body.entry_id).maybeSingle();
    if (!entry) return null;
    return { petId: entry.pet_id, parentId: entry.parent_id, makeLine: () => voiceLine(entry.kind, entry.detail) };
  }
  if (typeof body.expense_id === "string") {
    const { data: expense } = await admin.from("expenses")
      .select("pet_id, parent_id, category, amount_cents, owed_cents").eq("id", body.expense_id).maybeSingle();
    if (!expense) return null;
    return {
      petId: expense.pet_id,
      parentId: expense.parent_id,
      makeLine: (author, pet) =>
        expenseVoiceLine(expense.category, author.name, expense.amount_cents, expense.owed_cents, pet.currency_code),
    };
  }
  return null;
}

/** Sends to one device; a token registered under the wrong environment is retried on the other one. */
async function deliver(deps: NotifyParentDependencies, config: ApnsConfig, jwt: string, device: DeviceToken, alert: ApnsAlert): Promise<boolean> {
  let result = await deps.send(config, jwt, device.token, device.environment, alert);
  if (result.status === 400 && result.reason === "BadDeviceToken") {
    const environment = otherEnvironment(device.environment);
    result = await deps.send(config, jwt, device.token, environment, alert);
    if (result.ok) {
      await deps.admin.from("device_tokens").update({ environment }).eq("token", device.token);
      console.log(`[notify-parent] token moved to ${environment}`);
    }
  }
  if (result.ok) return true;

  console.error(`[notify-parent] APNs refused a token: ${result.status} ${result.reason}`);
  if (result.status === 410 || result.reason === "BadDeviceToken") {
    await deps.admin.from("device_tokens").delete().eq("token", device.token);
    console.log("[notify-parent] removed a dead token");
  }
  return false;
}

export async function notifyParent(request: Request, deps: NotifyParentDependencies): Promise<Response> {
  try {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

    const jwt = (request.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: userData, error: userError } = await deps.admin.auth.getUser(jwt);
    if (userError || !userData.user) return json({ error: "not_signed_in" }, 401);

    const body = await request.json().catch(() => ({}));
    if (typeof body.entry_id !== "string" && typeof body.expense_id !== "string") return json({ error: "id_missing" }, 400);
    const news = await loadNews(deps.admin, body);
    if (!news) return json({ error: "not_found" }, 404);

    const { data: parentRows } = await deps.admin.from("parents")
      .select("id, user_id, name, nickname").eq("pet_id", news.petId);
    const parents = (parentRows ?? []) as Parent[];
    const author = parents.find((parent) => parent.id === news.parentId);
    // Only the parent who wrote it may announce it.
    if (!author || author.user_id !== userData.user.id) return json({ error: "not_the_author" }, 403);

    const receivers = parents.filter((parent) => parent.id !== news.parentId);
    if (receivers.length === 0) return json({ sent: 0, reason: "nobody_to_tell" });

    const { data: pet } = await deps.admin.from("pets")
      .select("name, species, currency_code").eq("id", news.petId).single();
    const line = pet ? news.makeLine(author, pet as Pet) : null;
    if (!pet || !line) return json({ sent: 0, reason: "nothing_to_say" });

    if (!deps.apnsConfig) {
      console.log("[notify-parent] APNS_* secrets are not set yet, skipping the push");
      return json({ sent: 0, reason: "apns_not_configured" });
    }

    const { data: devices } = await deps.admin.from("device_tokens")
      .select("token, user_id, environment").in("user_id", receivers.map((parent) => parent.user_id));
    if (!devices || devices.length === 0) return json({ sent: 0, reason: "no_devices" });

    const apnsJwt = await deps.makeJwt(deps.apnsConfig);
    let sent = 0;
    for (const device of devices as DeviceToken[]) {
      const receiver = receivers.find((parent) => parent.user_id === device.user_id)!;
      const alert: ApnsAlert = {
        title: notificationTitle(pet.name, pet.species),
        body: notificationBody(receiver.nickname, line),
        threadId: news.petId,
      };
      if (await deliver(deps, deps.apnsConfig, apnsJwt, device, alert)) sent += 1;
    }
    console.log(`[notify-parent] sent ${sent} of ${devices.length}`);
    return json({ sent });
  } catch (error) {
    console.error("[notify-parent] failed:", error);
    return json({ error: "unexpected" }, 500);
  }
}
