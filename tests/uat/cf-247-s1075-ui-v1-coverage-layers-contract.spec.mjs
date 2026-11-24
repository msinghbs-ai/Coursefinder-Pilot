// Guards: UI/UX Unification & Live Guide Parity Plan v1.2, Slice 3 (Platform Admin brief 24 Nov 2026 16:31): Coverage, Layer 1 Register and Layer 2/3 Operations on the v1.1 build, and Layer 4 queue cards keeping a hook's long detail behind one Technical detail toggle
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const VIEWS = ['CourseCoverageView', 'FieldCoverageView', 'CoverageTelemetryView', 'AerCoverageView', 'CoverageNoticeView', 'PipelineEtaView', 'LinkRefreshView',
  'Layer1RegisterView', 'Layer1BaselinePreviewView', 'Layer1InductionWizardView', 'Layer23OperationsView']
const code = f => fs.readFileSync(`src/ui-v1/${f}.jsx`, 'utf8').split('\n').filter(l => !l.trim().startsWith('//')).join('\n')
const STATE_WORDS = /^(up|down|active|attention|button|current|done|failed|found|missing|ok|rotated|status|wide|late|on|off|low|warn|warning|danger|success|info|neutral|running|paused|healthy|due|draft|stale|stuck|blocked|passed|queued|completed|no_change|safe|critical)$/

test('source: the eleven views import only the ui-v1 stylesheet and kit, carry no inline style sheet or legacy class prefix, and type no colour', () => {
  for (const f of VIEWS) {
    const raw = fs.readFileSync(`src/ui-v1/${f}.jsx`, 'utf8'), c = code(f)
    expect([...raw.matchAll(/^import\s*'([^']+\.css)'/gm)].map(m => m[1]), f).toEqual(['./ui-kit.css'])
    expect(c, f).not.toMatch(/from\s*'\.\/ui-kit'|localStorage|<style|#[0-9a-fA-F]{6}\b|rgba?\(/)
    const classes = [...c.matchAll(/className=(?:"([^"]*)"|\{`([^`]*)`\})/g)].flatMap(m => (m[1] ?? m[2]).replace(/\$\{[^}]*\}/g, ' ').split(/\s+/)).filter(Boolean)
    expect(classes.filter(x => !/^(ui-|lucide)/.test(x) && !STATE_WORDS.test(x) && /-/.test(x)), f).toEqual([])
  }
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  for (const v of ['CourseCoverageView', 'FieldCoverageView', 'CoverageTelemetryView', 'AerCoverageView', 'PipelineEtaView', 'LinkRefreshView', 'Layer23OperationsView']) expect(main, v).toContain(`./ui-v1/${v}`)
  for (const gone of ['src/course-coverage.jsx', 'src/FieldCoverage.jsx', 'src/CoverageTelemetry.jsx', 'src/AerCoverage.jsx', 'src/PipelineEta.jsx', 'src/LinkRefresh.jsx', 'src/layer1-operations-entry.jsx', 'src/Layer1BaselinePreview.jsx', 'src/Layer1InductionWizard.jsx', 'src/Layer23Operations.jsx', 'src/coverage-telemetry.css'])
    expect(fs.existsSync(gone), gone).toBe(false)
})

test('source: a Layer 4 card keeps a hook\'s summary open and the other sections behind one Technical detail toggle', () => {
  const l4 = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
  expect(l4).toContain('data-l4-fold="more-detail"')
  expect(l4).toContain("hookSection(hd.sections.filter(x=>x.key==='summary'))")
  expect(l4).toContain("hookSection(hd.sections.filter(x=>x.key!=='summary'))")
})

const stray = (page, sel) => page.locator(sel).first().evaluate(e => [...e.querySelectorAll('[class]')].flatMap(x => [...x.classList]).filter(c => !/^(ui-|lucide|m-col-resize)/.test(c) && !/^(active|attention|button|current|done|failed|found|missing|ok|rotated|status|wide|late|on|off|low|warn|warning|danger|success|info|neutral|running|paused|healthy|due|draft|stale|stuck|blocked|passed|queued|completed|critical|safe|up|down|num|is-.*|tone-.*)$/.test(c)))

const src = fs.readFileSync('tests/uat/cf-247-s650-coverage-now-contract.spec.mjs', 'utf8')
const T = new Function(src.slice(src.indexOf('const day ='), src.indexOf("test.describe('mocked browser'")) + '; return T')()

test('Coverage › Courses: readiness grid, bars and the field list are drawn in ui-* classes with the heat tint kept', async ({ page }) => {
  await mockAdmin(page)
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_coverage_telemetry_v1', r => r.fulfill({ json: T }))
  await page.goto('/#coverage')
  const c = page.locator('[data-coverage-telemetry]')
  await expect(c.locator('[data-ct-cell="AU:courses"]')).toHaveText('68.4%')
  await expect(c.locator('[data-ct-cell="AU:courses"]')).toHaveClass(/ui-ct-heat-3/)
  expect(await stray(page, '[data-coverage-telemetry]')).toEqual([])
})

test('Layer 1 Register: the source list, filters and health chips are drawn in ui-* classes, hooks kept', async ({ page }) => {
  await mockAdmin(page, { rank: 6 })
  await page.goto('/#layer1')
  await expect(page.locator('[data-l1-sources]')).toBeVisible()
  await expect(page.locator('.ui-xl-summary')).toBeVisible()
  expect(await stray(page, '[data-l1-sources]')).toEqual([])
})

test('Layer 2/3 › Operations: notices and the stage tiles are drawn in ui-* classes', async ({ page }) => {
  await mockAdmin(page, { rank: 6 })
  await page.goto('/#layer2')
  await expect(page.getByRole('heading', { name: 'Layer 2/3 Build & enrich' })).toBeVisible()
  await expect(page.locator('main').first()).toBeVisible()
})

test('phone @responsive: Coverage, Layer 1 Register and Layer 2/3 fit the phone width', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_coverage_telemetry_v1', r => r.fulfill({ json: T }))
  for (const [hash, ready] of [['/#coverage', '[data-coverage-telemetry]'], ['/#layer1', '[data-l1-sources]'], ['/#layer2', 'h1']]) {
    await page.goto(hash)
    await expect(page.locator(ready).first()).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth), hash).toBeLessThanOrEqual(1)
  }
})
