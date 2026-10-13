// CF-247 v2.15.252 (S17): Platform Admin, 12 Oct 2026 — Layer 3 AI validation is retired. University adapters (Layer 2)
// admit intakes, English requirements and fees, so the AI cascade (intake, English and tuition checks), its screens
// (Layer 3 Control and Work queue, Layer 4 › Send back to AI) and its edge functions are removed. Old addresses still land:
// Layer 3 opens Layer 2 › Adapters and Send back to AI opens the Layer 4 Review queue. layer3-provider-control stays (it
// keeps the OpenRouter key the scholarship AI uses).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { PAGES, SECTIONS, resolveTarget } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')
const srcFiles = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(d => d.isDirectory() ? srcFiles(path.join(dir, d.name)) : /\.(jsx?|css)$/.test(d.name) ? [path.join(dir, d.name)] : [])

test('menu: no Layer 3 page or Send back to AI tab; old addresses resolve to Layer 2 › Adapters and the Review queue', () => {
  expect(PAGES.layer3).toBeUndefined()
  expect(SECTIONS.flatMap(s => s.pages)).not.toContain('layer3')
  expect(SECTIONS.find(s => s.label === 'Data pipeline').pages).toEqual(['coverage', 'layer1', 'layer2', 'layer4'])
  expect(PAGES.layer4.tabs.map(t => t.key)).not.toContain('sendback')
  for (const [addr, tab] of [['layer-3-ai', ''], ['layer-3-ai', 'routing'], ['layer-3-ai', 'work'], ['layer-3-ai-interpretation', ''], ['layer3', ''], ['Layer 3 AI validation', '']])
    expect(resolveTarget(addr, new URLSearchParams(tab ? { tab } : {})), `${addr} ${tab}`).toMatchObject({ page: 'layer2', tab: 'adapters' })
  expect(resolveTarget('layer-3-ai', new URLSearchParams({ tab: 'models' })).page).toBe('services') // v2.15.122 kept
  expect(resolveTarget('layer-4-review', new URLSearchParams({ tab: 'sendback' }))).toMatchObject({ page: 'layer4', tab: 'review' })
})

test('files: Layer 3 screens and functions deleted; layer3-provider-control kept', () => {
  for (const f of ['src/Layer3Operations.jsx', 'src/Layer3Work.jsx', 'src/SendBackToAI.jsx',
    'supabase/functions/layer3-model-routing', 'supabase/functions/layer3-work-dispatch', 'supabase/functions/layer3-work-interpret',
    'supabase/functions/layer3-cf245-tuition-benchmark', 'supabase/functions/layer3-contact-benchmark', 'supabase/functions/layer3-intake-benchmark'])
    expect(fs.existsSync(f), f).toBe(false)
  expect(fs.existsSync('supabase/functions/layer3-provider-control/index.ts')).toBe(true)
  expect(read('src/EnvironmentMigrationWorkspace.jsx')).toContain("supabase.functions.invoke('layer3-provider-control'")
  const wf = read('.github/workflows/deploy-edge-functions.yml')
  for (const f of ['layer3-model-routing', 'layer3-work-dispatch', 'layer3-work-interpret', 'layer3-cf245-tuition-benchmark', 'layer3-intake-benchmark']) expect(wf, f).not.toContain(`[${f}]=`)
  // every shared helper left is still imported by a function
  for (const f of fs.readdirSync('supabase/functions/_shared')) {
    const users = fs.readdirSync('supabase/functions').filter(d => d !== '_shared' && fs.existsSync(`supabase/functions/${d}/index.ts`) && read(`supabase/functions/${d}/index.ts`).includes(`_shared/${f}`))
    expect(users.length, f).toBeGreaterThan(0)
  }
})

test('source: no Send back to AI decision, Layer 3 dashboard tile or Layer 3 settings section', () => {
  for (const f of srcFiles('src')) {
    const s = read(f)
    expect(s, f).not.toContain('return_layer3')
    expect(s, f).not.toContain('Send back to AI')
    expect(s, f).not.toContain('Layer3Operations')
    expect(s, f).not.toContain('SendBackToAI')
  }
  expect(read('src/Dashboard.jsx')).not.toContain('Layer 3 · AI')
  expect(read('src/PipelineSettings.jsx')).not.toContain('data-settings-section="layer3"')
  expect(read('src/lib/workerErrors.js')).not.toContain('layer3-work-dispatch')
})

test.describe('mocked browser', () => {
  test('old Layer 3 addresses open Layer 2 › Adapters', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-3-ai')
    await expect(page).toHaveURL(/#layer-2-discovery$/)
    await expect(page.locator('.m-topbar h1')).toHaveText('Layer 2 Discovery & reading')
    await expect(page.getByRole('tab', { name: 'Adapters' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator('.m-nav').getByRole('button', { name: 'Layer 3 AI validation', exact: true })).toHaveCount(0)
    await page.goto('/#layer-3-ai-interpretation?tab=work')
    await expect(page).toHaveURL(/#layer-2-discovery$/)
  })

  test('old Send back to AI address opens the Layer 4 Review queue; no Layer 3 tile on the Dashboard', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?tab=sendback')
    await expect(page).toHaveURL(/#layer-4-review$/)
    await expect(page.getByRole('tab', { name: 'Review queue' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByRole('tab', { name: 'Send back to AI' })).toHaveCount(0)
    await page.goto('/#dashboard')
    // v2.15.266: the Layers tiles are retired; the Dashboard keeps Waiting for you and four tiles, none for Layer 3
    await expect(page.locator('[data-waiting]')).toBeVisible()
    await expect(page.locator('.db-home')).not.toContainText('Layer 3')
  })
})

test('migration 20261012010100: the 10 Layer 3 jobs are paused (not deleted) and the pending intake, English and fee Layer 4 items closed', () => {
  const s = fs.readFileSync('supabase/migrations/20261012010100_cf247_layer3_retired_pause.sql', 'utf8')
  expect(s).toContain('perform cron.alter_job(v.jobid, active := false);')
  expect(s).toContain("if v_n <> 10 then raise exception 'expected 10 Layer 3 jobs, found %', v_n; end if;")
  expect(s).toContain("field_code in ('course_intake', 'course_english', 'provider_current_tuition_validation')")
  expect(s).not.toMatch(/cron\.unschedule|^(drop|delete|truncate)\b/im)
})
