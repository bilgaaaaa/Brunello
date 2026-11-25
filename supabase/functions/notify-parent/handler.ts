// Tells the other parent about a new diary entry, in the pet's voice.
// Called by the app right after it saves an entry: POST { "entry_id": "<uuid>" } with the caller's session.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { ApnsAlert, ApnsConfig, ApnsEnvironment, ApnsResult } from "./apns.ts";
import { notificationBody, notificationTitle, voiceLine } from "./petVoice.ts";

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

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const otherEnvironment = (environment: ApnsEnvironment): ApnsEnvironment =>
  environment === "sandbox" ? "production" : "sandbox";

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

    const { entry_id: entryId } = await request.json().catch(() => ({}));
    if (typeof entryId !== "string") return json({ error: "entry_id_missing" }, 400);

    const { data: entry } = await deps.admin.from("entries")
      .select("id, pet_id, parent_id, kind, detail").eq("id", entryId).maybeSingle();
    if (!entry) return json({ error: "entry_not_found" }, 404);

    const { data: parents } = await deps.admin.from("parents")
      .select("id, user_id, nickname").eq("pet_id", entry.pet_id);
    const author = (parents ?? []).find((parent) => parent.id === entry.parent_id);
    // Only the parent who wrote the entry may announce it.
    if (!author || author.user_id !== userData.user.id) return json({ error: "not_the_author" }, 403);

    const receivers = (parents ?? []).filter((parent) => parent.id !== entry.parent_id);
    const line = voiceLine(entry.kind, entry.detail);
    if (receivers.length === 0 || !line) return json({ sent: 0, reason: "nobody_to_tell" });

    if (!deps.apnsConfig) {
      console.log("[notify-parent] APNS_* secrets are not set yet, skipping the push");
      return json({ sent: 0, reason: "apns_not_configured" });
    }

    const { data: pet } = await deps.admin.from("pets").select("name, species").eq("id", entry.pet_id).single();
    const { data: devices } = await deps.admin.from("device_tokens")
      .select("token, user_id, environment").in("user_id", receivers.map((parent) => parent.user_id));
    if (!pet || !devices || devices.length === 0) return json({ sent: 0, reason: "no_devices" });

    const apnsJwt = await deps.makeJwt(deps.apnsConfig);
    let sent = 0;
    for (const device of devices as DeviceToken[]) {
      const receiver = receivers.find((parent) => parent.user_id === device.user_id)!;
      const alert: ApnsAlert = {
        title: notificationTitle(pet.name, pet.species),
        body: notificationBody(receiver.nickname, line),
        threadId: entry.pet_id,
        entryId: entry.id,
      };
      if (await deliver(deps, deps.apnsConfig, apnsJwt, device, alert)) sent += 1;
    }
    console.log(`[notify-parent] entry ${entry.id}: sent ${sent} of ${devices.length}`);
    return json({ sent });
  } catch (error) {
    console.error("[notify-parent] failed:", error);
    return json({ error: "unexpected" }, 500);
  }
}
