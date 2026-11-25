// Guards: StudySearch Portal Release 2 (Platform Admin 26 Nov 2026, S1-API-Frontend-Delivery): the student sheet shows only what the student may see, never invents a missing fee, and prints with browser CSS ($0, no Browser Rendering)
// CF-247 S1201: sheetModel and the @media print rules. Counsellor notes and internal titles never reach the sheet.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const P = () => import('../../portal/src/lib/proposals.js')
const proposal = () => ({
  id: 'p1', version: 4, status: 'ready', title: 'INTERNAL: Aarav tough case', internal_note: 'Parents prefer Adelaide, budget is tight',
  student: { ref: 'SS-000142', given_name: 'Aarav', family_initial: 'S', result_text: '72%', english_text: 'IELTS Academic 6.5', budget_per_year: 25000, budget_currency: 'AUD' },
  courses: [
    { course_id: 'c1', position: 1, why: 'Lowest fee', snapshot: { title: 'Advanced Diploma of Nursing', provider_name: 'EQUALS International', fee: { per_year: 16950, currency: 'AUD' }, duration_value: 1.5, duration_unit: 'years', next_intake: { label: 'Feb 2027', start_date: '2027-02-08' }, entry: { text: 'Year 12 or equivalent' } } },
    { course_id: 'c2', position: 2, why: '', snapshot: { title: 'Associate Degree', provider_name: 'Melbourne Polytechnic', fee: null, next_intake: null, entry: null, scholarship: null } },
  ],
  steps: [{ title: 'Confirm the shortlist', owner: 'counsellor', due_label: '30 Nov 2026', included: true }, { title: 'Hidden step', owner: 'student', included: false }],
  documents: ['Passport'], message_to_student: 'Hello Aarav', details_checked_at: '2026-11-18T01:00:00Z', counsellor: { name: 'Mandeep Singh', title: 'Education Counsellor' },
})

test('the sheet model never reads the counsellor note or the internal title', async () => {
  const { sheetModel } = await P()
  const text = JSON.stringify(sheetModel(proposal(), new Date('2026-11-26T01:00:00Z')))
  expect(text).not.toContain('Parents prefer Adelaide')
  expect(text).not.toContain('INTERNAL')
  expect(text).not.toContain('Hidden step')
  expect(text).toContain('Study options for Aarav')
  expect(text).not.toMatch(/SS-000142.*SS-000142/) // reference appears once, as the student's own reference
})

test('a missing fee, intake or entry says Confirm with the provider and never shows a made-up figure', async () => {
  const { sheetModel, CONFIRM } = await P()
  expect(CONFIRM).toBe('Confirm with the provider')
  const m = sheetModel(proposal(), new Date('2026-11-26T01:00:00Z'))
  const second = JSON.stringify(m.courses[1])
  expect(second).toContain(CONFIRM)
  expect(second).not.toMatch(/A\$\s?0\b/)
  expect(JSON.stringify(m.courses[0])).toContain('A$16,950')
})

test('the print rules hide the shell, break pages and keep colours; the screen has a one-click print button', () => {
  const css = fs.readFileSync('portal/src/styles.css', 'utf8')
  const print = css.slice(css.indexOf('@media print'))
  expect(print).toMatch(/@page\s*\{[^}]*size:\s*A4/)
  expect(print).toMatch(/\.side[^{]*\{[^}]*display:\s*none/)
  expect(print).toMatch(/\.no-print/)
  expect(print).toMatch(/print-color-adjust:\s*exact/)
  expect(print).toMatch(/break-after:\s*page/)
  const sheet = fs.readFileSync('portal/src/screens/ProposalSheet.jsx', 'utf8')
  expect(sheet).toContain('window.print()')
  expect(sheet).toMatch(/Save as PDF \/ Print/)
  expect(sheet).not.toMatch(/internal_note/)
  expect(sheet).not.toMatch(/browser[- ]?rendering|puppeteer|html2pdf|jspdf/i)
})
