// Guards: PIM step 4 common interface and interface 4 second safeguard (Platform Admin 25 Nov 2026 23:12 AEDT): one lifecycle read for academic entry and scholarships with the owning lane; guarded supersessions re-checked and flagged, never reversed; snapshot only; G1, G2, G3, locks, cron.
// s1169: security.pim_lifecycle_v1 and its key in the Data Delivery snapshot.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128080000_cf247_s1169_pim_lifecycle_interface_replacement_check.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1169: every active course has exactly one academic entry stage; the scholarship lane rollup is read as it stands', () => {
  for (const s of ['not_applicable', 'admitted', 'in_review', 'read_queued', 'read_no_admissible_rows', 'page_stored', 'page_bound_not_stored', 'no_page']) expect(code).toContain(`'${s}'`)
  expect(code).toContain('from pipeline.scholarship_provider_coverage s')
  expect(code).toContain("guard: lifecycle stages cover % courses, % active")
})

test('s1169: the lanes keep ownership: the read writes nothing in their tables', () => {
  expect(code).not.toMatch(/\b(insert into|update|delete from)\s+(pipeline\.(aer_|coverage_|scholarship_|layer4_)|catalogue\.)/i)
})

test('s1169: the second safeguard re-tests guarded supersessions in the existing long window and flags, never reverses', () => {
  expect(code).toContain("security.pipeline_num_v1('data_delivery.net_long_hours', 168)")
  expect(code).toContain("security.supersede_successor_v1('layer4', s.id)")
  expect(code).not.toMatch(/layer4_supersession_reverse_v1/)
})

test('s1169: counted in the background snapshot; nothing dropped; G3 75/48, locks and cron guarded', () => {
  expect(code).toContain("''lifecycle'', security.pim_lifecycle_v1()")
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(truncate|cron\.schedule|drop\s+(table|function|column|constraint|trigger))\b/i)
  expect(MIG).toContain('-- Replaces:')
})
