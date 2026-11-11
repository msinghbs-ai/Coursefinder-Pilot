// Guards: F-AER.03 (country and qualification variants) AER qualification-first storage: international qualifications kept with their identity, never a synthetic country (Platform Admin 11 Nov 2026 decisions, items 2 and 3)
// Production 11 Nov 2026: the entry matrix reader dropped 183 rows as unknown_country; they are international qualifications and every-country scopes (IB, GAC, Cambridge
// International, "All countries", "INT"). Migration 20261112060000 stores a provider's requirement for a qualification beside the matrix; worker v0.70.0 keeps such rows.
// Database behaviour is proven on isolated PostgreSQL by tests/fixtures/aer-qualification-first/run.sh (workflow aer-qualification-first-test).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const MIG = 'supabase/migrations/20261112060000_cf247_aer_qualification_first.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
async function load() {
  const out = path.join(os.tmpdir(), `entry-q-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/entry.ts', '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`])
  return import(out)
}
const quals = [{ code: 'IB_DP', aliases: ['international baccalaureate', 'ib diploma', 'ib', 'international baccalaureate diploma'] },
               { code: 'IB_COURSES', aliases: ['international baccalaureate certificate', 'ib certificate'] }, { code: 'GAC', aliases: ['global assessment certificate', 'gac'] }]
const tokens = ['ALL', 'INT', 'WORLDWIDE', 'ALL COUNTRIES', 'GLOBAL']
const row = (o) => ({ country_name: '', study_level: null, min_grade: null, min_value: null, grade_scale: 'none', benchmark_band: null, course_name: null, conditions: {}, confidence: 0.95, ...o })
const page = 'International Baccalaureate (IB) Diploma | 28 points. All countries (CIE/Pearson IGCSE levels) | IGCSE: at least 4 passes. Global Assessment Certificate | GAC: completed with an average of 65%. India | CBSE Year 12 | 75%'
const answer = { rows: [
  row({ country_code: 'International Baccalaureate (IB) Diploma', qualification_name: 'International Baccalaureate (IB) Diploma', min_value: 28, grade_scale: 'points', quote: 'International Baccalaureate (IB) Diploma | 28 points' }),
  row({ country_code: 'ALL', qualification_name: 'IGCSE', quote: 'All countries (CIE/Pearson IGCSE levels) | IGCSE: at least 4 passes' }),
  row({ country_code: 'GAC', qualification_name: 'Global Assessment Certificate', min_value: 65, grade_scale: 'percentage', quote: 'Global Assessment Certificate | GAC: completed with an average of 65%' }),
  row({ country_code: 'IN', country_name: 'India', qualification_name: 'CBSE Year 12', min_value: 75, grade_scale: 'percentage', quote: 'India | CBSE Year 12 | 75%' }),
  row({ country_code: 'Pacific Islands', qualification_name: 'Form 7', quote: 'International Baccalaureate (IB) Diploma | 28 points' }),
  row({ country_code: 'IB', qualification_name: 'IB Diploma', min_value: 30, grade_scale: 'points', quote: 'International Baccalaureate (IB) Diploma | 28 points' })] }

test('without the qualification list the reader behaves exactly as before', async () => {
  const { entryMatrixParsed } = await load()
  const r = entryMatrixParsed(answer, page)
  expect(r.rows.map((x) => x.country_code)).toEqual(['IN'])
  expect(r.qualification_rows).toEqual([])
  expect(r.dropped.filter((d) => d.reason === 'unknown_country').length).toBe(4)
})

test('with the list, a recognised international qualification is kept with its identity; every other check still applies', async () => {
  const { entryMatrixParsed } = await load()
  const r = entryMatrixParsed(answer, page, [], { qualifications: quals, globalTokens: tokens })
  expect(r.qualification_rows.map((x) => [x.qualification_code, x.min_value, x.applicability])).toEqual([['IB_DP', 28, 'unresolved'], ['GAC', 65, 'unresolved']])
  expect(r.rows.map((x) => x.country_code)).toEqual(['IN'])
  expect(r.dropped.some((d) => d.reason === 'unknown_qualification' && d.country === 'ALL')).toBe(true)
  expect(r.dropped.some((d) => d.reason === 'unknown_country' && d.country === 'PACIFIC ISLANDS')).toBe(true)
  expect(r.dropped.filter((d) => d.reason === 'value_not_in_quote').length).toBe(1) // "IB" printed where a country goes is the qualification, its 30 is not printed
  expect(r.rows.some((x) => x.country_code === 'IB')).toBe(false)
})

test('identity by whole alias (longest wins, never part of a word); global only when the page says every country', async () => {
  const { entryQualificationCode, entryApplicability } = await load()
  expect(entryQualificationCode('International Baccalaureate Certificate (IB)', '', quals)).toBe('IB_COURSES')
  expect(entryQualificationCode('Libya school certificate', '', quals)).toBeNull()
  expect(entryApplicability('ALL', 'x', tokens).applicability).toBe('global')
  expect(entryApplicability('IB', 'IB Diploma accepted from all countries', tokens).applicability).toBe('global')
  expect(entryApplicability('IB', 'IB Diploma 28 points', tokens).applicability).toBe('unresolved')
})

test('the database keeps qualification identity apart from country; no synthetic country; additive only', () => {
  expect(code).toContain('create table if not exists ref.aer_qualifications (')
  expect(code).toContain('create table if not exists catalogue.provider_qualification_requirements (')
  expect(code).toContain("check ((scope = 'national') = (country_code is not null))")
  expect(code).not.toMatch(/iso_alpha2\s*=\s*'(GLOBAL|INT|XX|ZZ)'|insert into ref\.countries/i)
  for (const c of ['IB_DP', 'IB_COURSES', 'EB', 'GCE_A', 'CAIE_AL', 'GAC', 'APID', 'NCUK_IFY', 'DE_ABITUR', 'FR_BAC', 'IT_MATURITA', 'IE_LC']) expect(code).toContain(`('${c}',`)
  expect(code).not.toMatch(/alter\s+table\s+(if\s+exists\s+)?catalogue\.provider_entry_matrix|alter\s+table\s+(if\s+exists\s+)?catalogue\.course_entry_requirements/i)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b|cron\.(schedule|alter_job)/im)
})

test('the two live functions are edited only from their live md5; the person decides qualification rows on the same item', () => {
  expect(m).toContain('--   public.svc_entry_matrix_record(uuid,jsonb,numeric,text) 3e76d77b83bc8c1f9514b40f7cb4ac3e -> 7eee2ef2229520266fd56c8aa8f1f1fb')
  expect(m).toContain('--   security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid) 6d7b47fe7d2cd40b9cfb8f3547bad158 -> c46ef6d3f9820c3d4d822846909e35ce')
  expect(code).toContain("raise exception 'live % differs from the definition this change edits (body md5 %)'")
  expect(code).toContain("'proposed',\n              jsonb_build_object('reader', 'entry_ai'")
  expect(code).toContain("position('entry_matrix_gate_v1' in")
  expect(m).toMatch(/^-- Replaces: public\.svc_entry_matrix_record, security\.entry_matrix_review_apply_v1/m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112060000_'))).toEqual(['20261112060000_cf247_aer_qualification_first.sql'])
})

test('worker v0.70.0 asks the database for the qualifications and sends qualification rows', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  // v0.70.0 or a later worker that keeps its v0.70.0 note (F-AER.07 v0.71.0 reads PDF tables by cell and keeps this behaviour)
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(7\d|[89]\d)\.\d+"/)
  expect(w).toContain('v0.70.0 (12 Nov 2026, CF-247 F-AER.03 qualification-first')
  expect(w).toContain('rpc("svc_aer_qualifications_v1", {})')
  expect(w).toContain('...(qrows.length ? { qualification_rows: qrows } : {})')
})
