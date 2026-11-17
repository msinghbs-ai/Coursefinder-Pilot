import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { applySpec, type Spec } from "../_shared/cf247-layer1-spec.ts";

// CF-247 Wave 2, PR A (S2-Build; Mapper Contract v1.2, docs/platform/LAYER1-AI-INDUCTION-MAPPER-CONTRACT.md in the admin repository).
// AI Auto-Map for Layer 1 › Sources › + Add source, step 3. Actions:
//   status: { ok, version, model }. The wizard enables AI Auto-Map only when this answers ok.
//   map:    field and category suggestions for a sample, and a parser spec for the target record type, checked by
//           security.layer1_parser_spec_validate_v1 and test-applied to the sample. It writes nothing but a call record (daily limit).
// The model is called by the coverage-sweep worker (mode induction_map), the only caller of the model provider: the route layer1_induction_map
// gives its one model, caps and holds, and every attempt is kept in pipeline.ai_invocations (Platform Admin 17 Nov 2026 20:30). A person decides every mapping.
const VERSION = "1.0.0";
const FUNCTION_NAME = "layer1-ai-induction-mapper";
const FORMAT_OF: Record<string, string> = { csv_file: "csv", xlsx_file: "xlsx", json_api: "json", html_pages: "html_table" };
const CONNECTORS = ["csv_file", "xlsx_file", "json_api", "html_pages", "pdf_document", "manual_upload"];

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

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function route(service: any) {
  const r = (await rpc(service, "svc_layer1_induction_map_route_v1", {})) || {};
  return { model: String(r.model || ""), held: !!r.held, why: String(r.held_reason || r.held_kind || "") };
}

async function caller(req: Request, service: any, url: string, anon: string) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Sign in to use AI Auto-Map.");
  const user = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
  const { data: { user: u }, error } = await user.auth.getUser(token);
  if (error || !u) throw new Error("Your session has ended; sign in again.");
  if (!(await rpc(service, "svc_layer1_authorize_curator", { p_user_id: u.id }))) throw new Error("AI Auto-Map needs Curator or above.");
  return u.id as string;
}

// the worker reads the route's one model, sends the induction request (coverage-sweep/induction.ts) and records the call
async function askWorker(service: any, url: string, serviceKey: string, input: Record<string, unknown>) {
  const nonce = await rpc(service, "svc_pilot_issue_nonce", { p_function: "coverage-sweep" });
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 120000); // fixed: API time-out
  try {
    const r = await fetch(`${url}/functions/v1/coverage-sweep`, {
      method: "POST", signal: ctl.signal,
      headers: { "content-type": "application/json", "x-cf-run-nonce": String(nonce), authorization: `Bearer ${serviceKey}`, apikey: serviceKey },
      body: JSON.stringify({ mode: "induction_map", input }),
    });
    const body = await r.json().catch(() => ({}));
    if (!body?.ok) throw new Error(clean(body?.error || `the AI worker answered ${r.status}`, 300));
    return { parsed: body.answer, model: String(body.model || "") };
  } finally {
    clearTimeout(timer);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("POST required", 405);
  const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!, key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const service = createClient(url, key, { auth: { persistSession: false } });
  let body: any = {};
  try { body = await req.json(); } catch { body = {}; }
  try { await caller(req, service, url, anon); } catch (e) { return fail(e instanceof Error ? e.message : String(e), 401); }

  try {
    const rt = await route(service);
    if (!rt.model) return fail("No qualified model is routed for the induction mapping (Models & services › layer1_induction_map).");
    if (rt.held) return fail(`The induction mapping is held: ${rt.why || "route held"}.`);
    if (body.action === "status") return json({ ok: true, version: VERSION, model: rt.model });
    if (body.action !== "map") return fail("Unknown action; use status or map.", 400);

    // the request (Mapper Contract v1.1)
    const recordType = clean(body.target_record_type, 40);
    const connector = clean(body.connector_type, 40);
    const country = clean(body.country_code, 2).toUpperCase();
    if (!isUuid(body.induction_id)) return fail("induction_id is required.");
    if (!CONNECTORS.includes(connector)) return fail("connector_type is not one the wizard offers.");
    const columns: string[] = Array.isArray(body.sample?.columns) ? body.sample.columns.slice(0, 300).map((c: unknown) => clean(c, 200)) : []; // fixed: input-safety bound
    const rows: string[][] = Array.isArray(body.sample?.rows) ? body.sample.rows.slice(0, 20).map((r: unknown) => (Array.isArray(r) ? r : []).slice(0, columns.length).map((v) => clean(v, 300))) : []; // fixed: input-safety bound (contract: 20 rows)
    if (!columns.length || columns.some((c) => !c)) return fail("The sample needs its column names.");
    if (new Set(columns).size !== columns.length) return fail("Two sample columns have the same name; rename one before mapping.");
    const targetFields = (Array.isArray(body.target_fields) ? body.target_fields : []).map((f: any) => ({ field: clean(f?.field, 80), label: clean(f?.label, 120), category_key: clean(f?.category_key, 40) })).filter((f: any) => f.field);
    const categories = (Array.isArray(body.categories) ? body.categories : []).map((c: any) => ({ key: clean(c?.key, 40), label: clean(c?.label, 120), description: clean(c?.description, 300) })).filter((c: any) => c.key);
    if (!targetFields.length || !categories.length) return fail("The target fields and categories are missing from the request.");

    // what the record type allows, and the draft's attribution
    const check0 = await rpc(service, "svc_layer1_parser_spec_validate_v1", { p_spec: {}, p_record_type: recordType, p_columns: null });
    const targets = check0?.targets;
    if (!targets) return fail(`Unknown target record type "${recordType}".`);
    const induction = await rpc(service, "svc_layer1_induction_read", { p_id: body.induction_id, p_source_id: null });
    if (!induction) return fail("The draft was not found; save it and try again.");
    const attribution = clean(induction?.payload?.attribution_text ?? induction?.attribution_text ?? "", 1000);

    const { parsed, model } = await askWorker(service, url, key, {
      target_record_type: recordType, country_code: country, connector_type: connector, sample: { columns, rows },
      platform_fields: targetFields, categories,
      parser_targets: Object.entries(targets.fields).map(([k, v]: [string, any]) => ({ target: k, type: v.type, required: !!v.required })),
      parser_key: targets.key,
    });

    // suggestions: one per source column, names only from the lists
    const fieldCat = new Map(targetFields.map((f: any) => [f.field, f.category_key]));
    const catKeys = new Set(categories.map((c: any) => c.key));
    const seen = new Set<string>();
    const suggestions = (Array.isArray(parsed?.suggestions) ? parsed.suggestions : []).flatMap((s: any) => {
      const src = clean(s?.source_field, 200);
      if (!columns.includes(src) || seen.has(src)) return [];
      seen.add(src);
      const tf = fieldCat.has(clean(s?.target_field, 80)) ? clean(s?.target_field, 80) : null;
      let ck = catKeys.has(clean(s?.category_key, 40)) ? clean(s?.category_key, 40) : null;
      if (tf && fieldCat.get(tf)) ck = fieldCat.get(tf) as string;
      const conf = Math.max(0, Math.min(1, Number(s?.confidence) || 0));
      return [{ source_field: src, target_field: tf, category_key: ck, confidence: Math.round(conf * 100) / 100, reason: clean(s?.reason, 200) }];
    });

    // the parser spec: fixed parts from the platform, mappings from the model, then the strict check
    const format = FORMAT_OF[connector];
    let parser_spec: Spec | null = null;
    let validation = { ok: false, errors: [] as string[] };
    if (!format) {
      validation.errors.push(`A parser spec is not built for ${connector}; this source needs a reader written in code.`);
    } else {
      const fields = (Array.isArray(parsed?.spec_fields) ? parsed.spec_fields : []).flatMap((f: any) => {
        const target = clean(f?.target, 80), source = clean(f?.source, 200);
        if (!targets.fields[target] || !columns.includes(source)) return [];
        const transforms = (Array.isArray(f?.transforms) ? f.transforms : []).slice(0, 8).map((t: any) => (t && "arg" in t ? { op: clean(t.op, 30), arg: t.arg } : { op: clean(t?.op, 30) }));
        return [{ source, target, type: targets.fields[target].type, ...(targets.fields[target].required ? { required: true } : {}), ...(transforms.length ? { transforms } : {}) }];
      }).filter((f: any, i: number, all: any[]) => all.findIndex((x) => x.target === f.target) === i);
      const mapped = new Set(fields.map((f: any) => f.target));
      const modelKey = (Array.isArray(parsed?.unique_key) ? parsed.unique_key : []).map((k: unknown) => clean(k, 80)).filter((k: string) => mapped.has(k));
      const unique_key = [...new Set([...targets.key.filter((k: string) => mapped.has(k)), ...modelKey])];
      const headerRow = Math.floor(Number(parsed?.header_row));
      parser_spec = {
        spec_version: 1, record_type: recordType, target_table: targets.target_table, format,
        ...(format !== "json" ? { expected_headers: columns } : {}),
        ...(format !== "json" && headerRow >= 1 && headerRow <= 200 ? { source: { header_row: headerRow } } : {}),
        fields, unique_key, attribution_text: attribution, evidence: { bind: "source_file" },
      } as Spec;
      const check = await rpc(service, "svc_layer1_parser_spec_validate_v1", { p_spec: parser_spec, p_record_type: recordType, p_columns: columns });
      const errors: string[] = Array.isArray(check?.errors) ? check.errors : [];
      if (!attribution) errors.push("Add the source's attribution text in step 2; the spec carries it beside every value.");
      // test-apply the spec to the sample rows
      const objects = rows.map((r) => Object.fromEntries(columns.map((c, i) => [c, r[i] ?? null])));
      const trial = errors.length ? { records: [], errors: [] as string[] } : applySpec(parser_spec, objects, 10);
      validation = { ok: errors.length === 0 && trial.errors.length === 0, errors: [...new Set([...errors, ...trial.errors])] };
    }
    return json({ ok: true, version: VERSION, model, suggestions, parser_spec, validation });
  } catch (e) {
    return fail(e instanceof Error ? e.message : String(e));
  }
});
