import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { fmtDate, fmtDateTime, fmtNumber, fmtMoney, fmtPercent, fmtShare } from '../../src/lib/format.js'

// B2 UI uniformity release (v2.15.106) with refinement R12.
const read = p => fs.readFileSync(p, 'utf8')

test('one token set: colour literals live only in tokens.css, loaded first', () => {
  const out = execFileSync('node', ['scripts/verify-ui-tokens.mjs'], { encoding: 'utf8' })
  expect(out).toContain('ui-tokens: PASS')
  const html = read('index.html')
  expect(html.indexOf('/src/tokens.css')).toBeGreaterThan(0)
  expect(html.indexOf('/src/tokens.css')).toBeLessThan(html.indexOf('/src/ui-kit.css'))
  const tokens = read('src/tokens.css')
  for (const t of ['--cf-fs-md:', '--cf-radius-md:', '--cf-shadow-card:', '--cf-space-4:', '--m-bg:', '--dq-ink:', '--ops-bg:', '--cf-insight-ink:']) expect(tokens).toContain(t)
  for (const f of ['src/mature.css', 'src/data-quality.css', 'src/pipeline-ops.css']) expect(read(f)).not.toMatch(/:root\{--(m|dq|ops)-/)
})

test('en-AU formats from one shared module', () => {
  expect(fmtDate('2026-09-29')).toBe('29 Sep 2026')
  // v2.15.131: times are Melbourne time for every viewer (AEST +10 here, AEDT +11 from 4 Oct).
  expect(fmtDateTime('2026-09-29T04:37:00Z')).toBe('29 Sep 2026, 2:37 pm')
  expect(fmtDateTime('2026-10-05T04:37:00Z')).toBe('5 Oct 2026, 3:37 pm')
  expect(fmtDate('2026-09-30T15:00:00Z')).toBe('1 Oct 2026')
  expect(fmtDateTime(null)).toBe('—')
  expect(fmtNumber(25978)).toBe('25,978')
  expect(fmtMoney(31680, 'AUD')).toBe('A$31,680')
  expect(fmtMoney(0.345126, 'USD', { decimals: 4 })).toBe('US$0.3451')
  expect(fmtPercent(49.2)).toBe('49.2%')
  expect(fmtPercent(100)).toBe('100.0%')
  expect(fmtShare(404, 25978)).toBe('1.6%')
  const offenders = fs.readdirSync('src').filter(f => /\.(jsx?|mjs)$/.test(f)).filter(f => /toLocale(Date|Time)?String\(|Intl\.(Number|DateTime)Format/.test(read('src/' + f)))
  expect(offenders).toEqual([])
})

test('one component kit and "Layer N" wording', () => {
  const kit = read('src/ui-kit.jsx')
  for (const c of ['export function StatusChip', 'export function Badge', 'export function LayerBadge', 'export function Button', 'export function Metric', 'export function Empty', 'export function FilterChip', 'export function Loading', 'export function SectionTitle', 'export function statusTone']) expect(kit).toContain(c)
  for (const f of ['src/pipeline-ops-entry.jsx', 'src/platform-maturity-entry.jsx', 'src/EvidenceWorkspace.jsx', 'src/ScheduledJobsWorkspace.jsx', 'src/m2-3-intelligence-entry.jsx', 'src/mature-main.jsx']) expect(read(f)).toMatch(/from'\.\/ui-kit'/)
  for (const f of ['src/CourseDetailPolish.jsx', 'src/ScheduledJobsWorkspace.jsx', 'src/Layer4Intervention.jsx', 'src/course-coverage.jsx']) {
    expect(read(f)).not.toMatch(/>L[1-4]\b|'L[1-4] |Awaiting L[1-4]|\(L[1-4]\)/)
  }
})

test('R12: Course coverage reports completeness states and the completeness score', () => {
  const m = read('supabase/migrations/20260929190000_cf247_coverage_completeness_states.sql')
  expect(m).toContain("md5(prosrc) from pg_proc where oid='security.admin_course_coverage_read(text,jsonb)'::regprocedure)<>'a624cf66621a749cdd395cf530466927'")
  for (const s of ["'present'", "'source_null'", "'not_applicable'", "'zero'", "'suppressed'", "'not_yet_enriched'", "'stale'", "'ambiguous'", "'rejected'"]) expect(m).toContain(s)
  expect(m).toContain("'completeness_states'")
  expect(m).toContain('pipeline.completeness_daily')
  expect(m).toContain('pipeline.course_completeness')
  const v = read('src/course-coverage.jsx')
  expect(v).toContain('Course completeness score')
  expect(v).toContain('Completeness by attribute')
  expect(v).toContain('completeness_state:pick.cstate')
})
