// CF-247 s1344 (S1-Build; SS-Programme-Control 28 Nov 2026 PC-20261128-DOT-STORAGE-APPROVED): DOT's direct drop-off into the private data-intake
// bucket (never BOOST). The caller signs in as the DOT user; the database decides first whether the switch (data_intake.on) is on and the caller
// holds an active, unexpired dot_submitter assignment (public.svc_data_intake_v1 gate), before anything is read or stored.
//   action=upload   one original (PDF, HTML, JSON, JSONL or text): size from data_intake.max_bytes, the SHA-256 the caller states must equal the
//                   server's, the MIME must match the extension; stored once at dot/<country>/<provider>/<package>/files/<sha256>.<ext>
//                   (no overwrite) and recorded. A finalised package takes no more files.
//   action=finalise the READY manifest, written last ({files:[{sha256}], items:[structured intake candidates]}): stored at
//                   .../manifest-<sha256>.json; every listed original must already be recorded and every candidate must name the package's
//                   provider, else HELD:MANIFEST_INCOMPLETE; then the existing structured intake writer (submitter dot) takes the candidates and
//                   its receipt is returned. Replaying a finalised package returns the same receipt and writes nothing.
//   action=status   the package's state and receipt.
// Every database check (identity with a bounded expiry, package open, provider in country, derived path, complete manifest, the same manifest on
// replay) runs before anything is stored, so a refused call stores nothing; one writer per package at a time (database lock).
// The caller can only write new objects under its own package paths through this function; it has no storage, table or listing access of its own.
// No canonical row, evidence or activation is written here: proof on stored copies, the course binding and the admission rules decide.
// s1351 (PC-20261128-DOT-DROPBOX-POC): a one-package drop-off capability may stand in for the signed-in user: ?cap=<token> on the URL or the
// header x-intake-capability. The database checks it (unexpired, not revoked) and its package scope replaces the caller's country, provider and
// package. Besides multipart, a raw body is accepted: the action and fields in the query (action, sha256, ext, source_url), the bytes (upload)
// or the manifest JSON (finalise) as the body; status needs no body.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "dot-intake-v0.4.0";
const BUCKET = "data-intake";
const MIME: Record<string, string[]> = { pdf: ["application/pdf"], html: ["text/html"], json: ["application/json"], jsonl: ["application/x-ndjson", "application/jsonl", "application/json"], txt: ["text/plain"] };
const json = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify({ ...body, version: VERSION }), { status, headers: { "content-type": "application/json" } });
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const noSession = { persistSession: false, autoRefreshToken: false };
const SHA = /^[0-9a-f]{64}$/, PKG = /^[a-z0-9][a-z0-9._-]{2,80}$/, UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const fixedError = (e: any) => { const m = String(e?.message || ""); return m.startsWith("INVALID_INPUT:") ? { status: 422, body: { error: "refused", reason: m.slice(0, 300) } } : { status: 500, body: { error: "request_failed" } } };

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return json(500, { error: "service_configuration_error" });
  const q = new URL(req.url).searchParams;
  const cap = (q.get("cap") || req.headers.get("x-intake-capability") || "").trim();
  const svc = createClient(url, service, { auth: noSession });
  let who: Record<string, unknown>;
  if (cap) {
    if (!/^dic_[0-9a-f]{64}$/.test(cap)) return json(401, { error: "invalid_capability" });
    who = { capability_sha256: hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(cap))) };
  } else {
    const auth = req.headers.get("authorization") || "";
    if (!auth.toLowerCase().startsWith("bearer ")) return json(401, { error: "authentication_required" });
    const { data: u, error: uErr } = await createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: noSession }).auth.getUser();
    if (uErr || !u?.user?.id) return json(401, { error: "authentication_required" });
    who = { user_id: u.user.id };
  }
  const rpc = (p_action: string, extra: Record<string, unknown>) => svc.rpc("svc_data_intake_v1", { p_action, p_args: { ...who, ...extra } });
  // the database decides first: the switch, and an active, unexpired dot_submitter assignment or capability
  const { data: gate, error: gateErr } = await rpc("gate", {});
  if (gateErr) return json(500, { error: "gate_failed" });
  if (!gate?.ok) return json(gate?.held === "HELD:SWITCHED_OFF" ? 503 : gate?.held === "HELD:CAPABILITY_INVALID" ? 401 : 403, { error: "refused", held: gate?.held ?? "HELD:GATE" });

  // multipart (fields and file) or raw (fields in the query, bytes or manifest as the body)
  const field = new Map<string, string>(); let file: File | null = null;
  if ((req.headers.get("content-type") || "").toLowerCase().startsWith("multipart/form-data")) {
    let form: FormData;
    try { form = await req.formData() } catch { return json(400, { error: "multipart_form_required" }) }
    for (const [k, v] of form.entries()) { if (v instanceof File) { if (k === "file") file = v } else field.set(k, String(v)) }
  } else {
    for (const [k, v] of q.entries()) if (k !== "cap") field.set(k, v);
    const raw = new Uint8Array(await req.arrayBuffer());
    if (raw.length) file = new File([raw], `body.${field.get("ext") || "bin"}`, { type: (req.headers.get("content-type") || "").split(";")[0].trim().toLowerCase() || "application/octet-stream" });
  }
  const scope = (gate.scope || {}) as Record<string, string>;
  const action = String(field.get("action") || ""), pkg = String(scope.package || field.get("package") || "").trim();
  const country = String(scope.country || field.get("country") || "").trim().toUpperCase(), provider = String(scope.provider_id || field.get("provider_id") || "").trim().toLowerCase();
  if (!["upload", "finalise", "status"].includes(action)) return json(400, { error: "invalid_action" });
  if (!PKG.test(pkg) || !/^[A-Z]{2}$/.test(country) || !UUID.test(provider)) return json(400, { error: "invalid_package_identity" });
  const ident = { package: pkg, country, provider_id: provider };
  const root = `dot/${country}/${provider}/${pkg}/`;
  if (action === "status") { const { data, error } = await rpc("status", ident); if (error) { const f = fixedError(error); return json(f.status, f.body) } return json(200, data) }

  const stated = String(field.get("sha256") || "").trim().toLowerCase();
  if (!SHA.test(stated)) return json(400, { error: "invalid_sha256" });
  if (!file || file.size === 0) return json(400, { error: "file_required" });
  if (file.size > Number(gate.max_bytes || 0)) return json(413, { error: "file_too_large", max_bytes: gate.max_bytes });
  const bytes = new Uint8Array(await file.arrayBuffer());
  const sha = hex(await crypto.subtle.digest("SHA-256", bytes));
  if (sha !== stated) return json(422, { error: "sha256_mismatch", stated, computed: sha });  // nothing stored, nothing recorded
  const store = async (path: string, type: string) => {
    const up = await svc.storage.from(BUCKET).upload(path, bytes, { contentType: type, upsert: false });  // never overwrite
    if (up.error && !/exists|duplicate|409/i.test(String((up.error as any).statusCode ?? "") + " " + up.error.message)) throw new Error("storage_failed");
    return !!up.error;
  };

  if (action === "upload") {
    const ext = String(field.get("ext") || (file.name.split(".").pop() || "")).toLowerCase(), type = (file.type || "").split(";")[0].trim().toLowerCase();
    if (!MIME[ext] || !MIME[ext].includes(type)) return json(415, { error: "unsupported_type", ext, mime: type });
    if (ext === "pdf" && new TextDecoder().decode(bytes.slice(0, 5)) !== "%PDF-") return json(415, { error: "not_a_pdf" });
    const sourceUrl = String(field.get("source_url") || "").trim();
    if (sourceUrl && !/^https:\/\/[^\s]{4,500}$/.test(sourceUrl)) return json(400, { error: "invalid_source_url" });
    const path = `${root}files/${sha}.${ext}`;
    const args = { ...ident, sha256: sha, ext, bytes: bytes.length, mime: type, path, source_url: sourceUrl };
    // every database check runs before the bytes are stored (identity, package open, provider in country, derived path)
    const pre = await rpc("precheck_upload", args);
    if (pre.error) { const f = fixedError(pre.error); return json(f.status === 422 && /finalised/.test(String(pre.error.message)) ? 409 : f.status, f.body) }
    if (!pre.data?.ok) return json(pre.data?.held === "HELD:SWITCHED_OFF" ? 503 : 403, { error: "refused", held: pre.data?.held });
    // a retry after a stored-but-unrecorded upload finds the same object (same path for the same bytes) and records it
    try { await store(path, MIME[ext][0]) } catch { return json(500, { error: "storage_failed" }) }
    const { data, error } = await rpc("upload", args);
    if (error) { const f = fixedError(error); return json(f.status, { ...f.body, stored: path }) }
    return json(200, data);
  }

  // finalise: the READY manifest, last
  let manifest: any;
  try { manifest = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) } catch { return json(415, { error: "manifest_json_required" }) }
  if (!manifest || !Array.isArray(manifest.files) || !Array.isArray(manifest.items)) return json(415, { error: "manifest_files_and_items_required" });
  const mpath = `${root}manifest-${sha}.json`, margs = { ...ident, manifest_sha256: sha, manifest_path: mpath, manifest };
  // validated before it is stored: an incomplete manifest, another provider's candidate or a changed manifest stores nothing
  const pre = await rpc("precheck_finalise", margs);
  if (pre.error) { const f = fixedError(pre.error); return json(f.status === 422 ? 409 : f.status, f.body) }
  if (!pre.data?.ok) return json(pre.data?.held === "HELD:SWITCHED_OFF" ? 503 : pre.data?.held === "HELD:MANIFEST_INCOMPLETE" ? 409 : 403, { error: "held", ...pre.data });
  if (pre.data?.replay) return json(200, pre.data);  // the same manifest again: the same receipt, nothing written
  try { await store(mpath, "application/json") } catch { return json(500, { error: "storage_failed" }) }
  const { data, error } = await rpc("finalise", margs);
  if (error) { const f = fixedError(error); return json(f.status, { ...f.body, stored: mpath }) }
  return json(data?.ok ? 200 : 409, { ...data, stored: mpath });
});
