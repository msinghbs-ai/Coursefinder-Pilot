// Guards: CF-247 s956 (Platform Admin 21 Nov 2026 21:15, Lane 1 item 2; India team review of 20 Nov 2026: REQ-92, REQ-97, REQ-101, REQ-102, REQ-103, REQ-106, REQ-107): country filters read Study destination and Student's education country; durations read in years; the source-reading panel is for Curator and up; Provider contacts can clear its provider and says what it is for; Empty reason and the feed filters explain themselves; statistics cards carry full names
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { fmtDuration } from '../../src/lib/format.js'

const src = f => fs.readFileSync(`src/${f}`, 'utf8')

test('REQ-92: Study destination on Courses, Providers, Scholarships and Entry requirements; Student\'s education country on Entry requirements', () => {
  const m = src('mature-main.jsx'), a = src('AerWorkspace.jsx')
  expect(m).toContain('<PagedFilterSelect kind="country" label="Study destination"')
  expect(m).toContain('return <div className="m-filter-bar" data-provider-filters><FilterSelect label="Study destination"')
  expect(m).toContain('if(type===\'scholarship\')return <div className="m-filter-bar"><FilterSelect label="Study destination"')
  expect(m).toContain("country:'Study destination',")
  expect(a).toContain('<FilterSelect label="Study destination" value={f.destination}')
  expect(a).toContain('<FilterSelect label="Student\'s education country" value={f.country}')
  expect(a).not.toContain('label="Source country"')
})

test('REQ-97: durations read in years with the stored value in brackets', () => {
  expect(fmtDuration(156, 'weeks')).toBe('3 years (156 weeks)')
  expect(fmtDuration(78, 'weeks')).toBe('1.5 years (78 weeks)')
  expect(fmtDuration(24, 'months')).toBe('2 years (24 months)')
  expect(fmtDuration(40, 'weeks')).toBe('40 weeks')
  expect(fmtDuration(null, 'weeks')).toBe(null)
  for (const f of ['DetailSummary.jsx', 'CatalogueColumns.jsx', 'CourseDetailPolish.jsx']) expect(src(f), f).toContain('fmtDuration(')
})

test('REQ-101: the source-reading panel (Read now) shows only from Curator up', () => {
  const a = src('AerWorkspace.jsx')
  const uses = a.split('\n').filter(l => l.includes('<AerReadNow '))
  expect(uses.length).toBe(3)
  for (const l of uses) expect(l).toMatch(/&&(can|Number\(rank\)>=3)&&<AerReadNow /)
})

test('REQ-102: Provider contacts can clear its provider, says what it is for, and lists the live countries', () => {
  const p = src('ProviderContactsWorkspace.jsx')
  expect(p).toContain('<ProviderPicker clearable value={filters.providerId}')
  expect(p).toContain('data-pc-provider-clear')
  expect(p).toContain('data-pc-provider-all>All Providers</button>')
  expect(p).toContain('data-pc-purpose>International recruitment contacts for each provider')
  expect(p).toContain('{countryPairs(lk).map(')
  expect(p).not.toContain('<option value="GB">United Kingdom</option>')
})

test('REQ-103 and REQ-107: filters explain themselves; the feed filters read On website and In Zoho CRM', () => {
  const d = src('DataTable.jsx'), m = src('mature-main.jsx')
  expect(d).toContain("emptyLabel='All',help=''}")
  expect(d).toContain('{help&&<p className="m-filter-help" data-filter-help>{help}</p>}')
  expect(m).toContain('label="Empty reason" help={EMPTY_REASON_HELP}')
  expect(m).toContain('label="On website" help={FEED_HELP.website}')
  expect(m).toContain('label="In Zoho CRM" help={FEED_HELP.zoho}')
  expect(m).toContain("website:'On website',zoho:'In Zoho CRM'")
})

test('REQ-106: statistics cards take their names and publisher from the dataset registry; QILT and PRISMS get their full forms', () => {
  const m = src('mature-main.jsx')
  for (const k of ['qilt', 'prisms', 'qs_wur', 'the_wur']) expect(m).toContain(`{statLabel('${k}',`)
  expect(m).toContain('Published by {a}')
  const mig = fs.readFileSync('supabase/migrations/20261122040000_cf247_s956_statistics_registry_full_names.sql', 'utf8')
  expect(mig).toContain("set label = 'QILT (Quality Indicators for Learning and Teaching)'")
  expect(mig).toContain("set label = 'PRISMS (Provider Registration and International Student Management System)'")
  expect(mig).toMatch(/^-- Retires: nothing\./m)
})
