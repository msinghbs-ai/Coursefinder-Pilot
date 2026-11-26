// Guards: Atlas brief 26 Nov 2026 15:59 AEDT, Platform Admin portal UAT (s1222): a fluid full-width desktop layout with card grids; a Cards/List toggle kept per person on Courses, Saved courses and Entry Requirements; Course details in a right-hand drawer (a full-height sheet on a phone) that keeps the list's place; concise cards with no "Not recorded" boxes and one annual tuition fee; the national course code beside the title and the Course page link beside Course details; India and Nepal pinned first in every student-country list from the G2 setting portal.priority_source_countries; the Course details country selector reads that country's matrix rows (course, study level, provider) with a plain fallback
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const SRC = 'portal/src'
const MIG = 'supabase/migrations/20261129130000_cf247_s1222_portal_uat_data.sql'
const SCREENS = ['Courses', 'Saved', 'EntryRequirements']

test('migration: additive, guarded, pinned countries are a G2 setting and nothing is dropped', () => {
  const m = read(MIG)
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m)
  expect(m).not.toMatch(/\bdrop\s+(table|function|view|index|schema)\b/i); expect(m).not.toMatch(/\bdelete\s+from\b/i)
  expect(m).toMatch(/values \('portal', 'priority_source_countries', /)
  for (const f of ['portal.primary_fee_v1', 'portal.regulator_code_v1', 'portal.entry_matrix_v1', 'public.portal_entry_matrix_v1']) expect(m).toContain(`create or replace function ${f}(`)
  expect(m).toMatch(/security\.portal_rank_v1\(1\)/)
  expect(m).toMatch(/revoke all on function public\.portal_entry_matrix_v1\(jsonb\) from public, anon/i)
  // the replaced bodies were checked before replacement
  for (const h of ['2d4c96da6741d865f440b5d1a21980a1', 'dc9ed8ea2e47c52fbda609d4bd6c50d7', '10e320440fdd8c7b5ce37cf361dbdfb6', '1e86de1c476a110939747e0e3a73a05f']) expect(m).toContain(h)
})

test('one annual fee: the current Melbourne year first, then the nearest later year, then the latest earlier year', () => {
  const m = read(MIG)
  const fn = m.slice(m.indexOf('create or replace function portal.primary_fee_v1('), m.indexOf('$$;', m.indexOf('create or replace function portal.primary_fee_v1(')))
  expect(fn).toMatch(/Australia\/Melbourne/)
  expect(fn).toMatch(/'basis', 'annual'/)
  expect(fn).not.toMatch(/\b20(2[5-9]|3\d)\b/)
})

test('student-country lists: priority countries first from the setting, a divider, then A to Z; none written into a screen', async () => {
  const { orderMarkets } = await import('../../portal/src/lib/markets.js')
  const list = [{ code: 'AU', name: 'Australia' }, { code: 'NP', name: 'Nepal' }, { code: 'BD', name: 'Bangladesh' }, { code: 'IN', name: 'India' }]
  const r = orderMarkets(list, ['IN', 'NP'])
  expect(r.pinned.map(m => m.code)).toEqual(['IN', 'NP'])
  expect(r.rest.map(m => m.code)).toEqual(['AU', 'BD'])
  expect(orderMarkets(list, []).pinned).toEqual([])
  expect(orderMarkets(list, ['zz', 'np']).pinned.map(m => m.code)).toEqual(['NP'])
  const portal = read(`${SRC}/lib/portal.jsx`)
  expect(portal).toContain('state.settings.priority_source_countries')
  for (const f of ['screens/EntryRequirements.jsx', 'screens/Providers.jsx', 'screens/ProposalEditor.jsx', 'components/CourseDetails.jsx']) {
    const s = read(`${SRC}/${f}`)
    expect(s, f).toContain('<MarketOptions markets={markets} priority={priority} />')
    expect(s, f).not.toMatch(/markets\.map\(/)
    expect(s, f).not.toMatch(/['"](IN|NP|India|Nepal)['"]/)
  }
  expect(read(`${SRC}/components/ui.jsx`)).toMatch(/<option disabled value="__divider">/)
})

test('Cards or List on Courses, Saved courses and Entry Requirements, kept for the person', () => {
  expect(read(`${SRC}/lib/portal.jsx`)).toMatch(/setView: v => update\(\{ view: v === 'list' \? 'list' : 'cards' \}\)/)
  for (const f of SCREENS) {
    const s = read(`${SRC}/screens/${f}.jsx`)
    expect(s, f).toContain('<ViewToggle value={view} onChange={setView} />')
    expect(s, f).toContain('<div className="card-grid">')
    expect(s, f).toContain('<div className="list" role="list">')
  }
})

test('Course details open in the drawer; Escape, close and the shaded area close it; the list stays mounted', () => {
  const d = read(`${SRC}/components/DetailDrawer.jsx`)
  expect(d).toContain('role="dialog" aria-modal="true"')
  expect(d).toContain("e.key === 'Escape'")
  expect(d).toContain("document.body.style.overflow = 'hidden'")
  expect(d).toMatch(/e\.target === e\.currentTarget\) onClose\(\)/)
  expect(d).toMatch(/<ExtLink className="btn" href=\{course\.course_url\}>Course page ↗<\/ExtLink>/)
  for (const f of SCREENS) expect(read(`${SRC}/screens/${f}.jsx`), f).not.toMatch(/&& <CourseDetails/)
})

test('concise cards: no Not recorded, one fee, the course code beside the title, Course page next to Course details', () => {
  for (const f of SCREENS) {
    const s = read(`${SRC}/screens/${f}.jsx`)
    expect(s, f).toContain('<RegBadge r={c.regulator} />')
    expect(s, f).toMatch(/<DetailsButton[^\n]*\/>\n\s*<ExtLink className="btn" href=\{c\.(course_url|official_url)\}>Course page ↗<\/ExtLink>/)
    expect(s, f).not.toMatch(/<div className="cells">|className="cell"/)
  }
  for (const f of ['Courses', 'EntryRequirements']) expect(read(`${SRC}/screens/${f}.jsx`), f).not.toContain('NOT_RECORDED')
  expect(read(`${SRC}/components/CourseRow.jsx`)).toContain('<RegBadge r={c.regulator} />')
})

test('Course details: one primary fee with other lines folded, and one entry section grouped by scope with a fallback', async () => {
  const p = read(`${SRC}/components/CourseDetails.jsx`)
  expect(p).toContain('body.primary_fee')
  expect(p).toMatch(/<details className="d-more"><summary>Other recorded fee lines/)
  expect(p).toContain('has no entry requirement recorded for')
  expect(p).toContain('state.countryRows === 0')
  const f = await import('../../portal/src/lib/courseDetailFormat.js')
  const g = f.groupByScope([{ scope: 'provider', country: 'A' }, { scope: 'course', country: 'B' }, { scope: 'study_level', country: 'C' }])
  expect(g.map(x => x.key)).toEqual(['course', 'study_level', 'provider'])
  expect(f.primaryFeeAmount({ per_year: 49840, currency: 'AUD', year: 2026 })).toMatch(/49,840/)
  expect(f.primaryFeeAmount(null)).toBeNull()
  expect(f.primaryFeeNote({ year: 2026 })).toBe('per year · 2026 fee · provider')
  expect(f.lengthOrBlank(null, null)).toBe('')
})

test('layout: fluid full width with card grids; drawer is a full sheet on a phone; tap targets 44px', () => {
  const css = read(`${SRC}/styles.css`)
  expect(css).toMatch(/\.content \{[^}]*max-width:1680px/)
  expect(css).not.toMatch(/\.content \{[^}]*max-width:1100px/)
  const b = css.slice(css.indexOf('/* s1222: portal UAT fixes'))
  expect(b).toMatch(/\.card-grid \{ display:grid; grid-template-columns:repeat\(auto-fill,minmax\(min\(100%,360px\),1fr\)\)/)
  expect(b).toMatch(/\.vt-btn \{[^}]*min-height:44px/)
  expect(b).toMatch(/\.drawer-close \{[^}]*min-width:44px/)
  expect(b).toMatch(/@media \(max-width:640px\) \{\s*\.drawer \{ width:100vw/)
  expect(b).toMatch(/\.chip-x button \{ width:44px; height:44px \}/)
})
