// Guards: Atlas brief to S1-API-Frontend-Delivery, 26 Nov 2026 12:02 AEDT (Platform Admin live UAT): an expandable Course details panel on Courses and Saved courses, every outside link opening in a new tab, and a separate Entry Requirements (AER) screen; Viewer reads, Counsellor saves and adds to a proposal; amended by s1222 (Atlas brief 26 Nov 2026 15:59 AEDT, portal UAT fixes: concise cards, drawer, pinned student countries); amended by s1355 (Platform Admin PC-20261128-CONTINUOUS-BUILD-EXECUTE and the evening country-neutral gates: a fee is shown in the currency it is held in and labelled by the course's own register, never a fixed country)
// CF-247 s1215: portal screens. The read functions (s1214, S2-Build) and the study-levels read (s1215) are guarded in their migration contracts; this spec guards the screens, the one link component and the menu.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

const read = p => fs.readFileSync(p, 'utf8')
const SRC = 'portal/src'
const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)])
const jsx = walk(SRC).filter(f => f.endsWith('.jsx'))

test('every outside link goes through ExtLink: new tab, noopener noreferrer, web addresses only', () => {
  const ext = read(`${SRC}/components/ExtLink.jsx`)
  expect(ext).toContain('target="_blank" rel="noopener noreferrer"')
  expect(ext).toMatch(/\^https\?:\\\/\\\//)
  // No other anchor in the portal writes a value into an href unless it is a portal hash route; an outside address must use ExtLink.
  for (const f of jsx.filter(f => !f.endsWith('ExtLink.jsx'))) {
    for (const m of read(f).matchAll(/<a\b[^>]*\bhref=(\{[^}]*\}|"[^"]*")/g)) {
      const v = m[1]
      expect(/^"#|^\{`#|^\{"#|^\{'#/.test(v), `${f}: ${v}`).toBe(true)
    }
  }
})

test('outside links on every screen use ExtLink: course, provider website, scholarship, proposal course', () => {
  expect(read(`${SRC}/screens/Courses.jsx`)).toMatch(/<ExtLink[^>]*href=\{c\.course_url\}/)
  expect(read(`${SRC}/screens/Saved.jsx`)).toMatch(/<ExtLink[^>]*href=\{c\.course_url\}/)
  expect(read(`${SRC}/screens/Providers.jsx`)).toMatch(/<ExtLink[^>]*href=\{p\.website\}/)
  expect(read(`${SRC}/screens/Scholarships.jsx`)).toMatch(/<ExtLink[^>]*href=\{s\.source_url\}/)
  expect(read(`${SRC}/screens/ProposalEditor.jsx`)).toMatch(/<ExtLink[^>]*href=\{s\.course_url\}/)
  expect(read(`${SRC}/screens/EntryRequirements.jsx`)).toMatch(/<ExtLink[^>]*href=\{c\.official_url\}/)
  expect(read(`${SRC}/components/CourseDetails.jsx`)).toMatch(/<ExtLink[^>]*href=\{body\.official_url\}/)
})

test('the menu order is the brief’s, Entry Requirements is open to a Viewer, Saved courses and Proposals are Counsellor only', () => {
  const shell = read(`${SRC}/screens/Shell.jsx`)
  const nav = [...shell.slice(shell.indexOf('const NAV'), shell.indexOf(']\n', shell.indexOf('const NAV'))).matchAll(/\{ to: '([^']+)', label: '([^']+)'(, counsellor: true)?/g)]
  expect(nav.map(m => m[2])).toEqual(['Dashboard', 'Courses', 'Entry Requirements', 'Universities & Providers', 'Scholarships', 'Saved courses', 'Proposals'])
  expect(Object.fromEntries(nav.map(m => [m[2], Boolean(m[3])]))).toEqual({
    Dashboard: false, Courses: false, 'Entry Requirements': false, 'Universities & Providers': false, Scholarships: false, 'Saved courses': true, Proposals: true,
  })
  expect(shell).toContain("here === '/entry-requirements') return <EntryRequirements access={access} />")
  expect(shell).not.toMatch(/entry-requirements[^\n]*COUNSELLOR_ONLY/)
})

test('Entry Requirements: reads the one function, filters come from the database, Save and Add to proposal are Counsellor only', () => {
  const s = read(`${SRC}/screens/EntryRequirements.jsx`)
  expect(s).toContain("'portal_aer_list_v1'"); expect(s).toContain("'portal_study_levels_v1'")
  expect(s).toContain('access.kind === \'counsellor\'')
  // s1222: the two Counsellor buttons sit in one component that renders nothing for a Viewer.
  expect(s).toContain('if (!canSave) return null')
  expect((s.match(/<button type="button" className=\{`btn\$\{(saved|inBasket) \? ' on' : ''\}`\}/g) || []).length).toBe(2)
  expect(s).toContain("'♡ Save'"); expect(s).toMatch(/Add to proposal/)
  // s930: destinations, markets and levels are read live; none is written into the screen.
  expect(s).toContain('setLevels(l)')
  expect(s).not.toMatch(/\b(Australia|Canada|New Zealand|United Kingdom|Ireland|Bachelor|Masters?)\b/)
  expect(s).toMatch(/Student’s country of education/); expect(s).toMatch(/Study level/); expect(s).toMatch(/Provider or course/)
  expect(s).toContain('<StudyInBar />')
})

test('the Course details panel is on Courses, Saved courses and Entry Requirements, reads the course when opened, and says Not recorded', () => {
  // s1222: the panel opens in the right-hand drawer (DetailDrawer), so the list keeps its place.
  for (const f of ['Courses', 'Saved', 'EntryRequirements']) {
    const s = read(`${SRC}/screens/${f}.jsx`)
    expect(s, f).toContain('<DetailsButton'); expect(s, f).toMatch(/<DetailDrawer course=\{openCourse/)
    expect(s, f).toContain('onClose={() => setOpenCourse(null)}')
  }
  expect(read(`${SRC}/components/DetailDrawer.jsx`)).toContain('<CourseDetails id={`drawer-${course.course_id}`} courseId={course.course_id} />')
  const p = read(`${SRC}/components/CourseDetails.jsx`)
  for (const h of ['Overview', 'Campuses and delivery', 'Fees', 'Intakes and deadlines', 'Academic entry requirements', 'English language requirements', 'Career outcomes', 'Official source']) expect(p).toContain(`title="${h}"`)
  expect(p).toMatch(/aria-expanded/); expect(read(`${SRC}/lib/courseDetail.js`)).toMatch(/'portal_course_detail_v1', \{ p_course_id: courseId \}/)
  expect(p).toContain('NOT_RECORDED'); expect(p).toMatch(/Different lines are not added together/); expect(p).toMatch(/not this course/)
  // no sum of fee lines on the panel
  expect(p).not.toMatch(/reduce\(|\bsum\b/)
})

test('phone layout at 412px: panel and entry cards stack to one column and tap targets are at least 44px', () => {
  const css = read(`${SRC}/styles.css`)
  const phone = css.slice(css.lastIndexOf('/* s1215'))
  expect(phone).toMatch(/@media \(max-width:640px\)[\s\S]*\.d-grid, \.er-grid \{ grid-template-columns:1fr \}/)
  expect(phone).toMatch(/\.details \.btn, \.details select, \.er-col a \{ min-height:44px \}/)
  expect(phone).toMatch(/a\.textlink \{[^}]*min-height:44px/)
})

test('the pure formatting reads recorded values and never adds fee lines together', async () => {
  const cd = read(`${SRC}/components/CourseDetails.jsx`)
  expect(cd).toContain('<FeeList rows={fees} regulator={body.regulator} />'); expect(cd).toContain('feeLabel(f, regulator)')
  expect(read(`${SRC}/lib/format.js`)).not.toMatch(/\|\|\s*'AUD'/)
  const f = await import('../../portal/src/lib/courseDetailFormat.js')
  expect(f.feeLabel({ fee_type: 'provider_current_tuition', basis: 'annual' })).toBe('Tuition per year (provider)')
  expect(f.feeLabel({ fee_type: 'provider_current_tuition', basis: 'total_indicative' })).toMatch(/whole course/)
  expect(f.feeIsAnnual({ fee_type: 'provider_current_tuition', basis: 'indicative_annual' })).toBe(true); expect(f.feeIsAnnual({ fee_type: 'tuition', basis: 'registered_total_course' })).toBe(false)
  expect(f.feeLabel({ fee_type: 'estimated_total_course_cost' })).toMatch(/Estimated total/)
  expect(f.feeAmount({ amount: 21000, currency: 'AUD' })).toBe('A$21,000')
  expect(f.feeAmount({ amount: null, currency: 'AUD' })).toBe('Not recorded')
  // s1355: no country is assumed. The registered-fee label names the course's own register; a missing currency shows the figure alone; an outcome unit may be any ISO currency.
  expect(f.feeLabel({ fee_type: 'tuition' }, { label: 'CRICOS', scheme: 'cricos' })).toBe('Registered tuition for the whole course (CRICOS)')
  expect(f.feeLabel({ fee_type: 'non_tuition' }, { label: 'NZQA' })).toBe('Non-tuition fees for the whole course (NZQA)')
  expect(f.feeLabel({ fee_type: 'estimated_total_course_cost' }, null)).toBe('Estimated total course cost')
  expect(f.feeAmount({ amount: 28000, currency: 'NZD' })).toBe('NZ$28,000'); expect(f.feeAmount({ amount: 15477, currency: 'CAD' })).toBe('CA$15,477')
  expect(f.feeAmount({ amount: 21000, currency: null })).toBe('21,000'); expect(f.feeAmount({ amount: 21000 })).not.toMatch(/\$/)
  expect(f.outcomeValue({ unit: 'NZD', value: 61000 })).toBe('NZ$61,000'); expect(f.outcomeValue({ unit: 'GBP', value: 30000 })).toBe('£30,000')
  const pm = await import('../../portal/src/lib/proposals.js')
  const sheet = (cur, courses) => pm.sheetModel({ student: { budget_per_year: '40000', budget_currency: cur }, courses: courses.map(c => ({ snapshot: { fee: { per_year: 30000, currency: c } } })) }).student.budget
  expect(sheet('', ['NZD', 'NZD'])).toBe('NZ$40,000 a year'); expect(sheet('', ['NZD', 'AUD'])).toBe('40,000 a year'); expect(sheet('', [])).toBe('40,000 a year'); expect(sheet('CAD', ['AUD'])).toBe('CA$40,000 a year')
  const e = f.entryLine({ kind: 'minimum_grade', description: 'ATAR 70', min_grade: '70', country_code: null })
  expect(e.main).toBe('ATAR 70'); expect(e.grade).toBe(''); expect(e.kind).toBe('Minimum grade')
  expect(f.entryLine({ kind: 'prior_qualification', description: 'Bachelor degree', min_value: 4.5, grade_scale: '7-point' }).grade).toBe('4.5 (7-point)')
  // a line that names no country applies to everyone; a named country applies to that country only
  const rows = [{ description: 'a', country_code: null }, { description: 'b', country_code: 'IN' }, { description: 'c', country_code: 'NP' }]
  expect(f.entryForMarket(rows, '').map(r => r.description)).toEqual(['a']); expect(f.entryForMarket(rows, 'IN').map(r => r.description)).toEqual(['a', 'b'])
  expect(f.englishLine({ test_name: 'IELTS Academic', overall_score: 6.5, component_scores: { reading: 6, writing: 6 } })).toEqual({ test: 'IELTS Academic', overall: '6.5 overall', parts: 'Reading 6 · Writing 6', notes: '' })
  expect(f.outcomeValue({ unit: 'percent', value: 78.54 })).toBe('78.5%'); expect(f.outcomeValue({ unit: 'AUD', value: 65000 })).toBe('A$65,000')
  expect(f.outcomeValue({ unit: 'percent', value: null })).toBe('Not recorded')
  expect(f.intakeText({ label: 'March', year: 2027 })).toBe('March 2027')
  expect(f.deliveryText('on_campus_and_online')).toBe('On campus and online'); expect(f.deliveryText(null)).toBe('Not recorded')
})
