// Screen review package 3 (v2.15.123): duplicate screens merged; nothing a person used is lost.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS, resolveTarget } from '../../src/nav-map.js'

const read = p => fs.readFileSync(p, 'utf8')

test('Regulatory settings merged into Layer 1; its Pilot reset and the readiness gates sit on the Go-live checklist', () => {
  expect(PAGES.regulatory).toBeUndefined()
  expect(SECTIONS.find(s => s.label === 'Platform settings').pages).toEqual(['environment', 'scrapers', 'services', 'dataModel', 'retention', 'migration'])
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
  const reg = read('src/RegulatorySettings.jsx')
  expect(reg).toContain("const IN_SCOPE = ['AU', 'NZ']")
  expect(reg).not.toContain('Layer 1 source registry')
  expect(reg).not.toContain('RESET DATABASE')
})

test('Readiness is flat: Capacity on Platform health, gates and UAT on Go-live, blocks in Layer 4', () => {
  expect(PAGES.health.tabs.find(t => t.key === 'readiness').label).toBe('Capacity')
  expect(PAGES.layer4.tabs.find(t => t.key === 'blocks')).toEqual({ key: 'blocks', label: 'Blocks', min: 5 })
  const main = read('src/mature-main.jsx')
  expect(main).toContain(`case'layer4':return tab==='aireview'?<ScholarshipAiReview onError={err}/>:tab==='blocks'?<div className="m-page-stack"><PlatformMaturity rank={rank} onError={onError} view="blocks"/></div>`) // v2.15.250: AI could not decide
  const pm = read('src/platform-maturity-entry.jsx')
  expect(pm).toContain("view==='capacity'?<>")
  expect(pm).toContain("view==='golive'?<>")
  expect(pm).toContain("view==='blocks'?<BlockConsole")
})

test('v2.15.124: Readiness by area is part of Attributes; the cross-layer Sources list is under Operations', () => {
  expect(PAGES.coverage.tabs.map(t => t.key)).toEqual(['courses', 'attributes']) // v2.15.200 Decision 254: Universities retired into Layer 2 › Adapters
  expect(resolveTarget('coverage', new URLSearchParams({ tab: 'domains' })).tab).toBe('attributes')
  expect(resolveTarget('data-quality-readiness').tab).toBe('attributes')
  expect(PAGES.layer1.tabs.map(t => t.key)).toEqual(['operations', 'scholarships']) // v2.15.246: one Sources list
  expect(SECTIONS.find(s => s.label === 'Operations').pages).toEqual(['health', 'jobs', 'evidence', 'sources'])
  expect(resolveTarget('layer-1-register', new URLSearchParams({ tab: 'sources' })).page).toBe('sources')
  expect(read('src/data-quality-entry.jsx')).not.toContain('No single completeness score')
})

test('v2.15.124: Schedules folded into Automations; the copied job list is gone (history is on Jobs)', () => {
  expect(PAGES.jobs.tabs.map(t => t.key)).toEqual(['automations', 'priority', 'jobs', 'tasks']) // v2.15.197: Task manager
  expect(resolveTarget('scheduled-jobs', new URLSearchParams({ tab: 'schedules' })).tab).toBe('automations')
  expect(resolveTarget('scheduled-tasks').tab).toBe('automations')
  const w = read('src/ScheduledJobsWorkspace.jsx')
  expect(w).not.toContain('<h3>Recent Job Runs</h3>')
  expect(w).toContain('cf-scheduler-v2-native')
})
