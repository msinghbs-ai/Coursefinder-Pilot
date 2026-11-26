// Guards: Atlas brief 26 Nov 2026 18:18 AEDT (S2-AER gap audit, admin #1186), s1271: a portal course with no primary campus whose active campuses are all in one city and state shows that city on the search cards, Entry Requirements rows and saved courses; a course with campuses in several cities gets no city (no tie-break, no guess); a search that names a city still shows the matching campus first
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261129170000_cf247_s1271_portal_sole_city.sql'
const m = fs.readFileSync(MIG, 'utf8')
const fn = name => { const i = m.indexOf(`create or replace function ${name}(`); return m.slice(i, m.indexOf('$function$;', i)) }

test('migration: additive, guarded, replaces only the s1222 bodies, nothing dropped', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m)
  expect(m).not.toMatch(/\bdrop\s+(table|function|view|index|schema)\b/i); expect(m).not.toMatch(/\bdelete\s+from\b/i)
  for (const h of ['7cac99bac0e19a06f34f2357dda727fb', '60b50705e19a4e16a8ee435ebfdeecbf', '3fd363d0003f148b8040ddd6bf6dd112']) expect(m).toContain(h)
  expect(m).toContain('security.consumer_api_check_v1()')
  expect(m).toContain("'post-check: the number of active cron jobs changed'")
  expect(m).toContain("'post-check: manual locks changed'")
  expect(m).toMatch(/revoke all on function portal\.course_place_v1\(uuid\) from public, anon, authenticated/)
})

test('one place per course: primary campus, else the one city and state every campus shares, else none', () => {
  const p = fn('portal.course_place_v1')
  expect(p).toContain("coalesce(ca.status, 'active') = 'active'")
  expect(p).toContain('coalesce(cc.is_primary, false) prim')
  expect(p).not.toContain('ca.is_primary')  // the provider's main campus is not the course's campus
  expect(p).toContain("count(distinct (lower(city), coalesce(state_code, ''))) filter (where city is not null) n_place")
  expect(p).toMatch(/al\.n_city = al\.n and al\.n_place = 1/)  // every campus has a city, and all are one place
  for (const b of ['primary_campus', 'sole_city', 'one_state', 'several_cities', 'provider']) expect(p).toContain(`'${b}'`)
  expect(p).not.toMatch(/order by[^\n]*limit 1/)  // no tie-break between cities
})

test('cards, Entry Requirements rows and saved courses read the one place', () => {
  const cards = fn('catalogue.portal_course_cards_v1'), aer = fn('portal.aer_list_v1'), saved = fn('public.portal_saved_list_v1')
  for (const [n, f] of [['cards', cards], ['aer', aer], ['saved', saved]]) {
    expect(f, n).toContain('left join lateral portal.course_place_v1(c.id) pl on true')
    expect(f, n).toMatch(/'place_basis', /)
    expect(f, n).toMatch(/when pl\.basis = 'provider' then p\.primary_city else pl\.city end/)
  }
  // a searched city or postcode still picks the matching campus
  expect(cards).toContain("and (lower(trim(ca.city)) = any(p_cities) or ca.postcode = any(")
  expect(cards).not.toMatch(/cc\.is_primary desc nulls last, ca\.city limit 1\) cam/)
  expect(aer).not.toContain('coalesce(cam.city, p.primary_city)')
})

test('post-check proves a sole-city card names its city and a multi-city card does not', () => {
  expect(m).toContain("'post-check: a sole-city card does not name its city: % / %'")
  expect(m).toContain("'post-check: a multi-city course was given a city: %'")
})
