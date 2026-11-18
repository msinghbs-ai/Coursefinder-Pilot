import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { applySpec, missingHeaders, rowKeyAndHash, type Spec } from "../_shared/cf247-layer1-spec.ts";
import { fetchBytes, readTable } from "../_shared/cf247-layer1-read.ts";
import { extractHtmlTables } from "../_shared/cf247-html-table.js";

// CF-247 Wave 2 PR C (S2-Build; Platform Admin 17 Nov 2026 17:55, 19:08, 19:58, 22:04, 23:02). The generic Layer 1 declarative runner for
// sources whose parser is AI-built (a strict JSON spec, checked by security.layer1_parser_spec_validate_v1; nothing here evaluates code or builds SQL).
// Actions:
//   status   { ok, version }.
//   dry_run  { induction_id }: reads the first layer1.declarative_dry_run_rows rows of a wizard draft's source with the draft's spec, writes nothing
//            to staging, and records the counts with svc_layer1_induction_dry_run_record (a passing dry run switches nothing on). Curator and above,
//            or the service role.
//   apply    { source_id, run_id?, offset? }: for an active, unpaused source with approved terms (REQ-68) and an undrifted AI-built parser. One call
//            reads layer1.declarative_batch_rows rows from offset; the answer gives run_id and next_offset until has_more is false, and the last
//            call closes the run (staged rows not seen are marked departed, staging only). Service role only.
// Each call fetches the file (kept as evidence on the first call; a changed file stops the run), checks the headers against the spec (a missing
// header halts the run and flags the parser for re-inference, svc_layer1_parser_drift_record), turns rows into canonical records, and stages them
// in chunks of layer1.declarative_chunk_rows with a row key and hash. Course and provider registers apply their new and changed records through
// svc_layer1_apply_register_records in chunks of layer1.register_apply_chunk; the other record types are staged for review. Every record names the
// enrichment categories it leaves open; Australian postcodes are flagged against the ABS postcode-to-SUA shares.
const VERSION = "1.1.0";
const APPLY_FN = "public.svc_layer1_apply_register_records";
// 1.1.0 (18 Nov 2026, Platform Admin 10:31): campuses, provider accreditations and grade scale conversions, and a course's study load and empty
// reason, are applied by public.svc_layer1_apply_baseline_records_v1 (fills only what is not held; never overwrites, publishes or deletes).
const BASELINE_FN = "public.svc_layer1_apply_baseline_records_v1";
const isApplied = (t: any) => t?.apply === APPLY_FN || t?.apply === BASELINE_FN;
const courseExtras = (recs: Record<string, unknown>[]) => recs.filter((x) => !empty(x.study_load) || !empty(x.empty_reason_code));

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" } });
const fail = (error: string, status = 200) => json({ ok: false, error }, status);
const clean = (v: unknown, max = 300) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, max);
const isUuid = (v: unknown) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(v ?? ""));
const MIME: Record<string, string> = { csv: "text/csv", xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", json: "application/json", html_table: "text/html" };

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

// G2: sizes come from Settings › Pipeline settings (layer1.*); the second value is used only if a setting cannot be read (fixed: fallback)
async function settings(service: any) {
  const s = (await rpc(service, "svc_layer1_register_settings_v1", {})) || {};
  const n = (k: string, d: number) => { const v = Math.floor(Number(s[k])); return v >= 1 ? v : d; };
  return {
    chunk: n("layer1.declarative_chunk_rows", 200), dryRows: n("layer1.declarative_dry_run_rows", 100), batch: n("layer1.declarative_batch_rows", 2000),
    maxRows: n("layer1.declarative_max_rows", 200000), maxMb: n("layer1.declarative_max_file_mb", 50), applyChunk: n("layer1.register_apply_chunk", 20),
  };
}

async function sha256(bytes: Uint8Array) {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

const empty = (v: unknown) => v === null || v === undefined || String(v).trim() === "";

// canonical records → staged rows with key, hash, open categories and postcode flag
async function toRows(service: any, spec: Spec, recordType: string, country: string, records: Record<string, unknown>[], ctx: any) {
  const routes: Record<string, string[]> = ctx.gap_routes?.[recordType] || {};
  const applied = isApplied(ctx.targets?.[recordType]);
  const seen = new Set<string>();
  const out: any[] = [];
  let duplicates = 0;
  for (const rec of records) {
    const { key, hash } = await rowKeyAndHash(spec, rec);
    if (!key.replace(/\|/g, "")) continue;
    if (seen.has(key)) { duplicates++; continue; }
    seen.add(key);
    const gaps = Object.entries(routes).filter(([, fields]) => fields.some((f) => empty(rec[f]))).map(([cat]) => cat);
    out.push({ key, hash, record: rec, gaps, postcode_flag: null as string | null, apply_state: applied ? "applied" : "staged_review" });
  }
  if (country === "AU") {
    const pcs = [...new Set(out.map((r) => clean(r.record.postcode, 10)).filter((p) => /^[0-9]{4}$/.test(p)))];
    if (pcs.length) {
      const flags = (await rpc(service, "svc_layer1_declarative_postcodes_v1", { p_postcodes: pcs })) || {};
      for (const r of out) { const p = clean(r.record.postcode, 10); if (flags[p]) r.postcode_flag = flags[p]; }
    }
  }
  return { rows: out, duplicates, applied };
}

function tally(rows: any[], categories: string[]) {
  const gaps: Record<string, number> = Object.fromEntries(categories.map((c) => [c, 0]));
  for (const r of rows) for (const g of r.gaps) gaps[g] = (gaps[g] || 0) + 1;
  return { gaps, postcode_escalations: rows.filter((r) => r.postcode_flag === "layer4_review" || r.postcode_flag === "outside_sua").length };
}

async function dryRun(service: any, inductionId: string) {
  const cfg = await settings(service);
  const ctx = await rpc(service, "svc_layer1_declarative_source_v1", { p_source_id: null, p_induction_id: inductionId });
  const ind = ctx?.induction;
  if (!ind) return fail("The draft was not found.");
  const p = ind.payload || {};
  const spec = p.parser_spec as Spec | null;
  const recordType = clean(p.target_record_type || spec?.record_type, 40);
  const url = clean(p.source_url, 2000);
  const record = async (status: "passed" | "failed", c: Record<string, number>, message: string, reader = "") =>
    rpc(service, "svc_layer1_induction_dry_run_record", { p_id: inductionId, p_result: { status, rows_read: c.rows_read || 0, inserts: c.inserts || 0, updates: c.updates || 0,
      departures: 0, postcode_escalations: c.postcode_escalations || 0, reader: reader || `layer1-declarative-runner ${VERSION}`, message } });
  if (!spec || typeof spec !== "object") { await record("failed", {}, "The draft has no parser spec yet (step 3, AI Auto-Map)."); return json({ ok: true, status: "failed", message: "no parser spec" }); }
  if (!/^https?:\/\//i.test(url)) { await record("failed", {}, "The draft has no source web address."); return json({ ok: true, status: "failed", message: "no source url" }); }
  const run = await rpc(service, "svc_layer1_declarative_run_start_v1", { p_source_id: ind.source_id || null, p_induction_id: inductionId, p_mode: "dry_run", p_record_type: recordType, p_reader: `layer1-declarative-runner ${VERSION}` });
  try {
    const bytes = await fetchBytes(url, cfg.maxMb * 1024 * 1024);
    const table = readTable(bytes, spec.format, spec.source || {}, cfg.dryRows);
    const missing = missingHeaders(spec, table.headers);
    const check = await rpc(service, "svc_layer1_parser_spec_validate_v1", { p_spec: spec, p_record_type: recordType, p_columns: table.headers });
    if (missing.length || check?.ok !== true) {
      const msg = missing.length ? `Columns missing from the source: ${missing.slice(0, 10).join(", ")}.` : `The parser spec does not pass the check: ${(check?.errors || []).slice(0, 5).join(" ")}`;
      await rpc(service, "svc_layer1_declarative_run_finish_v1", { p_run_id: run, p_status: missing.length ? "halted_drift" : "failed", p_counts: { rows_read: table.rows.length }, p_message: msg });
      await record("failed", { rows_read: table.rows.length }, msg);
      return json({ ok: true, run_id: run, status: "failed", message: msg });
    }
    const { records, errors } = applySpec(spec, table.rows, undefined, clean(p.scheme, 40));
    const country = clean(ind.country_code || ctx?.source?.country_code, 2).toUpperCase();
    const { rows, duplicates, applied } = await toRows(service, spec, recordType, country, records, ctx);
    let inserts = 0, updates = 0, unchanged = 0;
    for (let i = 0; i < rows.length; i += cfg.chunk) {
      const r = await rpc(service, "svc_layer1_declarative_stage_v1", { p_run_id: run, p_rows: rows.slice(i, i + cfg.chunk), p_write: false });
      inserts += Number(r?.inserts || 0); updates += Number(r?.updates || 0); unchanged += Number(r?.unchanged || 0);
    }
    const t = tally(rows, ctx.categories || []);
    // Track B: how many tables the page holds, so a wrong source.table_index is easy to see
    const pageTables = spec.format === "html_table" ? extractHtmlTables(new TextDecoder("utf-8").decode(bytes)).length : undefined;
    const counts = { rows_read: table.rows.length, records: rows.length, rejected: table.rows.length - records.length, duplicates, inserts, updates, unchanged, ...(pageTables !== undefined ? { tables_on_page: pageTables } : {}),
      would_apply: applied ? inserts + updates : 0, staged_review: applied ? 0 : inserts + updates, postcode_escalations: t.postcode_escalations, gaps: t.gaps };
    const passed = rows.length > 0;
    const msg = `${rows.length} records from the first ${table.rows.length} rows${errors.length ? `; ${errors.length} problems, first: ${errors[0]}` : ""}${duplicates ? `; ${duplicates} duplicate keys` : ""}.`;
    await rpc(service, "svc_layer1_declarative_run_finish_v1", { p_run_id: run, p_status: "completed", p_counts: counts, p_message: msg });
    await record(passed ? "passed" : "failed", counts as any, msg);
    return json({ ok: true, version: VERSION, run_id: run, status: passed ? "passed" : "failed", counts, problems: errors.slice(0, 10) });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await rpc(service, "svc_layer1_declarative_run_finish_v1", { p_run_id: run, p_status: "failed", p_counts: {}, p_message: msg }).catch(() => null);
    await record("failed", {}, msg.slice(0, 500)).catch(() => null);
    return fail(msg);
  }
}

async function applyRun(service: any, body: any) {
  const cfg = await settings(service);
  const sourceId = String(body.source_id);
  const ctx = await rpc(service, "svc_layer1_declarative_source_v1", { p_source_id: sourceId, p_induction_id: null });
  const par = ctx?.parser, ops = ctx?.operations, p = ctx?.induction?.payload || {};
  if (!par || par.parser_kind !== "ai_built") return fail("This source is not read by an AI-built parser (a hardcoded parser runs on its own worker).");
  if (par.drift_flagged_at) return fail("The parser is flagged for layout drift; it is re-inferred before the source is read again.");
  if (!ops?.active || ops?.paused) return fail("The source is not active, or it is paused (Layer 1 › Sources).");
  if (p.terms_status !== "approved") return fail("The source's terms are not approved (REQ-68).");
  const spec = par.parser_spec as Spec;
  const recordType = clean(par.target_record_type || spec?.record_type, 40);
  const country = clean(ctx?.source?.country_code || ctx?.induction?.country_code, 2).toUpperCase();
  const url = clean(p.source_url || ctx?.source?.url, 2000);
  const scheme = clean(p.scheme, 40);
  const applied = isApplied(ctx.targets?.[recordType]);
  const baseline = ctx.targets?.[recordType]?.apply === BASELINE_FN;
  if (applied && !scheme && recordType !== "grade_scale_conversions") return fail("The source has no registration scheme (wizard step 1); a register cannot be applied without one.");
  if (!/^https?:\/\//i.test(url)) return fail("The source has no web address.");
  const offset = Math.max(0, Math.floor(Number(body.offset) || 0));

  let run: string = isUuid(body.run_id) ? String(body.run_id) : "";
  let jobId: string | null = null, evidenceId: string | null = null;
  const bytes = await fetchBytes(url, cfg.maxMb * 1024 * 1024);
  const hash = await sha256(bytes);
  if (!run) {
    if (offset !== 0) return fail("A new run starts at offset 0.");
    run = await rpc(service, "svc_layer1_declarative_run_start_v1", { p_source_id: sourceId, p_induction_id: ctx?.induction?.id || null, p_mode: "apply", p_record_type: recordType, p_reader: `layer1-declarative-runner ${VERSION}` });
    jobId = await rpc(service, "svc_layer1_start_job", { p_country_code: country, p_source_id: sourceId, p_payload: { runtime: "supabase_edge", version: VERSION, mode: "layer1_declarative", run_id: run, record_type: recordType } });
    evidenceId = await rpc(service, "svc_layer1_record_evidence", { p_source_id: sourceId, p_job_id: jobId, p_source_url: url, p_storage_path: null, p_content_hash: hash,
      p_mime_type: MIME[spec.format] || "application/octet-stream", p_metadata: { reader: `layer1-declarative-runner ${VERSION}`, run_id: run, attribution_text: clean(spec.attribution_text || p.attribution_text, 1000), spec_version: par.spec_version } });
    await rpc(service, "svc_layer1_declarative_run_note_v1", { p_run_id: run, p_job_id: jobId, p_evidence_id: evidenceId });
  }
  const finish = async (status: string, counts: Record<string, unknown>, message: string) => {
    const r = await rpc(service, "svc_layer1_declarative_run_finish_v1", { p_run_id: run, p_status: status, p_counts: counts, p_message: message });
    const job = jobId || body.job_id;
    if (isUuid(job)) await rpc(service, "svc_layer1_finish_job", { p_job_id: job, p_status: status === "completed" ? "completed" : "failed", p_result: r?.counts || counts, p_error: status === "completed" ? null : message }).catch(() => null);
    return r;
  };
  try {
    if (body.content_hash && body.content_hash !== hash) { await finish("failed", { offset }, "The source file changed during the run; start a new run."); return fail("The source file changed during the run."); }
    const table = readTable(bytes, spec.format, spec.source || {});
    if (table.rows.length > cfg.maxRows) { const m = `The source has ${table.rows.length} rows, more than layer1.declarative_max_rows (${cfg.maxRows}).`; await finish("failed", { rows_read: table.rows.length }, m); return fail(m); }
    const missing = missingHeaders(spec, table.headers);
    if (missing.length) {
      const m = `Columns missing from the source: ${missing.slice(0, 10).join(", ")}.`;
      await rpc(service, "svc_layer1_parser_drift_record", { p_source_id: sourceId, p_flagged: true, p_message: m });
      await finish("halted_drift", { rows_read: table.rows.length }, m);
      return json({ ok: false, run_id: run, status: "halted_drift", error: m });
    }
    const slice = table.rows.slice(offset, offset + cfg.batch);
    const { records, errors } = applySpec(spec, slice, undefined, scheme);
    const { rows, duplicates } = await toRows(service, spec, recordType, country, records, ctx);
    const c = { inserts: 0, updates: 0, unchanged: 0, applied: 0, provider_created: 0, course_created: 0, baseline_written: 0, conflicts: 0 };
    const evidence = evidenceId || body.evidence_id || null;
    for (let i = 0; i < rows.length; i += cfg.chunk) {
      const part = rows.slice(i, i + cfg.chunk);
      const r = await rpc(service, "svc_layer1_declarative_stage_v1", { p_run_id: run, p_rows: part, p_write: true });
      c.inserts += Number(r?.inserts || 0); c.updates += Number(r?.updates || 0); c.unchanged += Number(r?.unchanged || 0);
      if (applied) {
        const changed = new Set<string>((r?.changed_keys || []) as string[]);
        const recs = part.filter((x) => changed.has(x.key)).map((x) => x.record);
        for (let j = 0; j < recs.length; j += cfg.applyChunk) {
          const part2 = recs.slice(j, j + cfg.applyChunk);
          if (baseline) {
            const b = await rpc(service, "svc_layer1_apply_baseline_records_v1", { p_record_type: recordType, p_country_code: country, p_source_id: sourceId, p_evidence_id: evidence, p_registration_scheme: scheme || null, p_records: part2 });
            c.applied += part2.length; c.baseline_written += Number(b?.written || 0); c.conflicts += Number(b?.provider_not_registered || 0) + Number(b?.invalid || 0);
            continue;
          }
          const a = await rpc(service, "svc_layer1_apply_register_records", { p_country_code: country, p_source_id: sourceId, p_evidence_id: evidence, p_registration_scheme: scheme, p_records: part2 });
          c.applied += part2.length;
          c.provider_created += Number(a?.provider_created || 0); c.course_created += Number(a?.course_created || 0); c.conflicts += Number(a?.conflicts || 0);
          const extras = recordType === "course_register" ? courseExtras(part2) : [];
          if (extras.length) {
            const b = await rpc(service, "svc_layer1_apply_baseline_records_v1", { p_record_type: "course_register", p_country_code: country, p_source_id: sourceId, p_evidence_id: evidence, p_registration_scheme: scheme, p_records: extras });
            c.baseline_written += Number(b?.written || 0);
          }
        }
      }
    }
    const t = tally(rows, ctx.categories || []);
    const nextOffset = offset + slice.length;
    const hasMore = nextOffset < table.rows.length;
    const counts = { rows_read: table.rows.length, offset, batch_rows: slice.length, records: rows.length, rejected: slice.length - records.length, duplicates, ...c,
      staged_review: applied ? 0 : c.inserts + c.updates, postcode_escalations: t.postcode_escalations, gaps: t.gaps };
    if (!hasMore) {
      const r = await finish("completed", counts, `${table.rows.length} rows read${errors.length ? `; problems in the last call, first: ${errors[0]}` : ""}.`);
      return json({ ok: true, version: VERSION, run_id: run, has_more: false, counts: r?.counts || counts, problems: errors.slice(0, 10) });
    }
    return json({ ok: true, version: VERSION, run_id: run, has_more: true, next_offset: nextOffset, content_hash: hash, job_id: jobId || body.job_id || null, evidence_id: evidence, counts, problems: errors.slice(0, 10) });
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    await finish("failed", { offset }, m).catch(() => null);
    return fail(m);
  }
}

async function curator(req: Request, service: any, url: string, anon: string) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Sign in to run a dry run.");
  const user = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
  const { data: { user: u }, error } = await user.auth.getUser(token);
  if (error || !u) throw new Error("Your session has ended; sign in again.");
  if (!(await rpc(service, "svc_layer1_authorize_curator", { p_user_id: u.id }))) throw new Error("A dry run needs Curator or above.");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("POST required", 405);
  const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!, key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const service = createClient(url, key, { auth: { persistSession: false } });
  let body: any = {};
  try { body = await req.json(); } catch { body = {}; }
  const bearer = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  const isService = !!bearer && bearer === key;
  try {
    if (body.action === "status") return json({ ok: true, version: VERSION });
    if (body.action === "dry_run") {
      if (!isService) await curator(req, service, url, anon);
      if (!isUuid(body.induction_id)) return fail("induction_id is required.");
      return await dryRun(service, String(body.induction_id));
    }
    if (body.action === "apply") {
      if (!isService) return fail("An apply run is started by the service role only.", 403);
      if (!isUuid(body.source_id)) return fail("source_id is required.");
      return await applyRun(service, body);
    }
    return fail("Unknown action; use status, dry_run or apply.", 400);
  } catch (e) {
    return fail(e instanceof Error ? e.message : String(e), 401);
  }
});
