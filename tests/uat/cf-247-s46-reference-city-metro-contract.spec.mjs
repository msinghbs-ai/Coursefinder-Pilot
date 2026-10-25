// Guards: CF-247 (S46): found while refreshing the website developer pack (15 Oct 2026): the reference reply listed Sydney under Brisbane.
// CF-247 (S46): found while refreshing the website developer pack (15 Oct 2026): the reference reply listed Sydney under Brisbane. A city's
// metro area is now the one most of its campuses have, and a campus whose register state disagrees with its postcode takes the postcode's
// state when its address names it.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const mig = fs.readFileSync('supabase/migrations/20261015090000_cf247_reference_city_metro.sql', 'utf8')
test('most common metro area per city; the address decides a state the register got wrong; post-check on Sydney', () => {
  expect(mig).toContain('mode() within group (order by rc.metro_area) metro')
  expect(mig).not.toContain('min(rc.metro_area) metro')
  expect(mig).toContain("concat_ws(' ', k.name, k.address_line1, k.address_line2) ~* ('\\m' || security.au_state_from_postcode_v1(k.postcode) || '\\M')")
  expect(mig).toContain("raise exception 'reference post-check: Sydney still listed under another metro area';")
  expect(mig).toMatch(/^-- Replaces: /m)
})
