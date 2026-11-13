// Guards: F-SCH long-page recovery (Platform Admin S2-Scholarship directive 13 Nov 2026 §2; Operating Model v1.19 S2-Scholarship 2): one bounded, sectioned reading of the stored official page per failed scholarship, the award's own section only, several fields per call, merged into the one checked version 3 answer; never a repeated whole-page retry
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { awardSection, scholarshipExtractPartRequest, mergeRecoveryParts, DETAIL_PART_A, DETAIL_PART_B, DETAIL_SCHEMA, RECOVERY_VARIANT } from '../../supabase/functions/coverage-sweep/sch-extract.ts'

const m = fs.readFileSync('supabase/migrations/20261113294100_cf247_sch_detail_long_page_recovery.sql', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('the award section: an umbrella page gives only the named award\'s part; a name not on the page is recorded as not found', () => {
  const other = 'Global Excellence Scholarship. Open to all international students. Value $10,000. '.repeat(40)
  const page = other + ' Vice-Chancellor\'s International Scholarship (VCIS) This scholarship offers 50% off tuition for international students. ' + 'Other award text. '.repeat(500)
  const s = awardSection(page, "Vice-Chancellor's International Scholarship (VCIS)", 1200)
  expect(s.found).toBe(true)
  expect(s.text).toContain('50% off tuition')
  expect(s.text.length).toBeLessThanOrEqual(1200)
  expect(s.start).toBeGreaterThan(other.length - 400)
  const n = awardSection(page, 'Nonexistent Award Name', 1200)
  expect(n.found).toBe(false); expect(n.start).toBe(0); expect(n.text.length).toBe(1200)
})

test('two parts cover every detail field exactly once, keep the strict shapes, and merge into one answer', () => {
  expect([...DETAIL_PART_A, ...DETAIL_PART_B].sort()).toEqual([...DETAIL_SCHEMA.required].sort())
  const p = { provider: 'X', country: 'AU', currency: 'AUD', scholarship: 'A', parts: [{ id: 'page', url: 'https://x.edu/a', text: 'text' }] }
  const a = scholarshipExtractPartRequest('m', 'prompt', p, 'a', 4500), b = scholarshipExtractPartRequest('m', 'prompt', p, 'b', 4500)
  expect(a.response_format.json_schema.strict).toBe(true)
  expect(a.response_format.json_schema.schema.required).toContain('is_scholarship')
  expect(a.response_format.json_schema.schema.properties.detail.required).toEqual([...DETAIL_PART_A])
  expect(b.response_format.json_schema.schema.required).toEqual(['detail'])
  expect(b.response_format.json_schema.schema.properties.detail.required).toEqual([...DETAIL_PART_B])
  expect(a.provider.require_parameters).toBe(true)
  expect(mergeRecoveryParts({ is_scholarship: true, detail: { sponsor: 'S' } }, { detail: { summary: 'x' } })).toEqual({ is_scholarship: true, detail: { sponsor: 'S', summary: 'x' } })
})

test('worker: only marked recovery items take the sectioned path; costs of both calls kept; same checks and record', () => {
  expect(RECOVERY_VARIANT).toBe('sectioned-v1')
  expect(w).toContain('const recovery = it.recovery === RECOVERY_VARIANT && Number(it.prompt_version || 0) >= 3;')
  expect(w).toContain('wsNum("reading.sch_recovery_section_chars", 6000)')
  expect(w).toContain('c1 = pa.cost + pb.cost; cost += c1;')
  expect(w).toContain('if (!x.ans.ok) throw readError(`recovery ${nm}: ${x.ans.error}`, c1);')
  expect(w).toContain('checks.detail = checkScholarshipDetail(a.detail, parts, NAT_NAMES);')
})

test('database: one recovery item per failed scholarship, at most once, from the backfill; the worker is told the variant and name', () => {
  expect(m).toContain("alter table pipeline.scholarship_ai_queue add column if not exists recovery text;")
  expect(m).toContain("(x.error like 'held_partial: output_truncated%' or x.error like 'no_answer%' or x.error like 'unreadable_answer%')")
  expect(m).toContain("(q.state in ('queued', 'leased') or q.recovery is not null)")
  expect(m).toContain('n := n + security.scholarship_detail_recovery_queue_v1(greatest(p_limit - n, 0));')
  expect(m).toContain("'recovery', u.recovery,")
  expect(m).toContain("'f830adfdff8846de51f8e695bdb8d525'")
  expect(m).toContain("'709ad0f93b16e99f8962e85671f0b291'")
})
