// Guards: Boost model benchmark (Platform Admin 17 Nov 2026 22:05 and 22:45): the named candidate models (Qwen3 30B, Mistral Small 3.2, MiMo v2.6 Flash) are asked the same study load reading for the same stored course pages through their own Models & services route, each directly and never as a fallback; the cohort takes the course's own page only; every call's cost reaches the AI spend ledger; nothing is staged or admitted and no model is qualified for admission; the route boost_extract stays pinned to one model
// CF-247 S600 (was s596; renumbered 18 Nov 2026, s596 is the Layer 1 runner spec). Migration 20261118020000_cf247_boost_benchmark, worker coverage-sweep v1.0.11 (mode boost_benchmark). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118020000_cf247_boost_benchmark.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const mode = IX.slice(IX.indexOf('if (mode === "boost_benchmark") {'), IX.indexOf('// v1.0.16 (18 Nov 2026, CF-247 S2 - BOOST, Platform Admin 07:08 decision 3 and 10:10): Boost multi-field reading.'))  // the benchmark mode ends where the multi-field mode starts (s621)

test('the benchmark has its own route with the three named allowed candidates; the extraction route stays pinned', () => {
  expect(code).toMatch(/values \('boost_extract_benchmark', 'Boost extraction benchmark \(study load\)', 'Boost', null, 'boost_benchmark', null, array\['qwen3-30b', 'mistral-small-3\.2', 'mimo-v2\.6-flash'\], 1, 2000,/)
  expect(code).toContain("if (select count(*) from pipeline.ai_model_catalogue where code in ('qwen3-30b', 'mistral-small-3.2', 'mimo-v2.6-flash') and status = 'allowed') <> 3 then")
  expect(code).toContain("raise exception 'post-check: the route does not hand out the three candidates: %'")
  expect(code).toContain("raise exception 'post-check: the route boost_extract is no longer pinned to one model'")
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications/)
  expect(code).toContain("raise exception 'post-check: no model may be qualified for admission by this change'")
})

test('a run is named by a setting, takes the course\'s own page only, and its job is catalogued and holds no number', () => {
  for (const key of ['boost.benchmark_on', 'boost.benchmark_label', 'boost.benchmark_pages_per_country', 'batch.boost_benchmark']) expect(code, key).toContain(`('pipeline', '${key}',`)
  expect(code).toContain("and not exists (select 1 from pipeline.evidence_artifacts o where o.evidence_type = 'provider_course_page_text' and o.content_hash = a.content_hash and o.entity_id <> c.id)")
  expect(code).toContain("where c.lifecycle_status = 'active' and c.study_load is null")
  expect(code).toContain("('boost-benchmark', 'Boost', 30, 'Boost model benchmark',")
  expect(code).toContain("select cron.schedule('boost-benchmark', '1-59/2 * * * *',\n  'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''boost_benchmark'', ''limit'', security.pipeline_num_v1(''batch.boost_benchmark'', 8)::int)) where (security.boost_benchmark_gate_v1()->>''ok'')::boolean')")
  expect(code).toContain("return jsonb_build_object('ok', false, 'reason', 'blackout (migration squash)'); end if;")
  expect(code).toContain("if security.maintenance_hold_v1() then return jsonb_build_object('ok', false, 'reason', 'Pipeline Maintenance Mode'); end if;")
  expect(code).toContain("raise exception 'post-check: the benchmark table is not empty'")
})

test('results are closed, cost reaches the ledger, and nothing is dropped', () => {
  expect(code).toContain('alter table pipeline.boost_benchmark_items enable row level security;')
  expect(code).toContain('revoke all on pipeline.boost_benchmark_items from anon, authenticated;')
  expect(code).toMatch(/create trigger ai_spend_capture after insert or update of cost on pipeline\.boost_benchmark_items\s+for each row execute function security\.ai_spend_capture_v1\('boost_benchmark', 'delta', '\{cost\}'\);/)
  expect(code).toContain("raise exception 'post-check: benchmark spend would not land on the service boost_extract_benchmark'")
  for (const sig of ['public.svc_boost_benchmark_gate()', 'public.svc_boost_benchmark_route_v1()', 'public.svc_boost_benchmark_claim(int)', 'public.svc_boost_benchmark_done(jsonb)',
    'security.boost_benchmark_claim_v1(int)', 'security.boost_benchmark_gate_v1(timestamptz)', 'security.boost_benchmark_report_v1(text)']) {
    expect(code, sig).toContain(`revoke all on function ${sig} from public, anon, authenticated;`)
    expect(code, sig).toContain(`comment on function ${sig} is`)
  }
  expect(code).not.toMatch(/grant execute[^;]*(anon|authenticated)/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
})

test('the worker asks each candidate directly, with the extraction request and check, and writes only benchmark rows', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.41"')  // v1.0.38 from s1037  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992  // v1.0.34 from s851  // v1.0.25 from s721  // v1.0.19 from s674
  expect(mode).toContain('const route = await rpc("svc_boost_benchmark_route_v1", {});')
  expect(mode).toContain('const candidates = new Set<string>((Array.isArray(route?.models) ? route.models : []).map((m: any) => String(m?.model_identifier || "")).filter(Boolean));')
  expect(mode).toContain('if (!candidates.has(model)) {')
  expect((mode.match(/await cascadeFetch\(fetch, \{ service: "boost_extract_benchmark" \}, "https:\/\/openrouter\.ai\/api\/v1\/chat\/completions"/g) || []).length).toBe(1)
  expect(mode).toContain('body: JSON.stringify(boostStudyLoadRequest(model, String(pg.title || ""), sec.text, maxTokens))')
  expect(mode).toContain('const v = verifyStudyLoad(ra.a, pageFlat, page);')
  expect(mode).toContain('!String(out.model).startsWith(model) ? `answered by ${out.model}, not the model asked`')
  expect(mode).toContain('await rpc("svc_boost_benchmark_done", { p_items: done });')
  expect(mode).not.toMatch(/staging-boost|svc_boost_inbound|svc_boost_promote|svc_boost_extract_|boost_model_qualifications|catalogue\./)
})
