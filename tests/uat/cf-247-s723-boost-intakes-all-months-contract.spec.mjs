// Guards: Intakes priority rule (Platform Admin 19 Nov 2026 05:40, s723, REQ-69): the reader captures every start month the official course page announces, and the replay counts a registered primary annual intake that those months contain (or that contains them) as agreement, never as a contradiction; months that share no containment disagree
// CF-247 S723. Worker coverage-sweep (boost-fields.ts prompt boost-fields-v2) and scripts/boost-fields-replay.mjs. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

let F, B
test.beforeAll(async () => {
  const load = async (f) => { const out = await build({ entryPoints: [f], bundle: true, format: 'esm', write: false, logLevel: 'silent' }); return import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64')) }
  F = await load('supabase/functions/coverage-sweep/boost-fields.ts'); B = await load('supabase/functions/coverage-sweep/boost.ts')
})

test('the prompt asks for every announced start month, not only the next one', () => {
  expect(F.BOOST_FIELDS_PROMPT_VERSION).toBe('boost-fields-v2')
  expect(F.BOOST_FIELDS_SYSTEM).toContain('Every month the page announces as a start or intake month for this course, all of them, not only the next one.')
  expect(F.BOOST_FIELDS_SYSTEM).toContain('"March", "July", "November"')
  const page = 'Intakes: March, July and November each year.'
  expect(F.verifyBoostField('intakes', { months: ['March', 'July', 'November'], quote: 'Intakes: March, July and November' }, B.boostFlat(page), page).status).toBe('verified')
})

test('replay scoring: a held primary intake contained in the page\'s months agrees; no containment disagrees', () => {
  const S = fs.readFileSync('scripts/boost-fields-replay.mjs', 'utf8')
  expect(S).toContain('const sub = got.length > 0 && got.every((m) => held.includes(m)), sup = got.length > 0 && held.every((m) => got.includes(m))')
  expect(S).toContain('agree = sub || sup')
  expect(S).toContain("if (sub && sup) bump(lane, 'gold_exact'); else if (sup) bump(lane, 'gold_primary_subset'); else if (sub) bump(lane, 'gold_page_subset')")
  // the same arithmetic on the cases the directive names
  const score = (got, held) => { const sub = got.length > 0 && got.every((m) => held.includes(m)), sup = got.length > 0 && held.every((m) => got.includes(m)); return sub || sup }
  expect(score([3, 7, 11], [3])).toBe(true)   // page March, July, November; held primary March
  expect(score([7], [3, 7])).toBe(true)       // page names one of the held months
  expect(score([2, 7], [3])).toBe(false)      // no containment: a real difference
})
