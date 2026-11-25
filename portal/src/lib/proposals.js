// Student proposals: pure helpers (no browser, network or database code), so a spec can run them directly.
// The contract these helpers expect is in the portal design document ("Release 2 contract: student proposals").
import { money, durationText, durationInYears, dateText, NOT_RECORDED } from './format.js'

// What the student sheet prints when the platform holds nothing (design: anything not recorded prints this).
export const CONFIRM = 'Confirm with the provider'

const STATUS = {
  draft: { label: 'Draft', tone: 'grey' },
  ready: { label: 'Ready to send', tone: 'teal' },
  sent: { label: 'Sent', tone: 'blue' },
  accepted: { label: 'Accepted', tone: 'green' },
  archived: { label: 'Archived', tone: 'grey' },
}
const words = code => String(code || '').replace(/[_-]+/g, ' ').trim()
export function statusInfo(code) {
  if (STATUS[code]) return STATUS[code]
  const w = words(code)
  return { label: w ? w.charAt(0).toUpperCase() + w.slice(1) : 'Draft', tone: 'grey' }
}

// Only the student reference, given name and family initial are held about a student (design decisions, 25 Nov 2026).
const STUDENT_KEYS = ['ref', 'given_name', 'family_initial', 'source_country', 'qualification', 'result_text', 'english_text', 'destination', 'preferred_intake', 'budget_per_year', 'budget_currency']

export function blankProposal(defaults = {}) {
  const student = {}
  for (const k of STUDENT_KEYS) student[k] = ''
  return {
    id: null, version: 0, status: 'draft', title: '', student: { ...student, ...(defaults.student || {}) },
    courses: [], steps: Array.isArray(defaults.steps) ? defaults.steps.map(s => ({ ...s })) : [],
    documents: Array.isArray(defaults.documents) ? [...defaults.documents] : [],
    message_to_student: '', internal_note: '',
  }
}

// A saved course, a search result or a basket entry becomes one proposal course. The database builds the stored snapshot on
// save; until then the screen shows what it already holds about the course.
export function courseFromSummary(c) {
  return {
    course_id: c.course_id,
    why: c.why_text || '',
    snapshot: {
      title: c.title || c.snapshot?.title || '', provider_name: c.provider_name || c.snapshot?.provider_name || '',
      state_code: c.state_code ?? null, city: c.city ?? null, level: c.level ?? null,
      duration_value: c.duration_value ?? null, duration_unit: c.duration_unit ?? null, delivery_mode: c.delivery_mode ?? null,
      fee: c.fee ?? null, next_intake: c.next_intake ?? null,
      provisional: true,
    },
  }
}

export function addCourses(current, incoming, max) {
  const have = new Set(current.map(c => c.course_id))
  const next = [...current]
  let duplicates = 0, overLimit = 0
  for (const c of incoming) {
    if (have.has(c.course_id)) { duplicates += 1; continue }
    if (Number.isFinite(Number(max)) && Number(max) > 0 && next.length >= Number(max)) { overLimit += 1; continue }
    have.add(c.course_id)
    next.push(c.snapshot ? c : courseFromSummary(c))
  }
  return { courses: next, added: next.length - current.length, duplicates, overLimit }
}

export function moveCourse(courses, from, to) {
  if (from === to || from < 0 || to < 0 || from >= courses.length || to >= courses.length) return courses
  const next = [...courses]
  const [item] = next.splice(from, 1)
  next.splice(to, 0, item)
  return next
}
export const removeCourse = (courses, id) => courses.filter(c => c.course_id !== id)

const trim = v => (typeof v === 'string' ? v.trim() : v)

// What is sent on save. The stored course snapshot and the version belong to the database, so only the choices go up.
export function proposalPayload(p) {
  const student = {}
  for (const k of STUDENT_KEYS) student[k] = trim(p.student?.[k] ?? '')
  return {
    title: trim(p.title) || defaultTitle(p),
    status: p.status || 'draft',
    student,
    courses: p.courses.map((c, n) => ({ course_id: c.course_id, position: n + 1, why: trim(c.why || '') })),
    steps: (p.steps || []).map(s => ({ key: s.key ?? null, title: trim(s.title || ''), detail: trim(s.detail || ''), owner: s.owner || 'counsellor', due_label: trim(s.due_label || ''), due_date: s.due_date || null, included: s.included !== false })),
    documents: (p.documents || []).map(trim).filter(Boolean),
    message_to_student: trim(p.message_to_student || ''),
    internal_note: trim(p.internal_note || ''),
  }
}
export const isDirty = (saved, draft) => JSON.stringify(proposalPayload(saved)) !== JSON.stringify(proposalPayload(draft))

export function defaultTitle(p) {
  const s = p.student || {}
  const who = [trim(s.given_name), trim(s.family_initial) ? `${String(trim(s.family_initial)).replace(/\.$/, '')}.` : ''].filter(Boolean).join(' ')
  return who ? `${who}: study options` : 'Study options'
}

// Problems to fix before saving, in plain words. Limits come from the database with the proposal; none is written here.
export function validateProposal(p, limits = {}) {
  const out = []
  if (!trim(p.student?.given_name)) out.push('Add the student’s given name.')
  const initial = trim(p.student?.family_initial)
  if (initial && String(initial).replace(/\.$/, '').length > 1) out.push('The family name initial is one letter only. No full family name is stored.')
  const cap = (value, max, what) => { if (Number(max) > 0 && String(value || '').length > Number(max)) out.push(`${what} is longer than ${Number(max).toLocaleString('en-AU')} characters.`) }
  cap(p.message_to_student, limits.message_max_chars, 'The message to the student')
  cap(p.internal_note, limits.note_max_chars, 'The counsellor notes')
  for (const c of p.courses || []) cap(c.why, limits.why_max_chars, 'A “why this course” line')
  if (Number(limits.courses_max) > 0 && p.courses.length > Number(limits.courses_max)) out.push(`A proposal holds up to ${limits.courses_max} courses.`)
  return out
}

// Melbourne time, as the counsellors read it.
const MEL = 'Australia/Melbourne'
const melDay = d => new Intl.DateTimeFormat('en-CA', { timeZone: MEL, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
const clock = d => new Intl.DateTimeFormat('en-AU', { timeZone: MEL, hour: 'numeric', minute: '2-digit', hour12: true }).format(d).replace(/\s?(am|pm)$/i, (_, x) => ` ${x.toLowerCase()}`)

export function whenText(iso, now = new Date()) {
  if (!iso) return null
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return null
  const today = melDay(now), day = melDay(d)
  if (day === today) return `today, ${clock(d)}`
  const y = new Date(now.getTime() - 24 * 3600 * 1000)
  if (day === melDay(y)) return `yesterday, ${clock(d)}`
  return dateText(iso, 'day')
}
export function agoText(iso, now = new Date()) {
  const t = new Date(iso).getTime()
  if (!Number.isFinite(t)) return null
  const mins = Math.max(0, Math.round((now.getTime() - t) / 60000))
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins} ${mins === 1 ? 'minute' : 'minutes'} ago`
  const hours = Math.round(mins / 60)
  return `${hours} ${hours === 1 ? 'hour' : 'hours'} ago`
}

// ----- Live refresh -----
export function groupChanges(changes) {
  const by = new Map()
  for (const c of Array.isArray(changes) ? changes : []) {
    const k = c.course_id || 'other'
    if (!by.has(k)) by.set(k, [])
    by.get(k).push(c)
  }
  return by
}
export const changeCount = changes => (Array.isArray(changes) ? changes.length : 0)

// ----- Student sheet (print) -----
const DELIVERY = { on_campus: 'On campus', online: 'Online', blended: 'Blended', on_campus_and_online: 'On campus and online' }
const confirm = v => (v === null || v === undefined || v === '' || v === NOT_RECORDED ? CONFIRM : v)

export function sheetCourse(c, n) {
  const s = c.snapshot || {}
  const f = s.fee
  const per = f && Number(f.per_year) > 0 ? money(f.per_year, f.currency) : null
  const years = durationInYears(s.duration_value, s.duration_unit)
  const total = per && years ? money(Math.round(Number(f.per_year) * years), f.currency) : null
  const place = [s.city, s.state_code ? String(s.state_code).replace(/^[A-Z]{2}-/, '') : ''].filter(Boolean).join(', ')
  const length = durationText(s.duration_value, s.duration_unit)
  const mode = DELIVERY[s.delivery_mode]
  const i = s.next_intake
  const intake = i ? [i.label || dateText(i.start_date, 'day'), i.note].filter(Boolean).join(', ') : null
  return {
    n: n + 1, courseId: c.course_id,
    title: s.title || CONFIRM, provider: confirm(s.provider_name), campus: confirm(place),
    length: length === NOT_RECORDED ? CONFIRM : [length, mode ? mode.toLowerCase() : ''].filter(Boolean).join(', '),
    tuition: per ? `${per} a year` : CONFIRM,
    tuitionTotal: per && total ? `about ${total} in total` : null,
    nextIntake: confirm(intake), startDate: i?.start_date || null,
    entry: confirm(s.entry?.text), english: confirm(s.english?.text), scholarship: confirm(s.scholarship?.text),
    why: c.why || '',
  }
}

const OWNER = { student: 'you', counsellor: 'your counsellor' }
export function sheetModel(p, now = new Date()) {
  const s = p.student || {}
  const given = trim(s.given_name) || 'you'
  const who = [trim(s.given_name), trim(s.family_initial) ? `${String(trim(s.family_initial)).replace(/\.$/, '')}.` : ''].filter(Boolean).join(' ')
  const courses = (p.courses || []).map((c, n) => sheetCourse(c, n))
  const steps = (p.steps || []).filter(x => x.included !== false && trim(x.title)).map((x, n) => ({
    n: n + 1, title: x.title, detail: x.detail || '', due: x.due_label || (x.due_date ? dateText(x.due_date, 'day') : ''), owner: OWNER[x.owner] || '',
  }))
  const dates = []
  const submit = (p.steps || []).find(x => x.key === 'submit_applications' && x.included !== false && (x.due_date || x.due_label))
  if (submit) dates.push({ when: submit.due_label || dateText(submit.due_date, 'day'), what: 'applications go in', sort: submit.due_date || '' })
  for (const c of courses) if (c.startDate) dates.push({ when: dateText(c.startDate, 'day'), what: `course ${c.n} starts`, sort: c.startDate })
  dates.sort((a, b) => String(a.sort).localeCompare(String(b.sort)))
  return {
    heading: `Study options for ${given}`,
    prepared: dateText(now.toISOString(), 'day'),
    asAt: p.details_checked_at ? dateText(p.details_checked_at, 'day') : null,
    student: {
      who, ref: trim(s.ref) || '', country: trim(s.source_country_name || s.source_country) || '',
      qualification: [trim(s.qualification), trim(s.result_text)].filter(Boolean).join(', '),
      english: trim(s.english_text) || '', budget: Number(s.budget_per_year) > 0 ? `${money(s.budget_per_year, s.budget_currency)} a year` : '',
    },
    message: trim(p.message_to_student) || '',
    courses, steps, documents: (p.documents || []).map(trim).filter(Boolean), dates,
    counsellor: p.counsellor || null,
  }
}
