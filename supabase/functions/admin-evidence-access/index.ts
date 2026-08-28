import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "cache-control": "no-store",
  "referrer-policy": "no-referrer",
};
const jsonHeaders = { ...cors, "content-type": "application/json; charset=utf-8" };
const previewMimes = new Set(["application/pdf", "image/png", "image/jpeg", "image/webp", "text/plain", "application/json"]);
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const authHeader = req.headers.get("authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return reply(401, { error: "authentication_required" });

  let body: { evidence_id?: string; mode?: "preview" | "download" };
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }
  const evidenceId = String(body?.evidence_id || "").trim();
  const mode = body?.mode === "download" ? "download" : "preview";
  if (!uuidRe.test(evidenceId)) return reply(400, { error: "invalid_evidence_id" });

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(500, { error: "service_configuration_error" });

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: context, error: contextError } = await userClient.rpc("admin_read", { p_operation: "context", p_args: {} });
  if (contextError || !context?.authenticated) return reply(401, { error: "authentication_required" });
  if (Number(context?.role_rank || 0) < 3) return reply(403, { error: "curator_role_required" });

  const serviceClient = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  const { data: descriptor, error: descriptorError } = await serviceClient.rpc("svc_admin_evidence_access_descriptor", { p_evidence_id: evidenceId });
  if (descriptorError) return reply(500, { error: "evidence_access_lookup_failed" });
  if (!descriptor?.evidence_id) return reply(404, { error: "evidence_not_found" });
  if (!descriptor?.available || !descriptor?.storage_path) return reply(404, { error: "evidence_object_unavailable" });

  const mime = String(descriptor?.mime_type || "application/octet-stream").toLowerCase();
  if (mode === "preview" && !previewMimes.has(mime)) return reply(415, { error: "preview_not_allowed", download_allowed: true });

  const options = mode === "download" ? { download: true } : undefined;
  const { data: signed, error: signedError } = await serviceClient.storage.from("evidence").createSignedUrl(descriptor.storage_path, 60, options);
  if (signedError || !signed?.signedUrl) return reply(500, { error: "signed_access_failed" });

  return reply(200, {
    evidence_id: evidenceId,
    mode,
    mime_type: mime,
    expires_in: 60,
    url: signed.signedUrl,
  });
});
