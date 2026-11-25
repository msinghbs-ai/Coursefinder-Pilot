// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026 16:44, S1-API-Frontend-Delivery): the shortlist and the side-by-side compare use the database limits (G2: saved_courses_max, compare_courses_max), show honest labels, and only a Counsellor can save.
// CF-247 S1147. Durations are held in weeks, months, semesters or years; the total is the yearly fee over the length and is marked "about".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { durationText, durationInYears } from '../../portal/src/lib/format.js'

const read = (p) => fs.readFileSync(p, 'utf8')

test('durations read in plain years or weeks', () => {
  expect(durationText(78, 'weeks')).toBe('1.5 years')
  expect(durationText(104, 'weeks')).toBe('2 years')
  expect(durationText(26, 'weeks')).toBe('26 weeks')
  expect(durationText(2, 'years')).toBe('2 years')
  expect(durationText(1, 'years')).toBe('1 year')
  expect(durationText(9, 'months')).toBe('9 months')
  expect(durationText(18, 'months')).toBe('1.5 years')
  expect(durationText(24, 'months')).toBe('2 years')
  expect(durationText(4, 'semesters')).toBe('4 semesters')
  expect(durationText(null, null)).toBe('Not recorded')
  expect(durationText(10, 'fortnights')).toBe('Not recorded')
  expect(durationInYears(78, 'weeks')).toBeCloseTo(1.5)
  expect(durationInYears(4, 'semesters')).toBe(2)
  expect(durationInYears(0, 'weeks')).toBeNull()
})

test('the limits are the database settings, not numbers in the screens', () => {
  const saved = read('portal/src/screens/Saved.jsx')
  const hook = read('portal/src/lib/saved.js')
  expect(hook).toMatch(/savedMax: r\.saved_max/)
  expect(hook).toMatch(/compareMax: r\.compare_max/)
  expect(saved).toMatch(/const max = saved\.compareMax/)
  expect(saved).not.toMatch(/picked\.length >= \d/)
  expect(saved).not.toMatch(/up to \d+ (saved )?courses/i)
})

test('the compare table never guesses', () => {
  const saved = read('portal/src/screens/Saved.jsx')
  expect(saved).toMatch(/Not recorded/)
  expect(saved).toMatch(/about \$\{total\}/)
  expect(saved).toMatch(/No longer offered/)
  expect(saved).toMatch(/Duration not recorded/)
})

test('saving is Counsellor only on every screen that offers it', () => {
  const courses = read('portal/src/screens/Courses.jsx')
  expect(courses).toMatch(/const canSave = access\.kind === 'counsellor'/)
  expect(courses).toMatch(/useSaved\(canSave\)/)
  expect(read('portal/src/lib/saved.js')).toMatch(/if \(enabled\) refresh\(\)/)
  expect(read('portal/src/screens/Shell.jsx')).toMatch(/access\.kind === 'counsellor'\s*\?\s*<Saved/)
})
