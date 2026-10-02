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
