// Guards: Atlas brief 26 Nov 2026 19:51 AEDT (Platform Admin live UAT of the StudySearch Portal), s1275: a course closed to international students (open_to_international = false) is not returned by Portal course search or Entry Requirements; a course with no answer (null) stays and carries open_to_international so the Portal says "Check international availability"; a course with campuses in several cities and no primary campus shows the one city of it inside the state the search names, or "Multiple campuses (VIC)" / "Multiple campuses", and never a guessed campus
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261129230000_cf247_s1275_portal_intl_availability_campus_label.sql'
const m = fs.readFileSync(MIG, 'utf8')
const fn = name => { const i = m.indexOf(`create or replace function ${name}(`); return m.slice(i, m.indexOf('$function$;', i)) }
const src = p => fs.readFileSync(p, 'utf8')

test('migration: additive, guarded on the live bodies, nothing dropped, consumer API and locks untouched', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m)
  expect(m).not.toMatch(/\bdrop\s+(table|function|view|index|schema)\b/i); expect(m).not.toMatch(/\bdelete\s+from\b/i)
  for (const h of ['f91226e37714679a6799ad9451f3eb02', 'cbd8d27478cd43f72526f141a65b8070', '88bae8930ac30704c961714f92e1f15d', 'cd125b53b6a7738ac4c3e1787e52f38c']) expect(m).toContain(h)
  expect(m).toContain('security.consumer_api_check_v1()')
  expect(m).toContain("'post-check: the number of active cron jobs changed'")
  expect(m).toContain("'post-check: manual locks changed'")
  expect(m).toMatch(/revoke all on function portal\.place_label_v1\(text, text\) from public, anon, authenticated/)
  expect(m).not.toMatch(/insert into pipeline\.platform_toolset_settings/)  // G2: no setting, no value in code
})

test('search and Entry Requirements leave out domestic-only courses in the one passing step; unknown (null) stays', () => {
  expect(m).toContain("and c.open_to_international is not false")
  // the anchored edits are counted: one passing-set join in the search, two card calls that pass the state, three in Entry Requirements
  expect(m).toMatch(/c\.publication_status = 'published'\)\$a\$,\s*\n\s*\$b\$[^$]*and c\.open_to_international is not false/)
  expect(m).toContain("'states', to_jsonb(v_states))$b$, 2)")
  expect(m).toContain("'open_to_international', c.open_to_international, 'level_code'")
  // a saved course is never taken off a person's list: the saved-course edit adds only the place wording
  const saved = m.slice(m.indexOf("v_fn := 'public.portal_saved_list_v1()'"), m.indexOf('end $f$;'))
  expect(saved).toContain('portal.place_label_v1')
  expect(saved).not.toContain('open_to_international')
  expect(m).not.toMatch(/open_to_international is true/)  // null is kept and flagged, not hidden
})

test('cards: the international answer, the state-aware place, no guessed campus', () => {
  const cards = fn('catalogue.portal_course_cards_v1')
  expect(cards).toContain("'open_to_international', c.open_to_international")
  for (const b of ['searched_campus', 'state_campus', 'multiple_campuses_state', 'multiple_campuses']) expect(cards).toContain(`'${b}'`)
  expect(cards).toContain("'Multiple campuses (' || fs.shorts || ')'")
  expect(cards).toContain('portal.place_label_v1(pl.basis, pl.state_code)')
  expect(cards).toContain("jsonb_typeof(p_near->'states') = 'array'")  // the search's state arrives beside its postcodes
  expect(cards).toContain('s.code = any(v_states)')
  expect(cards).toMatch(/pl\.basis in \('several_cities', 'one_state'\) and fs\.n_place = 1/)  // one city in the state: that city
  const fs_ = cards.slice(cards.indexOf('left join lateral (select count(distinct'), cards.indexOf('left join pg_temp.portal_search_rank'))
  expect(fs_).not.toMatch(/\blimit\b/)  // never a tie-break between campus cities
  expect(fs_).not.toContain('is_primary')  // never a primary campus guessed
  // a typed city or postcode still picks its campus first (s1271)
  expect(cards).toContain("and (lower(trim(ca.city)) = any(p_cities) or ca.postcode = any(")
})

test('one wording for a multi-campus course', () => {
  const p = fn('portal.place_label_v1')
  expect(p).toContain("when 'several_cities' then 'Multiple campuses'")
  expect(p).toContain("'Multiple campuses (' ||")
  expect(m).toContain("'post-check: the place wording is wrong'")
})

test('post-check proves the exclusion, the state-aware labels and the unchanged sole-city card', () => {
  for (const s of ["'post-check: % domestic-only course(s) were returned by the search'", "'post-check: % domestic-only course(s) were returned by Entry Requirements'",
    "'post-check: the search total % is not the % courses open or not known to international students'",
    "'post-check: a state search did not name the course''s one campus city in it: %'", "'post-check: several campus cities in the state were not labelled: %'",
    "'post-check: a multi-campus course without a state in the search was not labelled: %'", "'post-check: a sole-city card changed: %'"]) expect(m).toContain(s)
})

test('Portal screens: the badge, and the place from one helper', () => {
  const ui = src('portal/src/components/ui.jsx'), fmt = src('portal/src/lib/format.js')
  expect(ui).toContain('Check international availability')
  expect(ui).toMatch(/c\.open_to_international === null/)  // only when the function sent the field and it is null
  expect(fmt).toMatch(/c\?\.place_label \|\|/)
  for (const p of ['portal/src/screens/Courses.jsx', 'portal/src/screens/EntryRequirements.jsx']) {
    const s = src(p)
    expect(s, p).toContain('IntlBadge'); expect(s, p).toMatch(/<IntlBadge c=\{c\} \/>/); expect(s, p).toContain('placeText')
  }
  expect(src('portal/src/screens/Saved.jsx')).toContain('placeText(c)')
  expect(src('portal/src/screens/Courses.jsx')).not.toMatch(/\[stateShort\(c\.state_code\), c\.city\]/)
})
