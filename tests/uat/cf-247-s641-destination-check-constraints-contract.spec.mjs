// Guards: 28-destination schema lock (Platform Admin 18 Nov 2026 12:21; applied by direction of 14:23): the relaxed CHECK constraints accept every value the old ones did plus the 28-destination values, each is replaced only if its live definition is the one read on 18 Nov, and the ranking.systems change carries the Platform Admin's consumer API approval with no column changed.
// CF-247 S641. supabase/migrations/20261118165000_cf247_28_destination_check_constraints.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118165000_cf247_28_destination_check_constraints.sql', 'utf8')

test('each constraint is replaced only if its live definition is the one read on 18 Nov, and keeps every old value', () => {
  expect(M).toContain("raise exception 'career_outcomes_occupation_scheme_check is not the definition read on 18 Nov: %', v;")
  expect(M).toContain("array['ANZSCO','OSCA','NOL','NOC','SOC','ISCO','ESCO','KLDB','ROME','SSYK','DISCO','SSOC','MASCO','KSCO','JSCO','TSCO']")
  expect(M).toContain("'health_insurance','language_requirement','admission_test','dependants','minimum_wage','offer_document'")
  expect(M).toContain("array['AACSB','EQUIS','AMBA','TEF','NZQA_EER','TRUSTED','KHDA','SETARA','IEQAS','FINEEC','ANVUR']")
  expect(M).toContain("check (code = any (array[''qs_wur'',''the_wur'',''arwu'',''ft'']))")
})

test('the consumer API change is approved and no column of a frozen relation changes; nothing else is dropped', () => {
  expect(M).toMatch(/^-- Consumer API change approved: Platform Admin, 18 Nov 2026 12:21 AEDT/m)
  expect(M).toContain("raise exception 'G3: the consumer API surface changed';")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/^begin;|^commit;/m)
})
