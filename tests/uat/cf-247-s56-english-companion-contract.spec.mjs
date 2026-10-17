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
  expect(worker).toContain('const WORKER = "coverage-sweep-worker-v0.29.0";')
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
