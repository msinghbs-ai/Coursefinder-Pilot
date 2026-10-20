// Screen review package 3 (v2.15.123): duplicate screens merged; nothing a person used is lost.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS, resolveTarget } from '../../src/nav-map.js'

const read = p => fs.readFileSync(p, 'utf8')

test('Regulatory settings merged into Layer 1; its Pilot reset and the readiness gates sit on the Go-live checklist', () => {
  expect(PAGES.regulatory).toBeUndefined()
  expect(SECTIONS.find(s => s.label === 'Platform settings').pages).toEqual(['environment', 'services', 'dataModel', 'retention', 'migration']) // v2.15.300: Scrapers & fetchers is Models & services › Fetchers
  expect(PAGES.migration.label).toBe('Go-live checklist')
  expect(PAGES.environment.label).toBe('Settings') // v2.15.160: the pipeline settings page, keys below
  // v2.15.246 (bugs 11/10-3): Manual batch runs retired; each source has Run now in Layer 1 › Sources, recorded as one job.
  expect(PAGES.layer1.tabs.find(t => t.key === 'batch')).toBeUndefined()
  const r = resolveTarget('regulatory-settings')
  expect([r.page, r.tab]).toEqual(['layer1', 'operations'])
  expect(resolveTarget('layer-1-register', new URLSearchParams({ tab: 'batch' })).tab).toBe('operations')
  const main = read('src/mature-main.jsx')
  expect(main).not.toContain('mode="batch"')
  // v2.15.228: Reset database retired (Platform Admin, 9 Oct 2026)
  expect(main).not.toContain('mode="reset"')
  expect(read('src/lib/supabase.js')).not.toContain('pilot-reset')
  expect(fs.existsSync('src/RegulatorySettings.jsx')).toBe(false) // 18 Oct 2026: unused screen retired
})

test('Readiness is flat: Capacity on Platform health, gates and UAT on Go-live; Layer 4 › Blocks retired (v2.15.253)', () => {
  expect(PAGES.health.tabs.find(t => t.key === 'readiness').label).toBe('Capacity')
  expect(PAGES.layer4.tabs.find(t => t.key === 'blocks')).toBeUndefined()
  const main = read('src/mature-main.jsx')
  expect(main).toContain("case'layer4':return <Layer4Inbox onError={err} routeParams={routeParams}/>") // v2.15.300: the Inbox only
  expect(main).not.toContain('view="blocks"')
  const pm = read('src/platform-maturity-entry.jsx')
  expect(pm).toContain("view==='capacity'?<>")
  expect(pm).toContain("view==='golive'?<>")
  expect(pm).not.toContain('BlockConsole')
})

test('v2.15.124: Readiness by area is part of Attributes; the cross-layer Sources list is under Operations', () => {
  expect(PAGES.coverage.tabs.map(t => t.key)).toEqual(['courses', 'attributes', 'progress', 'flags']) // v2.15.300: Counsellor reports in the Inbox /* v2.15.282: Flags; v2.15.292: Counsellor reports */ // v2.15.266: Progress; v2.15.200 Decision 254: Universities retired into Layer 2 › Adapters
  expect(resolveTarget('coverage', new URLSearchParams({ tab: 'domains' })).tab).toBe('attributes')
  expect(resolveTarget('data-quality-readiness').tab).toBe('attributes')
  expect(PAGES.layer1.tabs.map(t => t.key)).toEqual(['operations', 'scholarships']) // v2.15.246: one Sources list
  expect(SECTIONS.find(s => s.label === 'Operations').pages).toEqual(['health', 'jobs', 'evidence', 'sources', 'apiUsage']) // CF-247 16 Oct 2026: API usage
  expect(resolveTarget('layer-1-register', new URLSearchParams({ tab: 'sources' })).page).toBe('sources')
  expect(read('src/data-quality-entry.jsx')).not.toContain('No single completeness score')
})

test('v2.15.124: Schedules folded into Automations; the copied job list is gone (history is on Jobs)', () => {
  expect(PAGES.jobs.tabs.map(t => t.key)).toEqual(['automations', 'jobs', 'tasks']) // v2.15.197: Task manager; v2.15.300: Priority queue retired
  expect(resolveTarget('scheduled-jobs', new URLSearchParams({ tab: 'schedules' })).tab).toBe('automations')
  expect(resolveTarget('scheduled-tasks').tab).toBe('automations')
  const w = read('src/ScheduledJobsWorkspace.jsx')
  expect(w).not.toContain('<h3>Recent Job Runs</h3>')
  expect(w).toContain('cf-scheduler-v2-native')
})
