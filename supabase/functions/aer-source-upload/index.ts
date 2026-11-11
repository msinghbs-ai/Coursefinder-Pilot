// CF-247 F-AER.04 D3 (Platform Admin decision D3, 11 Nov 2026): a Platform Admin attaches a provider's entry-requirements PDF on Catalogue › Entry requirements › Sources.
// The source is checked and recorded by public.admin_aer_source (ownership on the provider's own website host, classes, reuse, reason, the PDF size cap entry.pdf_max_bytes)
// under the person's own sign-in; only then is the file stored where the fetch step stores entry PDFs (bucket evidence, gzipped) and recorded by
// public.svc_aer_source_upload_record, which queues its one read. Its rows go to Layer 4; an uploaded copy is never admitted by the machine class.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "cache-control": "no-store",
  "referrer-policy": "no-referrer",
};
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json; charset=utf-8" } });
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const noSession = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
const hex = (b: ArrayBuffer) => Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, "0")).join("");
const gzip = async (b: Uint8Array) => new Uint8Array(await new Response(new Blob([b]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer());

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const authHeader = req.headers.get("authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return reply(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(500, { error: "service_configuration_error" });

  let form: FormData;
  try { form = await req.formData() } catch { return reply(400, { error: "multipart_form_required" }) }
  const providerId = String(form.get("provider_id") || "").trim();
  const sourceUrl = String(form.get("url") || "").trim();
  const reason = String(form.get("reason") || "").trim();
  const title = String(form.get("title") || "").trim();
  const classes = String(form.get("classes") || "").split(",").map((s) => s.trim()).filter(Boolean);
  const file = form.get("file");
  if (!uuidRe.test(providerId)) return reply(400, { error: "invalid_provider_id" });
  if (!(file instanceof File) || file.size === 0) return reply(400, { error: "pdf_file_required" });
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!(bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46)) return reply(422, { error: "not_a_pdf", reason: "The file is not a PDF." });  // %PDF
  const sha = hex(await crypto.subtle.digest("SHA-256", bytes));

  // the person's own sign-in: rank, reason, ownership, classes, reuse and size are decided by the database
  const user = createClient(url, anon, { global: { headers: { Authorization: authHeader } }, auth: noSession });
  const { data: begin, error: beginError } = await user.rpc("admin_aer_source", {
    p_args: { action: "upload_begin", how: "pdf_upload", provider_id: providerId, url: sourceUrl, classes, reason, title, sha256: sha, bytes: bytes.byteLength },
  });
  if (beginError) return reply(beginError.code === "42501" ? 403 : 422, { error: "refused", reason: beginError.message });
  if (!begin?.ok || !begin?.attached) return reply(422, { error: begin?.rule || "refused", reason: begin?.reason || "The source was not attached.", check: begin });
  if (!begin.upload) return reply(200, { ok: true, stored: false, source_id: begin.source_id, outcome: begin.outcome, check: begin });

  const svc = createClient(url, service, { auth: noSession });
  const up = await svc.storage.from("evidence").upload(String(begin.storage_path), await gzip(bytes), { contentType: "application/gzip", upsert: true });
  if (up.error) return reply(500, { error: "storage_failed", reason: up.error.message, attachment_id: begin.attachment_id });
  const { data: rec, error: recError } = await svc.rpc("svc_aer_source_upload_record", { p_attachment: begin.attachment_id, p_path: begin.storage_path, p_sha: sha });
  if (recError) return reply(500, { error: "record_failed", reason: recError.message, attachment_id: begin.attachment_id });
  return reply(200, { ok: true, stored: true, source_id: begin.source_id, attachment_id: begin.attachment_id, sha256: sha, bytes: bytes.byteLength, outcome: rec?.outcome, reads_queued: rec?.reads_queued });
});
