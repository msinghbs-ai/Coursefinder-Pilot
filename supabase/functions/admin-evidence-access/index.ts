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
// v1.1 (CF-247, Platform Admin 19 Oct 2026 22:13: "tried opening view page and error Preview_not_allowed"): course pages and markdown pages
// are saved gzip-compressed (*.gz), about 117,000 files, and HTML was never on the preview list, so View page was refused for every course
// page and Download handed back a .gz. Now a saved web page, markdown or CSV file is opened here, unpacked and returned as text: the panel
// shows HTML in a sandboxed frame (no scripts, no forms, no same-origin) and text as text; Download returns the unpacked file.
const textMimes = new Set(["text/html", "application/xhtml+xml", "text/markdown", "text/csv", "text/plain", "application/json"]);
const maxTextBytes = 8 * 1024 * 1024; // fixed: response-size safety for the edge runtime, not an operational limit
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
  const path = String(descriptor.storage_path);
  const packed = path.toLowerCase().endsWith(".gz");
  if (textMimes.has(mime) && (packed || mime === "text/html" || mime === "application/xhtml+xml" || mime === "text/markdown")) {
    const { data: blob, error: fileError } = await serviceClient.storage.from("evidence").download(path);
    if (fileError || !blob) return reply(404, { error: "evidence_object_unavailable" });
    let stream: ReadableStream<Uint8Array> = blob.stream();
    if (packed) stream = stream.pipeThrough(new DecompressionStream("gzip"));
    const reader = stream.getReader();
    const parts: Uint8Array[] = [];
    let size = 0, truncated = false;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (size + value.length > maxTextBytes) { parts.push(value.slice(0, maxTextBytes - size)); size = maxTextBytes; truncated = true; await reader.cancel(); break; }
      parts.push(value); size += value.length;
    }
    const bytes = new Uint8Array(size);
    let at = 0;
    for (const p of parts) { bytes.set(p, at); at += p.length; }
    const content = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
    const base = path.split("/").pop()!.replace(/\.gz$/i, "");
    const kind = mime === "text/html" || mime === "application/xhtml+xml" ? "html" : mime === "text/markdown" ? "markdown" : "text";
    return reply(200, { evidence_id: evidenceId, mode, mime_type: mime, kind, file_name: base, content, size_bytes: size, truncated });
  }
  if (mode === "preview" && !previewMimes.has(mime)) return reply(415, { error: "preview_not_allowed", download_allowed: true });

  const options = mode === "download" ? { download: true } : undefined;
  const { data: signed, error: signedError } = await serviceClient.storage.from("evidence").createSignedUrl(path, 60, options);
  if (signedError || !signed?.signedUrl) return reply(500, { error: "signed_access_failed" });

  return reply(200, {
    evidence_id: evidenceId,
    mode,
    mime_type: mime,
    expires_in: 60,
    url: signed.signedUrl,
  });
});
