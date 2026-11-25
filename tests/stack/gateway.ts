// Local stand-in for a Supabase project, for tests only: fake sign-in and storage, real PostgREST behind it,
// and the real notify-parent handler wired to a fake Apple push server.
import { createClient } from "npm:@supabase/supabase-js@2";
import { notifyParent } from "/repo/supabase/functions/notify-parent/handler.ts";
import { makeApnsJwt } from "/repo/supabase/functions/notify-parent/apns.ts";
import type { ApnsAlert, ApnsConfig, ApnsEnvironment, ApnsResult } from "/repo/supabase/functions/notify-parent/apns.ts";

const JWT_SECRET = "local-test-secret-at-least-32-characters-long";
const POSTGREST = "http://127.0.0.1:3000";
const PORT = 54321;
const encoder = new TextEncoder();
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlDecode = (text: string) => Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const hmacKey = await crypto.subtle.importKey("raw", encoder.encode(JWT_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
async function signJwt(claims: Record<string, unknown>): Promise<string> {
  const body = `${b64url(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })))}.${b64url(encoder.encode(JSON.stringify(claims)))}`;
  return `${body}.${b64url(new Uint8Array(await crypto.subtle.sign("HMAC", hmacKey, encoder.encode(body))))}`;
}
async function verifyJwt(token: string): Promise<Record<string, unknown> | null> {
  const [header, claims, signature] = token.split(".");
  if (!header || !claims || !signature) return null;
  try {
    const valid = await crypto.subtle.verify("HMAC", hmacKey, b64urlDecode(signature), encoder.encode(`${header}.${claims}`));
    return valid ? JSON.parse(new TextDecoder().decode(b64urlDecode(claims))) : null;
  } catch {
    return null;
  }
}

const serviceKey = await signJwt({ role: "service_role", exp: 4102444800 });
const admin = createClient(`http://127.0.0.1:${PORT}`, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

// A throwaway Apple key, so the real token signing code runs and can be verified.
const appleKey = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const pkcs8 = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("pkcs8", appleKey.privateKey))));
const apnsConfig: ApnsConfig = {
  keyId: "TESTKEY123",
  teamId: "TESTTEAM12",
  privateKey: `-----BEGIN PRIVATE KEY-----\\n${pkcs8.match(/.{1,64}/g)!.join("\\n")}\\n-----END PRIVATE KEY-----`.replace(/\\n/g, "\n"),
  bundleId: "com.example.brunello",
};

const sentAlerts: Record<string, string>[] = [];
// Fake Apple: checks the provider token like Apple would, then answers by token prefix.
async function fakeSend(config: ApnsConfig, jwt: string, deviceToken: string, environment: ApnsEnvironment, alert: ApnsAlert): Promise<ApnsResult> {
  const [header, claims, signature] = jwt.split(".");
  const signatureOk = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, appleKey.publicKey, b64urlDecode(signature), encoder.encode(`${header}.${claims}`));
  const parsedHeader = JSON.parse(new TextDecoder().decode(b64urlDecode(header)));
  const parsedClaims = JSON.parse(new TextDecoder().decode(b64urlDecode(claims)));
  if (!signatureOk || parsedHeader.alg !== "ES256" || parsedHeader.kid !== config.keyId || parsedClaims.iss !== config.teamId || Math.abs(parsedClaims.iat - Date.now() / 1000) > 60) {
    throw new Error("the provider token would be rejected by Apple");
  }
  let result: ApnsResult = { ok: true, status: 200, reason: "" };
  if (deviceToken.startsWith("bad0") && environment === "sandbox") result = { ok: false, status: 400, reason: "BadDeviceToken" };
  if (deviceToken.startsWith("dead")) result = { ok: false, status: 410, reason: "Unregistered" };
  sentAlerts.push({ token: deviceToken, environment, title: alert.title, body: alert.body, result: result.reason || "ok" });
  return result;
}

const photos = new Map<string, Uint8Array>();
// Pulls the bytes of the part that carries a filename out of a multipart upload.
function extractFilePart(body: Uint8Array, contentType: string): Uint8Array | null {
  const boundary = contentType.match(/boundary=(.+)$/)?.[1]?.replace(/^"|"$/g, "");
  if (!boundary) return null;
  const marker = encoder.encode(`--${boundary}`);
  const indexOf = (needle: Uint8Array, from: number) => {
    outer: for (let i = from; i <= body.length - needle.length; i++) {
      for (let j = 0; j < needle.length; j++) if (body[i + j] !== needle[j]) continue outer;
      return i;
    }
    return -1;
  };
  const headerEnd = encoder.encode("\r\n\r\n");
  let start = indexOf(marker, 0);
  while (start !== -1) {
    const next = indexOf(marker, start + marker.length);
    if (next === -1) break;
    const split = indexOf(headerEnd, start);
    if (split !== -1 && split < next && new TextDecoder().decode(body.subarray(start, split)).includes("filename=")) {
      return body.slice(split + 4, next - 2);
    }
    start = next;
  }
  return null;
}
const userJson = (id: string) => ({ id, aud: "authenticated", role: "authenticated", app_metadata: {}, user_metadata: {}, is_anonymous: true, created_at: new Date().toISOString(), updated_at: new Date().toISOString() });

Deno.serve({ port: PORT, hostname: "127.0.0.1" }, async (request) => {
  const url = new URL(request.url);
  const path = url.pathname;
  try {
    if (path === "/auth/v1/signup" && request.method === "POST") {
      const id = crypto.randomUUID();
      const created = await fetch(`${POSTGREST}/rpc/test_create_user`, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${serviceKey}` }, body: JSON.stringify({ uid: id }) });
      if (!created.ok) return json({ error: await created.text() }, 500);
      const expiresAt = Math.floor(Date.now() / 1000) + 3600;
      const accessToken = await signJwt({ sub: id, role: "authenticated", aud: "authenticated", is_anonymous: true, exp: expiresAt });
      return json({ access_token: accessToken, token_type: "bearer", expires_in: 3600, expires_at: expiresAt, refresh_token: crypto.randomUUID(), user: userJson(id) });
    }
    if (path === "/auth/v1/user") {
      const claims = await verifyJwt((request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, ""));
      return claims?.sub ? json(userJson(String(claims.sub))) : json({ message: "invalid token" }, 401);
    }
    if (path.startsWith("/rest/v1/")) {
      const headers = new Headers(request.headers);
      headers.delete("host");
      // A token this stack did not sign (the app's placeholder key) counts as not signed in.
      const bearer = (headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
      if (!(await verifyJwt(bearer))) headers.delete("authorization");
      const body = ["GET", "HEAD"].includes(request.method) ? undefined : await request.arrayBuffer();
      const response = await fetch(`${POSTGREST}${path.replace("/rest/v1", "")}${url.search}`, { method: request.method, headers, body });
      return new Response(response.body, { status: response.status, headers: response.headers });
    }
    if (path.startsWith("/storage/v1/object/photos")) {
      const key = decodeURIComponent(path.replace("/storage/v1/object/photos", "").replace(/^\//, ""));
      if (request.method === "POST") {
        const file = extractFilePart(new Uint8Array(await request.arrayBuffer()), request.headers.get("content-type") ?? "");
        if (!file) return json({ message: "no file in the upload" }, 400);
        photos.set(key, file);
        return json({ Key: `photos/${key}`, Id: crypto.randomUUID() });
      }
      if (request.method === "GET") {
        const bytes = photos.get(key);
        return bytes ? new Response(bytes, { headers: { "content-type": "image/jpeg" } }) : json({ message: "Object not found" }, 404);
      }
      if (request.method === "DELETE") {
        const { prefixes } = await request.json();
        for (const prefix of prefixes) photos.delete(prefix);
        return json([]);
      }
    }
    if (path === "/functions/v1/notify-parent") {
      return await notifyParent(request, { admin, apnsConfig, makeJwt: makeApnsJwt, send: fakeSend });
    }
    if (path === "/test/alerts") return json(sentAlerts);
    return json({ message: `no route for ${request.method} ${path}` }, 404);
  } catch (error) {
    console.error("gateway error", error);
    return json({ message: String(error) }, 500);
  }
});
