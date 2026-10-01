// Screen review package 3 (v2.15.123): duplicate screens merged; nothing a person used is lost.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS, resolveTarget } from '../../src/nav-map.js'

const read = p => fs.readFileSync(p, 'utf8')

test('Regulatory settings merged into Layer 1; its Pilot reset and the readiness gates sit on the Go-live checklist', () => {
  expect(PAGES.regulatory).toBeUndefined()
  expect(SECTIONS.find(s => s.label === 'Platform settings').pages).toEqual(['environment', 'scrapers', 'services', 'dataModel', 'migration'])
  expect(PAGES.migration.label).toBe('Go-live checklist')
  expect(PAGES.environment.label).toBe('Environment & keys')
  expect(PAGES.layer1.tabs.find(t => t.key === 'batch')).toEqual({ key: 'batch', label: 'Manual batch runs', min: 6 })
  const r = resolveTarget('regulatory-settings')
  expect([r.page, r.tab]).toEqual(['layer1', 'batch'])
  const main = read('src/mature-main.jsx')
  expect(main).toContain(`if(tab==='batch')return <div className="m-legacy-host"><RegulatorySettings onError={onError} mode="batch"/></div>`)
  expect(main).toContain(`<PlatformMaturity rank={rank} onError={onError} view="golive"/><div className="m-legacy-host"><RegulatorySettings onError={onError} mode="reset"/></div>`)
  const reg = read('src/RegulatorySettings.jsx')
  expect(reg).toContain("const IN_SCOPE = ['AU', 'NZ']")
  expect(reg).not.toContain('Layer 1 source registry')
  expect(reg).toContain("if (confirmText.trim().toUpperCase() !== 'RESET DATABASE') return")
})

test('Readiness is flat: Capacity on Platform health, gates and UAT on Go-live, blocks in Layer 4', () => {
  expect(PAGES.health.tabs.find(t => t.key === 'readiness').label).toBe('Capacity')
  expect(PAGES.layer4.tabs.find(t => t.key === 'blocks')).toEqual({ key: 'blocks', label: 'Blocks', min: 5 })
  const main = read('src/mature-main.jsx')
  expect(main).toContain(`case'layer4':return tab==='blocks'?<div className="m-page-stack"><PlatformMaturity rank={rank} onError={onError} view="blocks"/></div>`)
  const pm = read('src/platform-maturity-entry.jsx')
  expect(pm).toContain("view==='capacity'?<>")
  expect(pm).toContain("view==='golive'?<>")
  expect(pm).toContain("view==='blocks'?<BlockConsole")
})
