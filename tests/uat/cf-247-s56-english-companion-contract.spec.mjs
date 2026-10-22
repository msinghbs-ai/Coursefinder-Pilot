// CF-247 (S56) Decision 265: English for the last four universities. Platform Admin 18 Oct 2026 09:27 "Help resolve 'still to do for english'";
// choices: Melbourne "Yes, build and read"; Wollongong and Torrens "Check CRICOS first"; ACU "Yes, UAC for ACU".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261018010000_cf247_english_companion_pages.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('Decision 265: guarded, housekeeping lines, nothing dropped or deleted, new tables commented, job catalogued', () => {
  expect(mig).toContain("<> '11a449a791a5a3ec06cf88527897bbb5' then")
  expect(mig).toMatch(/-- Replaces: /)
  expect(mig).toMatch(/-- Retires: nothing/)
  expect(mig).not.toMatch(/^(delete|drop|truncate)\b/im)
  expect(mig).toContain('comment on table pipeline.uni_adapter_companions is')
  expect(mig).toContain('comment on table pipeline.course_companion_pages is')
  expect(mig.indexOf("('companion-read', 'Enrichment'")).toBeLessThan(mig.indexOf("cron.schedule('companion-read'"))
  expect(mig).toContain("security.pipeline_num_v1('batch.companion_read', 40)")
  expect(mig).toContain("security.pipeline_num_v1('companion.reread_days', 60)")
})

test('levels come from the course page, then its companion page, then course group rules; the Melbourne policy is only proposed', () => {
  expect(mig).toContain("when cp.status = 'read' then nullif(cp.values->>'english_level', '') end raw")
  expect(mig).toContain("from jsonb_array_elements(coalesce(x.proposal->'level_rules', '[]'::jsonb)) with ordinality t(q, n)")
  expect(mig).toContain("'level_map', $j$")
  expect(mig).toMatch(/\$j\$::jsonb, 'proposed'\n/)
})

test('relinking is logged with the old page and respects locks and blocks; leftovers are flagged soft, not archived', () => {
  expect(mig).toContain("values ('coverage', 'rebind', 'course: ' || p_course_id, jsonb_build_object('course_id', p_course_id, 'old_url', v_old")
  expect(mig).toContain("l.field in ('official_url', 'course_url')) then return 'locked'")
  expect(mig).toContain("'not_on_provider_site'")
  expect(mig).toContain("'decision-265', 'soft', 'raised', 'auto'")
  expect(mig).not.toMatch(/lifecycle_status\s*=\s*'(archived|inactive)'/)
})

test('worker v0.29.0 reads companion pages and writes nothing to courses', () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(29|[3-9]\d)\.\d+";/)
  expect(worker).toContain('if (mode === "companion_read") {')
  expect(worker).toContain('await rpc("svc_companion_record", { p_course_id: it.course_id, p_status: st')
})

const fix = fs.readFileSync('supabase/migrations/20261018020000_cf247_english_level_band_wording.sql', 'utf8')
test('Decision 265 follow-up: "band 7.0" is band 7, "band 7+" is read; guarded; nothing dropped', () => {
  expect(fix).toContain("<> 'ed73353d0ca703f59f1cd74f46f830ee' then")
  expect(fix).toContain("'(\\d)\\.0(?![0-9])', '\\1', 'g')")
  expect(fix).toContain("'{levels,band 7+}'")
  expect(fix).not.toMatch(/^(delete|drop|truncate)\b/im)
})

const spend = fs.readFileSync('supabase/migrations/20261018030000_cf247_manual_source_read_and_melbourne_flags.sql', 'utf8')
test('a person-added source is not held by the central refresh interval; the budget still applies; Melbourne pages not found flagged soft', () => {
  expect(spend).toContain("<> 'd43113b1a6ec99ea3e44c61a562d9cb0' then")
  expect(spend).toContain("and fs.found_via = 'manual' and fs.status in ('found', 'reading')) then")
  expect(spend).toContain("if security.fc_budget_left_v1(p_purpose) < p_units then")
  expect(spend).toContain("and g.candidates->>'page_title' like 'Page not found%'")
  expect(spend).not.toMatch(/^(delete|drop|truncate)\b/im)
})

const acu = fs.readFileSync('supabase/migrations/20261018040000_cf247_acu_english_by_course_group.sql', 'utf8')
test('ACU by course group from the stored UAC page: proposed only, ten ordered rules, nothing dropped', () => {
  expect(acu).toContain("$j$::jsonb, 'proposed'")
  expect(acu).toContain("<> 'cd638f2de25dabb3872692d5b69f9532' then")
  expect(acu).toContain("and e.overall_score is not distinct from (q->>'overall_score')::numeric")
  expect(acu).toContain('"level_rules"')
  expect(acu).toContain("jsonb_array_length(proposal->'level_rules') = 10")
  expect(acu).not.toMatch(/^(delete|drop|truncate)\b/im)
})
