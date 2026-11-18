// Guards: open-licence destination editions publish without manual clicks (Platform Admin 18 Nov 2026 13:07): an edition whose owner is on destination.open_licence_owners and whose terms are approved has its attributed draft rows approved and is published hourly with an audit entry; QILT is not on the list; publishing never supersedes another owner's edition; the BOM climate statistics terms are recorded (CC BY 4.0) with full attribution.
// CF-247 S637. supabase/migrations-archive/20261118161000_cf247_destination_open_licence_publish.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118161000_cf247_destination_open_licence_publish.sql', 'utf8')

test('only open-licence owners with approved terms are approved and published, each with an audit entry; QILT stays gated', () => {
  expect(M).toContain("where x.status in ('draft', 'in_review') and x.terms_status = 'approved' and x.source_owner = any (v_owners)")
  expect(M).toContain("'[\"Bureau of Meteorology\", \"Australian Bureau of Statistics\", \"Study Australia\", \"Study Tasmania\", \"Department of Home Affairs\", \"Fair Work Ombudsman\", \"Jobs and Skills Australia\"]'::jsonb")
  expect(M).not.toMatch(/"QILT"|'QILT'/)
  expect(M).toContain("values ('destination', 'open_licence_publish', e.edition_label")
  expect(M).toContain("values ('destination-open-licence-publish', null, 'select security.destination_open_licence_publish_v1()'")
})

test('publishing replaces only an edition of the same source owner, and the ABS edition stays published', () => {
  expect(M).toContain("x.id <> v.id and x.source_owner is not distinct from v.source_owner")
  expect(M).toContain("raise exception 'the ABS population edition must stay published';")
})

test('the BOM climate statistics terms are recorded under CC BY 4.0 with full attribution, and nothing is deleted', () => {
  expect(M).toContain("v_res := security.destination_edition_set_terms_v1(v_ed, 'approved', v_admin);")
  expect(M).toContain('Source: Bureau of Meteorology, Commonwealth of Australia.')
  expect(M).toContain('Licensed under Creative Commons Attribution 4.0 (CC BY 4.0)')
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
