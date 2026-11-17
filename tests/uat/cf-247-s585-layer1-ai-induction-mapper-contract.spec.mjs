// Guards: Mapper Contract v1.1 (S1-RM-Design, 17 Nov 2026 20:10) and the Wave 2 addenda (Platform Admin 17 Nov 2026 19:08): the AI induction mapper suggests and writes nothing, uses one pinned model, and every AI-built parser spec passes a strict declarative check (allowed targets per record type, no SQL or code)
// CF-247 S585. Migration 20261117221000_cf247_w2a_layer1_parser_spec_contract.sql; edge function layer1-ai-induction-mapper 1.0.0; shared engine _shared/cf247-layer1-spec.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261117221000_cf247_w2a_layer1_parser_spec_contract.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/layer1-ai-induction-mapper/index.ts', 'utf8')
const eng = fs.readFileSync('supabase/functions/_shared/cf247-layer1-spec.ts', 'utf8')
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

test('the mapper: status and map only, Pipeline Operator or above, one pinned model, daily limit, writes nothing else', () => {
  expect(fn).toContain('if (body.action === "status") return json({ ok: true, version: VERSION, model });')
  expect(fn).toContain('await rpc(service, "svc_layer1_authorize_operator", { p_user_id: u.id })')
  expect(fn).toContain('if (!model || /(^|\\/)auto$/i.test(model)) return fail(')
  expect(fn).toContain('provider: { require_parameters: true, allow_fallbacks: false }')
  expect(fn).toContain('svc_layer1_mapper_call_v1')
  expect(fn).toContain('svc_layer1_parser_spec_validate_v1')
  const rpcs = [...fn.matchAll(/rpc\(service, "([a-z0-9_]+)"/g)].map((m) => m[1])
  expect([...new Set(rpcs)].sort()).toEqual(['svc_layer1_authorize_operator', 'svc_layer1_induction_read', 'svc_layer1_mapper_call_v1', 'svc_layer1_parser_spec_validate_v1', 'svc_layer1_register_settings_v1'])
  expect(fn).not.toMatch(/\.from\(["'][a-z_]+["']\)\.(insert|update|upsert|delete)/)
  expect(mig).toContain("('pipeline', 'layer1.induction_mapper_model', 'Layer 1 induction: pinned AI mapper model',")
  expect(fns['layer1-ai-induction-mapper']).toBe(true)
})

test('the shared engine applies fixed types and transforms only; no eval or SQL', () => {
  expect(eng).not.toMatch(/\beval\(|new Function\(|\.rpc\(|from\(["']/)
  for (const t of ['integer', 'numeric', 'currency_amount', 'date', 'boolean', 'url', 'code']) expect(eng).toContain(`case "${t}"`)
  expect(eng).toContain('export function missingHeaders(spec: Spec, headers: string[])')
})
