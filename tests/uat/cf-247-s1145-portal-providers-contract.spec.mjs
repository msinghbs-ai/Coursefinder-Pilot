// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026 16:44, S1-API-Frontend-Delivery): Universities & Providers shows only what the published-only function returns, paged on the server, with an honest Study Square route (s930: no cut or static lists).; amended by s1222 (Atlas brief 26 Nov 2026 15:59 AEDT, portal UAT fixes: concise cards, drawer, pinned student countries)
// CF-247 S1145. The route comes from pipeline.provider_representation, which holds no rows yet, so every provider reads "Status not recorded" rather than guessing.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { stateShort, initials } from '../../portal/src/lib/format.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const providers = read('portal/src/screens/Providers.jsx')

test('the list is the server page, appended by "Show more", never cut in the browser', () => {
  expect(providers).toContain("usePagedList('portal_providers_v1'")
  expect(providers).not.toMatch(/\.slice\(\s*0\s*,\s*\d+/)
  expect(providers).not.toMatch(/\bpage_?size\s*[:=]\s*\d+/i)
  expect(providers).toMatch(/<ShowMore/)
  const portal = read('portal/src/lib/portal.jsx')
  expect(portal).toMatch(/rpc\(name, \{ p_args: \{ \.\.\.args, page \} \}\)/)
  expect(portal).toMatch(/\[\.\.\.old\.items, \.\.\.r\.items\]/)
})

test('filters come from the facets the server returns, not from a list in the code', () => {
  expect(providers).toMatch(/f\.types \|\| \[\]/)
  expect(providers).toMatch(/f\.states \|\| \[\]/)
  expect(providers).toMatch(/f\.routes \|\| \[\]/)
  // s1222: the market list is the live lookup, with portal.priority_source_countries pinned first (MarketOptions).
  expect(providers).toMatch(/<MarketOptions markets=\{markets\} priority=\{priority\} \/>/)
  expect(providers).not.toMatch(/['"`](Victoria|New South Wales|Queensland|University|TAFE)['"`]/)
})

test('the four route states have plain words, and no route is promised when none is recorded', () => {
  for (const w of ['Represented', 'Direct', 'Not represented', 'Status not recorded']) expect(providers).toContain(w)
  expect(providers).toMatch(/Ask the Study Square team before promising a route/)
  expect(providers).toMatch(/Website not recorded/)
  // s1215: the website link goes through the one new-tab component (target _blank, rel noopener noreferrer), guarded in the s1215 contract.
  expect(providers).toMatch(/<ExtLink[^>]*href=\{p\.website\}/)
})

test('state codes and initials read naturally', () => {
  expect(stateShort('AU-QLD')).toBe('QLD')
  expect(stateShort('CA-ON')).toBe('ON')
  expect(stateShort(null)).toBe('')
  expect(initials('Monash University')).toBe('MU')
  expect(initials('University of Technology Sydney (UTS)')).toBe('UT')
  expect(initials('')).toBe('?')
})
