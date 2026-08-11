import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "pilot-reset-v0.2.0";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const service = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "authentication required" }, 401);
  const { data: userData, error: userError } = await service.auth.getUser(token);
  if (userError || !userData.user?.id) return json({ error: "invalid session" }, 401);
  const { data: allowed, error: allowError } = await service.rpc("svc_layer1_authorize_platform_admin", { p_user_id: userData.user.id });
  if (allowError || allowed !== true) return json({ error: "platform_admin required" }, 403);

  let body: any = {};
  try { body = await req.json(); } catch {}
  if (String(body.confirm || "").toUpperCase() !== "RESET AU UAT") {
    return json({ error: "Pass confirm: RESET AU UAT" }, 400);
  }

  const { data, error } = await service.rpc("svc_layer1_reset_au_uat");
  if (error) return json({ error: error.message, version: VERSION }, 500);

  const { error: storageError } = await service.storage.emptyBucket("evidence");
  if (storageError) {
    return json({ error: `Database reset completed but evidence bucket cleanup failed: ${storageError.message}`, version: VERSION, ...data }, 500);
  }

  return json({ ok: true, version: VERSION, evidence_bucket_emptied: true, ...data });
});
