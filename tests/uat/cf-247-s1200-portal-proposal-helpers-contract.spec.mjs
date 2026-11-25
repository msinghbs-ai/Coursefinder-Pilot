// Guards: StudySearch Portal Release 2 (Platform Admin 26 Nov 2026, S1-API-Frontend-Delivery): proposal helpers keep PII minimal, take limits from the server, and never invent a figure
// CF-247 S1200: the pure proposal helpers (portal/src/lib/proposals.js). A proposal holds a student reference, a given name and one family initial only.
import { test, expect } from '@playwright/test'

const P = () => import('../../portal/src/lib/proposals.js')
const snap = (over = {}) => ({ title: 'Bachelor of Accounting', provider_name: 'Barton Business School', fee: { per_year: 19600, currency: 'AUD', year: 2027 }, duration_value: 3, duration_unit: 'years', next_intake: { label: 'Feb 2027', start_date: '2027-02-15', status: 'open' }, ...over })
const base = () => ({
  id: 'p1', version: 3, status: 'draft', title: '', internal_note: 'Parents prefer Adelaide, budget is tight',
  student: { ref: 'SS-000142', given_name: 'Aarav', family_initial: 'S', qualification: 'CBSE Class XII', result_text: '72%', english_text: 'IELTS Academic 6.5', budget_per_year: 25000, budget_currency: 'AUD' },
  courses: [{ course_id: 'c1', position: 1, why: 'Lowest fee', snapshot: snap() }, { course_id: 'c2', position: 2, why: '', snapshot: snap({ title: 'Associate Degree of Veterinary Nursing', fee: null, next_intake: null }) }],
  steps: [{ key: 'submit_applications', title: 'Submit applications', owner: 'counsellor', due_date: '2026-12-15', due_label: '15 Dec 2026', included: true }],
  documents: ['Passport', '  ', 'Statement of purpose'], message_to_student: 'Hello Aarav',
  counsellor: { name: 'Mandeep Singh', title: 'Education Counsellor' },
})

test('the save payload carries only the minimal student fields and sends positions, not snapshots', async () => {
  const { proposalPayload } = await P()
  const p = base(); p.student.passport = 'N1234567'; p.student.email = 'a@b.test'; p.student.family_name = 'Sharma'
  const out = proposalPayload(p)
  expect(Object.keys(out.student)).not.toEqual(expect.arrayContaining(['passport', 'email', 'family_name']))
  expect(out.student.given_name).toBe('Aarav')
  expect(out.courses).toEqual([{ course_id: 'c1', position: 1, why: 'Lowest fee' }, { course_id: 'c2', position: 2, why: '' }])
  expect(JSON.stringify(out)).not.toContain('Barton')
  expect(out.documents).toEqual(['Passport', 'Statement of purpose'])
  expect(out.title.length).toBeGreaterThan(0)
})

test('reorder, remove and add keep a stable order and refuse duplicates and over-limit additions', async () => {
  const { moveCourse, removeCourse, addCourses, isDirty, proposalPayload } = await P()
  const p = base()
  expect(moveCourse(p.courses, 0, 1).map((c) => c.course_id)).toEqual(['c2', 'c1'])
  expect(moveCourse(p.courses, 0, -1).map((c) => c.course_id)).toEqual(['c1', 'c2'])
  expect(removeCourse(p.courses, 'c1').map((c) => c.course_id)).toEqual(['c2'])
  const r = addCourses(p.courses, [{ course_id: 'c2', title: 'dup' }, { course_id: 'c3', title: 'New', provider_name: 'X' }, { course_id: 'c4', title: 'Over' }], 3)
  expect(r).toMatchObject({ added: 1, duplicates: 1, overLimit: 1 })
  expect(r.courses.map((c) => c.course_id)).toEqual(['c1', 'c2', 'c3'])
  const moved = { ...p, courses: moveCourse(p.courses, 0, 1) }
  expect(isDirty(p, p)).toBe(false)
  expect(isDirty(p, moved)).toBe(true)
  expect(proposalPayload(moved).courses.map((c) => c.position)).toEqual([1, 2])
})

test('validation reads its limits from the server and holds none of its own', async () => {
  const { validateProposal } = await P()
  const p = base(); p.message_to_student = 'x'.repeat(50)
  expect(validateProposal(p, {})).toEqual([])
  expect(validateProposal(p, { message_max_chars: 40 }).join(' ')).toMatch(/message to the student/i)
  expect(validateProposal(p, { courses_max: 1 }).join(' ')).toMatch(/up to 1 courses/)
  p.student.family_initial = 'Sharma'
  expect(validateProposal(p, {}).join(' ')).toMatch(/one letter/i)
  p.student.given_name = ''
  expect(validateProposal(p, {}).join(' ')).toMatch(/given name/i)
})

test('whenText speaks Melbourne time in plain words', async () => {
  const { whenText } = await P()
  const now = new Date('2026-11-26T01:00:00Z') // 12:00 pm Melbourne
  expect(whenText('2026-11-25T22:41:00Z', now)).toMatch(/^today, 9:41 am$/)
  expect(whenText('2026-11-25T06:02:00Z', now)).toMatch(/^yesterday, /)
  expect(whenText('2026-11-18T01:00:00Z', now)).toMatch(/18 Nov 2026/)
  expect(whenText(null, now)).toBeNull()
  expect(whenText('not a date', now)).toBeNull()
})

test('changes group and count without inventing a change', async () => {
  const { groupChanges, changeCount } = await P()
  expect(changeCount(undefined)).toBe(0)
  const ch = [{ course_id: 'c1', course_title: 'A', field: 'fee', label: 'Annual tuition', from_text: 'A$1', to_text: 'A$2' }, { course_id: 'c1', course_title: 'A', field: 'intake', label: 'Next intake', from_text: 'Feb', to_text: 'Jul' }]
  expect(changeCount(ch)).toBe(2)
  const g = groupChanges(ch)
  expect([...g.keys()]).toEqual(['c1'])
  expect(g.get('c1').map((c) => c.label)).toEqual(['Annual tuition', 'Next intake'])
  expect(groupChanges(undefined).size).toBe(0)
})
