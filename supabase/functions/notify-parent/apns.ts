// Small Apple Push Notification client: signs a provider token with the .p8 key and sends one alert.

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  privateKey: string;
  bundleId: string;
}

export type ApnsEnvironment = "sandbox" | "production";

export interface ApnsAlert {
  title: string;
  body: string;
  threadId: string;
}

export interface ApnsResult {
  ok: boolean;
  status: number;
  reason: string;
}

const APNS_HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: "api.sandbox.push.apple.com",
  production: "api.push.apple.com",
};

/** Reads the four APNS_* secrets; returns null until all of them are set. */
export function readApnsConfig(env: (name: string) => string | undefined): ApnsConfig | null {
  const keyId = env("APNS_KEY_ID");
  const teamId = env("APNS_TEAM_ID");
  const privateKey = env("APNS_PRIVATE_KEY");
  const bundleId = env("APNS_BUNDLE_ID");
  if (!keyId || !teamId || !privateKey || !bundleId) return null;
  return { keyId, teamId, privateKey: privateKey.replace(/\\n/g, "\n"), bundleId };
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const base64 = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

/** Builds the short-lived ES256 token Apple asks for (valid for up to one hour). */
export async function makeApnsJwt(config: ApnsConfig, issuedAt = Math.floor(Date.now() / 1000)): Promise<string> {
  const encoder = new TextEncoder();
  const header = base64Url(encoder.encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const claims = base64Url(encoder.encode(JSON.stringify({ iss: config.teamId, iat: issuedAt })));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
}

/** Sends one alert to one device and reports Apple's answer. */
export async function sendAlert(
  config: ApnsConfig,
  jwt: string,
  deviceToken: string,
  environment: ApnsEnvironment,
  alert: ApnsAlert,
): Promise<ApnsResult> {
  const response = await fetch(`https://${APNS_HOSTS[environment]}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify({
      aps: { alert: { title: alert.title, body: alert.body }, sound: "default", "thread-id": alert.threadId },
    }),
  });
  const answer = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, reason: answer.reason ?? "" };
}
