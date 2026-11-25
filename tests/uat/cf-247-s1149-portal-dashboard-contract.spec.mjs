// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026 16:44, S1-API-Frontend-Delivery): the Dashboard keeps as many recent searches as the setting portal.recent_searches_shown says (G2), and a Viewer is told plainly what the Counsellor role adds.
// CF-247 S1149. The recent-search count used to be a constant in the code; it is now a setting read with the other portal settings.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = (p) => fs.readFileSync(p, 'utf8')
const dash = read('portal/src/screens/Dashboard.jsx')

test('the number of recent searches is the setting, not a constant', () => {
  expect(dash).toMatch(/Number\(settings\.recent_searches_shown\)/)
  expect(dash).toMatch(/slice\(0, keep\)/)
  expect(read('portal/src/copy.js')).not.toMatch(/RECENT_SEARCHES_SHOWN/)
  expect(dash).not.toMatch(/RECENT_SEARCHES_SHOWN/)
  expect(dash).not.toMatch(/slice\(0, \d+\)\)?\s*$/m)
})

test('a search from the Dashboard lands on Courses with the words kept', () => {
  expect(dash).toMatch(/location\.hash = `#\/courses\?q=\$\{encodeURIComponent\(q\)\}`/)
})

test('the saved panel is Counsellor only and a Viewer is told what to ask for', () => {
  expect(dash).toMatch(/counsellor\s*\n?\s*\? <SavedPanel \/>/)
  expect(dash).toMatch(/Your role is Viewer/)
  expect(dash).toMatch(/Counsellor role/)
})

test('the example searches are typing illustrations, with no fee, intake or provider the platform holds', () => {
  const copy = read('portal/src/copy.js')
  expect(copy).toMatch(/EXAMPLE_PROMPTS/)
  expect(copy).not.toMatch(/\bA\$\s?\d|\bAUD\b|\d{4}\s+intake/)
})
