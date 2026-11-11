// Guards: CF-247 F-INT (11 Nov 2026): the intake apply never waits for the search-document writer lock; when it is busy the courses go to search.refresh_requests, so a busy search refresh can no longer time out and roll back admitted intake dates.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261111150000_cf247_intake_apply_never_waits_for_search.sql', 'utf8')

test('one md5-guarded edit: try the writer lock, else queue the refresh', () => {
  expect(MIG).toContain("select pg_temp.edit_all('security.intake_dates_apply_v1(integer,uuid[])', '0cb3cd422f99ac0d520deef99ea0ee36', '8eb3fa7f92cc6953faf0234715dfee2e',")
  const n = MIG.slice(MIG.indexOf('array[$n$'), MIG.indexOf('$n$]);'))
  expect(n).toContain("if pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then")
  expect(n).toContain('perform search.refresh_course_enrichment_scoped_v1(')
  expect(n).toContain('insert into search.refresh_requests(requested_by)')
  expect(n).not.toContain('pg_advisory_xact_lock(hashtext')   // never the blocking form
  expect(MIG).toContain("<> '8eb3fa7f92cc6953faf0234715dfee2e' then")
})
