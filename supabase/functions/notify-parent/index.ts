// Entry point of the notify-parent Edge Function: wires the real database and Apple push clients.

import { createClient } from "npm:@supabase/supabase-js@2";
import { makeApnsJwt, readApnsConfig, sendAlert } from "./apns.ts";
import { notifyParent } from "./handler.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve((request) =>
  notifyParent(request, {
    admin,
    apnsConfig: readApnsConfig((name) => Deno.env.get(name)),
    makeJwt: makeApnsJwt,
    send: sendAlert,
  })
);
