// Guards: Platform Admin 23 Nov 2026 18:22 AEDT, Step 2 (AER v2 over stored reads; Decision 276 AER v1 freeze; G3 75/48; 0.8 confidence and 5% audit untouched): an entry-matrix read whose heading and address name no level takes the bachelor level only when its own table states the ATAR as its benchmark (aer.matrix_atar_table_share)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261123200000_cf247_s995_aer_matrix_atar_level.sql', 'utf8')

test('s995: the edit is md5-guarded, found once, and the consumer API, locks, jobs and confidence/audit settings are asserted unchanged', () => {
  expect(sql).toContain('51ad50c58c2f0db1712310a761e8d99b')
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).toContain("post-check: a confidence or audit setting changed")
  expect(sql).toContain("post-check: manual locks changed")
  expect(sql).not.toMatch(/update pipeline\.platform_toolset_settings|create table (?!if not exists)|cron\.schedule|create or replace function public\./i)
})

test('s995: the ATAR level applies only when no level word is printed, the table is mostly ATAR band rows, and no row prints another level', () => {
  expect(sql).toContain("m0.matrix_kind = 'band_ladder' and m0.quote ~* '\\mATAR\\M'")
  expect(sql).toContain("security.pipeline_num_v1('aer.matrix_atar_table_share', 0.5)")
  expect(sql).toContain("when cfg.inh_on and (select count(*) from words) = 0 and cfg.inh_codes ? 'bachelor' and atar.yes")
  expect(sql).toContain("'rule', lvl.rule,")
  expect(sql).toContain("'S995 ATAR is the table''s benchmark (undergraduate entry rank)'")
})
