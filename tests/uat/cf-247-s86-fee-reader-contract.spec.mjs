import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 v2.15.309 (Platform Admin 21 Oct 2026 20:02): AI fee reader for NZ universities, ready for Canada and later countries; errors
// collected and fed back to the AI. Choices: "Automatic above confidence", "As published + yearly estimate", "NZ universities, then NZ
// rest, then CA".
const m = fs.readFileSync('supabase/migrations/20261022001000_cf247_fee_reader.sql', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const f = fs.readFileSync('supabase/functions/coverage-sweep/fees.ts', 'utf8')
const ui = fs.readFileSync('src/FeeReader.jsx', 'utf8')

test('country rules are data; rollout scope and thresholds are settings', () => {
  expect(m).toContain('create table if not exists pipeline.fee_country_profiles')
  for (const c of ["('NZ', 'NZD', 'per_year', 120", "('CA', 'CAD', 'per_credit', 30", "('AU', 'AUD', 'per_year', 8"]) expect(m).toContain(c)
  for (const k of ['fees.auto_admit_confidence', 'fees.min_title_similarity', 'fees.outlier_ratio', 'fees.min_suggest_score', 'fees.max_pages_per_provider', 'fees.pages_per_run', 'fees.page_chars', 'fees.findings_in_prompt'])
    expect(m).toContain(`security.pipeline_num_v1('${k}'`)
  expect(m).toContain("('pipeline', 'fees.countries'")
  expect(m).toContain("'[\"university\"]'::jsonb")
  expect(m).toContain("('openrouter', 'guard_fee_ai'")
})

test('errors are kept and fed back; notes evolve; admission above confidence, otherwise Layer 4', () => {
  expect(m).toContain('create table if not exists pipeline.fee_reader_findings')
  expect(m).toContain('create table if not exists pipeline.fee_reader_recipes')
  expect(m).toContain("'findings', coalesce((select jsonb_agg(")
  expect(m).toContain("when c.conf >= v_min_conf and coalesce(c.sim, 0) >= v_min_sim")
  expect(m).toContain("perform security.coverage_apply_course_v1(c.course_id, v_src, f.evidence_id, f.url, f.content_hash,")
  expect(m).toContain("insert into pipeline.layer4_review_items(entity_type, entity_id, field_code")
  expect(m).toContain("select cron.schedule('fee-reader', '7-59/10 * * * *', $$select security.fee_reader_tick_v1()$$);")
  expect(m).toContain("('fee-reader', 'Course pages'")
  expect(m).toMatch(/^-- Replaces: /m)
  expect(m).toMatch(/^-- Retires: /m)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('worker: pinned model, quotes and amounts must be on the page, past problems in the prompt', () => {
  expect(w).toContain('coverage-sweep-worker-v0.35.0')
  expect(w).toContain('if (mode === "fee_ai") {')
  expect(w).toContain('if (d?.model && !String(d.model).startsWith(it.model))')
  expect(f).toContain('Problems with earlier reads of this provider (avoid them)')
  expect(f).toContain('!on.includes(q)')
  expect(f).toContain('strict: true')
})

test('screen: providers, rows, findings, notes, country rules', () => {
  expect(ui).toContain("supabase.rpc('admin_fee_reader'")
  for (const s of ['data-fee-reader', 'data-fee-rows', 'data-fee-findings', 'data-fee-profiles']) expect(ui).toContain(s)
  expect(ui).not.toMatch(/US\$\s?\d/)
})

test('a fee page never read is not held by the central-page refresh rule', () => {
  const h = fs.readFileSync('supabase/migrations/20261022002000_cf247_fee_pages_first_read.sql', 'utf8')
  expect(h).toContain("and fs.status in ('found', 'reading') and fs.read_at is null) then")
  expect(h).toMatch(/^-- Replaces: /m)
  expect(h).toMatch(/^-- Retires: /m)
})

// 21 Oct 2026 21:36 job queue review ("Keep 13,000, fix order only")
test('course-page search: priority countries first, wrong-in-a-row stop, providers never searched', () => {
  const s = fs.readFileSync('supabase/migrations/20261022003000_cf247_search_order_and_waste.sql', 'utf8')
  expect(s).toContain("sp.key = 'search.priority_countries')) desc,")
  expect(s).toContain("security.pipeline_num_v1('search.wrong_in_row_stop', 20)")
  expect(s).toContain("sk.key = 'search.skip_providers' and sk.value ? px.stable_key")
  expect(s).toMatch(/^-- Replaces: /m)
  expect(s).toMatch(/^-- Retires: /m)
})
