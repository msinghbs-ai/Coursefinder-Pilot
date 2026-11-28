// CF-247 s1344 (S1-Build; SS-Programme-Control 28 Nov 2026 PC-20261128-DOT-STORAGE-IMPLEMENT, PC-20261128-1130-DOT-STORAGE): DOT's direct intake of
// one structured candidate file (JSONL), prepared switched OFF (setting dot_intake.on). The caller signs in as the DOT user; the database decides
// whether that user holds an active, unexpired dot_submitter assignment and whether the switch is on (public.svc_dot_intake_v1 gate) before
// anything is read or stored. The file is checked here (size from dot_intake.max_bytes, the SHA-256 the caller states, UTF-8 JSON lines, each an
// object), stored once at staging-boost/dot/<package>/<sha256>.jsonl (no overwrite; never staging-boost inbound or outbound) and submitted through
// the existing structured intake writer (svc_dot_intake_v1 submit -> svc_structured_intake_v1, submitter dot), whose receipt is returned. A replay
// of the same file finds the stored copy and the writer counts its candidates as duplicates. No canonical row, evidence or activation is written
// here; the existing proof on the platform's stored copies, the course binding and the admission rules decide.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "dot-intake-v0.1.0";
const json = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify({ ...body, version: VERSION }), { status, headers: { "content-type": "application/json" } });
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const noSession = { persistSession: false, autoRefreshToken: false };
const PKG = /^[a-z0-9][a-z0-9._-]{2,80}$/, SHA = /^[0-9a-f]{64}$/;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const auth = req.headers.get("authorization") || "";
  if (!auth.toLowerCase().startsWith("bearer ")) return json(401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return json(500, { error: "service_configuration_error" });
  const { data: who, error: whoErr } = await createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: noSession }).auth.getUser();
  if (whoErr || !who?.user?.id) return json(401, { error: "authentication_required" });
  const svc = createClient(url, service, { auth: noSession });
  // the database decides first: the switch and an active, unexpired dot_submitter assignment
  const { data: gate, error: gateErr } = await svc.rpc("svc_dot_intake_v1", { p_action: "gate", p_args: { user_id: who.user.id } });
  if (gateErr) return json(500, { error: "gate_failed" });
  if (!gate?.ok) return json(gate?.held === "HELD:SWITCHED_OFF" ? 503 : 403, { error: "refused", held: gate?.held ?? "HELD:GATE" });

  let form: FormData;
  try { form = await req.formData() } catch { return json(400, { error: "multipart_form_required" }) }
  const pkg = String(form.get("package") || "").trim(), stated = String(form.get("sha256") || "").trim().toLowerCase(), file = form.get("file");
  if (!PKG.test(pkg)) return json(400, { error: "invalid_package" });
  if (!SHA.test(stated)) return json(400, { error: "invalid_sha256" });
  if (!(file instanceof File) || file.size === 0) return json(400, { error: "file_required" });
  if (file.size > Number(gate.max_bytes || 0)) return json(413, { error: "file_too_large", max_bytes: gate.max_bytes });
  const bytes = new Uint8Array(await file.arrayBuffer());
  const sha = hex(await crypto.subtle.digest("SHA-256", bytes));
  if (sha !== stated) return json(422, { error: "sha256_mismatch", stated, computed: sha });  // nothing stored, nothing submitted
  let items: unknown[];
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    items = text.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => JSON.parse(l));
    if (!items.length || items.some((x) => !x || typeof x !== "object" || Array.isArray(x))) throw new Error("not objects");
  } catch { return json(415, { error: "jsonl_objects_required" }) }

  const path = `dot/${pkg}/${sha}.jsonl`;
  const up = await svc.storage.from("staging-boost").upload(path, bytes, { contentType: "application/x-ndjson", upsert: false });
  if (up.error && !/exists|duplicate|409/i.test(String((up.error as any).statusCode ?? "") + " " + up.error.message)) return json(500, { error: "storage_failed" });
  const { data: out, error: subErr } = await svc.rpc("svc_dot_intake_v1", { p_action: "submit", p_args: { user_id: who.user.id, package: pkg, sha256: sha, path, items } });
  if (subErr) {  // only the platform's own INVALID_INPUT text reaches the caller, never a raw database message
    const m = String(subErr.message || "");
    return json(m.startsWith("INVALID_INPUT:") ? 422 : 500, { error: m.startsWith("INVALID_INPUT:") ? "refused" : "submit_failed", reason: m.startsWith("INVALID_INPUT:") ? m.slice(0, 200) : undefined, stored: path });
  }
  return json(200, { ok: true, package: pkg, sha256: sha, stored: path, replay: !!up.error, receipt: out?.receipt ?? null });
});
