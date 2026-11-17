// Guards: Mapper Contract v1.1 (S1-RM-Design, 17 Nov 2026 20:10), the Wave 2 addenda (Platform Admin 17 Nov 2026 19:08) and the AI routing choice (Platform Admin 20:30): the AI induction mapper suggests and writes nothing, its model call goes through the coverage-sweep worker on route layer1_induction_map, and every AI-built parser spec passes a strict declarative check (allowed targets per record type, no SQL or code)
// CF-247 S585. Migration 20261117221000_cf247_w2a_layer1_parser_spec_contract.sql; edge function layer1-ai-induction-mapper 1.0.0; worker coverage-sweep v1.0.7 mode induction_map (induction.ts); shared engine _shared/cf247-layer1-spec.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261117221000_cf247_w2a_layer1_parser_spec_contract.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/layer1-ai-induction-mapper/index.ts', 'utf8')
const eng = fs.readFileSync('supabase/functions/_shared/cf247-layer1-spec.ts', 'utf8')
const ind = fs.readFileSync('supabase/functions/coverage-sweep/induction.ts', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const fns = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions
const types = ['course_register', 'provider_register', 'tuition_fees', 'study_rules', 'destination_metrics', 'career_outcomes', 'scholarships']

test('every one of the seven record types has a fixed target table and allowed fields', () => {
  for (const t of types) expect(mig).toContain(`'${t}', jsonb_build_object('target_table', `)
  expect(mig).toContain("raise exception 'post-check: a record type has no targets'")
})

test('the spec check refuses unknown keys, targets, types and transforms, and needs attribution, a unique key and expected headers', () => {
  expect(mig).toContain("if k <> all (array['spec_version', 'record_type', 'target_table', 'format', 'source', 'expected_headers', 'fields', 'unique_key', 'attribution_text', 'evidence', 'currency']) then")
  expect(mig).toContain("v_ops constant text[] := array['trim', 'upper', 'lower', 'strip_currency', 'date_format', 'default', 'map_values', 'first_token'];")
  expect(mig).toContain("e := e || 'attribution_text is required (shown beside every value).'::text;")
  expect(mig).toContain("e := e || 'expected_headers is required for csv, xlsx and html_table (layout drift is checked against it).'::text;")
  expect(mig).toContain("if p_spec->>'target_table' is distinct from t->>'target_table' then")
  expect(mig).toContain("raise exception 'post-check: an invalid spec was accepted'")
})

test('the mapper: status and map only, Curator or above (Contract v1.2), the model through the worker on its route, writes nothing', () => {
  expect(fn).toContain('if (body.action === "status") return json({ ok: true, version: VERSION, model: rt.model });')
  expect(fn).toContain('await rpc(service, "svc_layer1_authorize_curator", { p_user_id: u.id })')
  expect(mig).toContain('where ur.user_id = p_user_id and r.status = \'active\' and r.rank >= 3')
  expect(fn).toContain('const nonce = await rpc(service, "svc_pilot_issue_nonce", { p_function: "coverage-sweep" });')
  expect(fn).toContain('body: JSON.stringify({ mode: "induction_map", input }),')
  expect(fn).not.toMatch(/openrouter\.ai|chat\/completions|OPENROUTER_API_KEY/)
  const rpcs = [...fn.matchAll(/rpc\(service, "([a-z0-9_]+)"/g)].map((m) => m[1])
  // the only write path is svc_layer1_parser_record, used by the re-infer job (PR B, s586); map writes nothing
  expect([...new Set(rpcs)].sort()).toEqual(['svc_enrichment_categories', 'svc_layer1_authorize_curator', 'svc_layer1_induction_map_route_v1', 'svc_layer1_induction_read', 'svc_layer1_parser_record',
    'svc_layer1_parser_reinfer_note_v1', 'svc_layer1_parser_reinfer_queue_v1', 'svc_layer1_parser_spec_validate_v1', 'svc_layer1_register_settings_v1', 'svc_pilot_consume_nonce', 'svc_pilot_issue_nonce'])
  const mapPath = fn.slice(fn.indexOf('if (body.action !== "map")'))
  expect(mapPath).not.toContain('svc_layer1_parser_record')
  expect(fn).not.toMatch(/\.from\(["'][a-z_]+["']\)\.(insert|update|upsert|delete)/)
  expect(fns['layer1-ai-induction-mapper']).toBe(false)  // PR B: the re-infer job calls it with a one-time nonce; a person's JWT is checked in the function
  expect(fn).toContain('await caller(req, service, url, anon);')
})

test('the route: one model, the central Qwen3 30B, provisional qualification on the 13 Nov decision, caps on the route; the worker calls through cascadeFetch', () => {
  expect(mig).toContain("values ('layer1_induction_map', 'Layer 1 induction field mapping', 'Layer 1', null, 'induction_map', null, array['qwen3-30b'], 2, 200,")
  expect(mig).toContain("'routed_single'")
  expect(mig).toContain("select 'layer1_induction_map', 'qwen3-30b', 'induction-map-v1', 'qualified', true,")
  expect(mig).toContain("('pipeline', 'reading.answer_tokens.induction_map', 'AI answer length: Layer 1 induction mapping',")
  expect(mig).toContain("return security.ai_route_v1('layer1_induction_map');")
  expect(worker).toContain('if (mode === "induction_map") {')
  expect(worker).toContain('await cascadeFetch(fetch, { service: "layer1_induction_map" }, "https://openrouter.ai/api/v1/chat/completions"')
  expect(worker).toContain('const route = await rpc("svc_layer1_induction_map_route_v1", {});')
  expect(ind).toContain('export const INDUCTION_PROMPT_VERSION = "induction-map-v1";')
  expect(ind).toContain('provider: { require_parameters: true, allow_fallbacks: false },')
  expect(fs.readFileSync('docs/platform/ai-prompts.json', 'utf8')).toContain('"layer1_induction_map"')
})

test('the shared engine applies fixed types and transforms only; no eval or SQL', () => {
  expect(eng).not.toMatch(/\beval\(|new Function\(|\.rpc\(|from\(["']/)
  for (const t of ['integer', 'numeric', 'currency_amount', 'date', 'boolean', 'url', 'code']) expect(eng).toContain(`case "${t}"`)
  expect(eng).toContain('export function missingHeaders(spec: Spec, headers: string[])')
})
