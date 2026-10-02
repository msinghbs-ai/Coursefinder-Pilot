// CF-247 (2 Oct 2026 overnight): map-first AI link matcher, identity v0.5.7, re-identify, directory capture (hints only),
// AI page-identity check (qualification only, never switched on).
import fs from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import os from 'node:os'
import path from 'node:path'
import { test, expect } from '@playwright/test'

async function bundle(src, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('npx', ['esbuild', src, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
const page = (h1, title) => `<html><head><title>${title}</title></head><body><h1>${h1}</h1><p>text</p></body></html>`

test('matcher: one pinned model; a choice must be one of the prepared candidates; refusals return to the queue', async () => {
  const idx = await fs.readFile('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(idx).toContain('export const AI_MATCH_MODEL = "qwen/qwen3-30b-a3b-instruct-2507";')
  expect(idx).toContain('if (d?.model && d.model !== AI_MATCH_MODEL) throw Error(`returned model ${d.model}`);')
  const m = await fs.readFile('supabase/migrations/20261002184400_cf247_ai_link_matcher.sql', 'utf8')
  expect(m).toContain("chosen address is not one of the candidates")
  expect(m).toContain("coalesce(pipeline.coverage_course_pages.basis, '') <> 'manual'")
  const k = await fs.readFile('supabase/migrations/20261002185100_cf247_ai_match_key_limit.sql', 'utf8')
  expect(k).toContain("p_error ~ '^HTTP (401|402|403|429)\\M'")
})

test('identity v0.5.7: a national code before the exact title is the exact title; nothing else is loosened', async () => {
  const { identity } = await bundle('supabase/functions/coverage-sweep/extract.ts', 'ex57')
  expect(identity(page('CHC52025 Diploma of Community Services', 'x'), 't', 'Diploma of Community Services', '111681B')).toBe('exact_title')
  expect(identity(page('CHC42021 Certificate IV in Community Services', 'x'), 't', 'Diploma of Community Services', '111681B')).toBe(null)
  expect(identity(page('Graduate Certificate of Business Administration', 'Graduate Certificate of Business Administration | Swinburne'), 't', 'Graduate Certificate of Business Administration (International)', '091577E')).toBe(null)
  expect(identity(page('CHC52025 Diploma of Community Services and Youth Work', ''), 't', 'Diploma of Community Services', '111681B')).toBe(null)
})

test('page identity v1.0.2: a "yes" needs the name on the page, the same qualification type and the same words', async () => {
  const { pageIdChecks, PAGE_ID_CONTRACT } = await bundle('supabase/functions/coverage-sweep/pageid.ts', 'pid')
  expect(PAGE_ID_CONTRACT).toBe('cf247-page-identity-v1.0.2')
  const ok = (c, n, t) => pageIdChecks(c, { page_course_name: n, same_course: true }, t ?? n).accepted
  expect(ok('Diploma of Hospitality Management', 'Advanced Diploma of Hospitality Management')).toBe(false)
  expect(ok('Certificate IV in Disability', 'Certificate IV in Disability Support')).toBe(false)
  expect(ok('Master of Advanced Nursing Practice', 'Master of Nursing')).toBe(false)
  expect(ok('Bachelor of Engineering (Honours) (Civil)', 'Bachelor of Engineering (Honours) (Electrical)')).toBe(false)
  expect(ok('Bachelor of Information Technology Bachelor of International Studies', 'Bachelor of Information Technology')).toBe(false)
  expect(ok('Diploma of Information Technology', 'ICT50220 - Diploma of Information Technology')).toBe(true)
  expect(ok('Bachelor of Business', 'Bachelor of Business - VU Brisbane')).toBe(true)
  expect(pageIdChecks('Bachelor of Science', { page_course_name: 'Bachelor of Science', same_course: false }, 'Bachelor of Science').accepted).toBe(false)
})

test('page identity is qualification only and directory pages are hints only', async () => {
  const idx = await fs.readFile('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(idx).toContain('if (mode === "id_qualify")')
  expect(idx).not.toMatch(/mode === "id_check"|mode === "ai_identity"/) // no live mode yet
  for (const f of ['20261002184900_cf247_page_identity_holdout.sql', '20261002185000_cf247_page_identity_holdout_h2.sql', '20261002185200_cf247_directory_match.sql'])
    expect(await fs.readFile(`supabase/migrations/${f}`, 'utf8')).not.toMatch(/coverage_course_pages\s+set|insert into catalogue\.|update catalogue\./i)
  const d = await fs.readFile('supabase/migrations/20261002184800_cf247_directory_capture.sql', 'utf8')
  expect(d).toContain('nothing from them is admitted')
  expect(idx).toContain('const DIRECTORY_HOSTS: Record<string, string> = { hotcourses: "www.hotcoursesabroad.com", univcc: "univ.cc" };')
})

test('22:26 decisions: AU English by exact title too; robots.txt per RFC 9309; Firecrawl only when direct reading fails', async () => {
  const m = await fs.readFile('supabase/migrations/20261002185600_cf247_au_english_exact_title.sql', 'utf8')
  expect(m).toContain(`jsonb_build_object('english', '["cricos_code", "exact_title"]'::jsonb)`)
  const f = await fs.readFile('supabase/migrations/20261002185700_cf247_english_policy_flag_step.sql', 'utf8')
  expect(f).not.toMatch(/status = 'approved', decided_by/) // the flag step approves nothing
  const idx = await fs.readFile('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(idx).toContain('else if (direct && (direct.status === 404 || direct.status === 410)) robotsState = "none";')
  expect(idx).toContain('else if (direct?.ok) robotsState = "no_rules";')
  expect(idx).toContain('if (robotsState === "unreadable") return j(')
  expect(idx).toContain('robotsAllows(await robotsFor(new URL(u.origin)), "/") && await useFc("site_hint", it.provider_id, u.origin + "/")')
})

test('Decision 235: Canadian field + award rule (Canada only) and the website name rule', async () => {
  const { identity, fieldAward, domainFitsName, siteNameMatch, staleCalendarUrl } = await bundle('supabase/functions/coverage-sweep/extract.ts', 'ex235')
  const fa = (h1, t, text = 'Vancouver') => fieldAward(h1, '', text, t) === 'field_award'
  expect(fa('Doctor of Philosophy in Medical Genetics', 'Medical Genetics: Doctor of Philosophy (PhD) - UBCV')).toBe(true)
  expect(fa('Medical Genetics (PhD)', 'Medical Genetics: Doctor of Philosophy (PhD) - UBCV')).toBe(true)
  expect(fa('Master of Science in Health Sciences', 'Master of Science Health Sciences')).toBe(true)
  expect(fa('Doctor of Philosophy in Clinical Psychology', 'Psychology: Doctor of Philosophy (PhD)')).toBe(false)
  expect(fa('Master of Arts in Psychology', 'Psychology: Doctor of Philosophy (PhD)')).toBe(false)
  expect(fa('Psychology', 'Psychology: Master of Arts (MA)')).toBe(false)
  expect(fa('Graduate programs', 'Physics: Doctor of Philosophy (PhD)')).toBe(false)
  expect(fa('Master of Science and Doctor of Philosophy in Physics', 'Physics: Doctor of Philosophy (PhD)')).toBe(false)
  expect(fa('Bachelor of Arts in English (Okanagan)', 'English: Bachelor of Arts Degree (BA) - UBCV')).toBe(false)
  expect(fa('Biochemistry and Molecular Biology (PhD)', 'Biochemistry and Molecular Biology: Doctor of Philosophy (PhD) - UBCO', 'Okanagan')).toBe(false)
  expect(fa('Combined Bachelor of Music', 'Combined Bachelor of Music/Bachelor of Education World Music')).toBe(false)
  expect(fa('Mathematics Honours (Bachelor of Science)', 'Mathematics: Bachelor of Science Degree (BSc)')).toBe(false)
  expect(fieldAward('Master of Science in Mathematics (MSc)', 'Master of Science in Mathematics (MSc) | Graduate School', 'menu: Okanagan campus', 'Mathematics: Master of Science (MSc) - UBCO')).toBe(null)
  expect(fieldAward('Master of Science in Mathematics (MSc)', 'Master of Science in Mathematics (MSc) - Okanagan | Graduate School', 'x', 'Mathematics: Master of Science (MSc) - UBCO')).toBe('field_award')
  const page = '<html><head><title>Bachelor of Science Biology</title></head><body><h1>Bachelor of Science in Biology</h1></body></html>'
  expect(identity(page, 'x', 'Bachelor of Science Biology', '', false, 'AU')).toBe('exact_title')
  expect(identity('<h1>Bachelor of Science in Biology</h1>', 'x', 'Biology: Bachelor of Science (BSc)', '', false, 'AU')).toBe(null)
  expect(identity('<h1>Bachelor of Science in Biology</h1>', 'x', 'Biology: Bachelor of Science (BSc)', '', false, 'CA')).toBe('field_award')
  expect(staleCalendarUrl('https://www.sfu.ca/students/calendar/2015/spring/programs/finance/master-of-science.html', new Date('2026-10-02'))).toBe(true)
  expect(staleCalendarUrl('http://www.sfu.ca/students/calendar/2026/fall/programs/mathematics/major/bachelor-of-science.html', new Date('2026-10-02'))).toBe(false)
  expect(staleCalendarUrl('https://www.grad.ubc.ca/prospective-students/graduate-degree-programs/phd-linguistics', new Date('2026-10-02'))).toBe(false)
  expect(domainFitsName('www.bcit.ca', 'british columbia institute of technology')).toBe(true)
  expect(domainFitsName('www.ufv.ca', 'university of fraser valley')).toBe(true)
  expect(domainFitsName('www.royalroads.ca', 'royal roads university')).toBe(true)
  expect(domainFitsName('www.universitystudy.ca', 'university of victoria')).toBe(false)
  const home = '<html><head><title>BCIT</title></head><body><h1>Welcome</h1><footer>© British Columbia Institute of Technology</footer></body></html>'
  expect(siteNameMatch(home, '© British Columbia Institute of Technology', 'British Columbia Institute of Technology', '', 'www.bcit.ca')).toBe('name_in_page_and_domain')
  expect(siteNameMatch(home, '© British Columbia Institute of Technology', 'British Columbia Institute of Technology', '', 'www.studyinbc.ca')).toBe(null)
})

test('Decision 236: New Zealand degree name (NZ only), with an optional abbreviation', async () => {
  const { identity, nzDegreeName } = await bundle('supabase/functions/coverage-sweep/extract.ts', 'ex236')
  const nz = (h1, t, text = 'x') => nzDegreeName(h1, '', text, t) === 'degree_name'
  expect(nz('Master of Fire Engineering Studies', 'Master of Fire Engineering Studies (Level 9)')).toBe(true)
  expect(nz('Master of Literature MLitt', 'Master of Literature (Level 9)')).toBe(true)
  expect(nz('Bachelor of Arts / Bachelor of Commerce Conjoint BA/BCom', 'Conjoint: Bachelor of Arts/Bachelor of Commerce (Level 7)')).toBe(false)
  expect(nz('Postgraduate Certificate in Design PGCertDes', 'Certificate in Design (Level 5)')).toBe(false)
  expect(nz('Bachelor of Arts Honours', 'Bachelor of Arts (Level 7)')).toBe(false)
  expect(nz('Master of Science', 'Master of Science in Physics (Level 9)')).toBe(false)
  expect(nz('Master of Fine Arts', 'Master of Fine Arts (Level 9)', 'master of fine arts level 8')).toBe(false)
  expect(nz('Master of Arts', 'Master of Arts (Level 9)')).toBe(false)
  expect(nz('Bachelor of Laws LLB', 'Bachelor of Laws (Level 7)')).toBe(false)
  expect(nz('Master of Planning', 'Master of Planning (Level 9)')).toBe(true)
  expect(identity('<h1>Master of Literature MLitt</h1>', 'x', 'Master of Literature (Level 9)', '', false, 'AU')).toBe(null)
  expect(identity('<h1>Master of Literature MLitt</h1>', 'x', 'Master of Literature (Level 9)', '', false, 'NZ')).toBe('degree_name')
})
