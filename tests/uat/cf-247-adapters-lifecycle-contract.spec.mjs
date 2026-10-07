// CF-247 Decision 254 (6 Oct 2026, Platform Admin 15:25 to 15:39): Layer 2 › Adapters, the adapter lifecycle in one place,
// collapsed cards remembered for the browser session, and the retired screens.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, resolveTarget } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'
import { openAdapter, openCard } from './support/cards.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('migration 1750: read cycle, Adapters list and detail, per-adapter admit, all behind md5 guards, nothing destructive', () => {
  const m = read('supabase/migrations/20261006001750_cf247_adapters_lifecycle.sql')
  for (const word of ['drop', 'delete from', 'truncate', 'cascade']) expect(m.toLowerCase().replace(/--[^\n]*/g, '')).not.toContain(word)
  for (const line of m.split('\n')) if (/\bupdate\s+\S+\s+(\w+\s+)?set\b/i.test(line)) expect(line).toMatch(/\bwhere\b/i)
  for (const lit of m.replace(/--[^\n]*/g, '').replace(/\$s\$[\s\S]*?\$s\$/g, '').matchAll(/'(?:[^']|'')*'/g)) expect(lit[0]).not.toContain(';')
  for (const g of ['f186cfbfa0173ebf00a8236ecc215b92', '128fcc8c475f93ada292060c785846ec', '68bf25c2ac72ad26a09aad0219e62367']) expect(m).toContain(`is distinct from '${g}'`)
  expect(m).toContain('check (read_cycle_days is null or read_cycle_days between 7 and 365)')
  expect(m).toContain("coalesce((select a.read_cycle_days from pipeline.uni_adapters a where a.provider_id=v_row.provider_id), 90)")
  expect(m).toContain("if v_rank < 6 then raise exception 'Platform Admin required'") // switching, cycle and admit are Platform Admin
  expect(m).toContain("q.job_id::text = j.args->'qual_jobs'->>q.provider_id::text")
  expect(m).toContain("coalesce((v_j.args->'qual_jobs'->>v_pid::text)::uuid, (v_j.args->>'qualification_job_id')::uuid)")
  expect(m).toContain("qj.kind = 'qualify_adapters' and qj.state = 'done'") // only a finished Qualify can be admitted from
  expect(m).not.toMatch(/public\.admin_uni_adapter_control\('admit'/) // this file admits nothing: the slice does, through the ordinary control
  expect(m).toContain("'uni_adapter_switch'")
})

test('screens: Layer 2 is Adapters, Adapter builder and Scholarships, Coverage has no Universities tab, redirects keep old links working', () => {
  expect(PAGES.layer2.tabs.map(t => t.key)).toEqual(['adapters', 'builder', 'scholarships'])
  expect(PAGES.coverage.tabs.map(t => t.key)).toEqual(['courses', 'attributes'])
  for (const old of ['operations', 'start', 'history', 'profiles']) expect(resolveTarget('layer-2-discovery', new URLSearchParams({ tab: old }))).toMatchObject({ page: 'layer2', tab: 'adapters' })
  expect(resolveTarget('coverage', new URLSearchParams({ tab: 'universities' }))).toMatchObject({ page: 'layer2', tab: 'adapters' })
  expect(resolveTarget('layer-2-operations')).toMatchObject({ page: 'layer2', tab: 'adapters' })
  const main = read('src/mature-main.jsx')
  expect(main).not.toContain('UniversitiesCoverage')
  expect(main).not.toContain('Layer2Workspace')
  const ui = read('src/AdaptersWorkspace.jsx')
  // no threshold of its own: Qualify shares and the read-cycle bounds come from the database
  for (const bad of ['0.5', '0.9', '< 7', '> 365', '=== 90']) expect(ui).not.toContain(bad)
  expect(ui).toContain('settings.read_cycle_min')
  const at = read('src/AdminTasks.jsx')
  expect(at).not.toContain('data-task-start')
  expect(at).not.toContain("kind:'qualify_adapters'")
})

test('every card starts collapsed and is remembered for the browser session only', () => {
  const c = read('src/Card.jsx')
  expect(c).toContain('sessionStorage')
  expect(c).not.toContain('localStorage')
  expect(c).toContain('{open&&<div className="cf-card-body">')
  for (const f of ['src/ModelsServices.jsx', 'src/Toolsets.jsx', 'src/FirecrawlWork.jsx', 'src/AdaptersWorkspace.jsx']) expect(read(f)).toContain("import Card")
  expect(read('src/ModelsServices.jsx')).not.toContain('<section className="m-panel">\n      <SectionTitle')
})

test.describe('mocked browser', () => {
  test('Models & services: every card collapsed, one opens, and stays open after a reload in the same session', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#models-services')
    const toggles = page.locator('.cf-card-toggle')
    await toggles.first().waitFor()
    expect(await page.locator('.cf-card-toggle[aria-expanded="true"]').count()).toBe(0)
    await expect(page.locator('[data-model]')).toHaveCount(0) // a closed card draws no body
    await page.locator('[data-card="services.ai-models"] .cf-card-toggle').click()
    await expect(page.locator('[data-model="sonnet-english"]')).toBeVisible()
    await page.reload()
    await expect(page.locator('[data-card="services.ai-models"] .cf-card-toggle')).toHaveAttribute('aria-expanded', 'true')
    await expect(page.locator('[data-card="services.fetching"] .cf-card-toggle')).toHaveAttribute('aria-expanded', 'false')
  })

  test('Adapters: filters, one collapsed row per university, open a row, read schedule and switch consequences', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept('Checked in the browser test'))
    await page.goto('/#layer-2-discovery')
    const w = page.locator('[data-adapters-workspace]')
    await expect(w.locator('[data-adapters-tally]')).toContainText('3 shown of 4') // universities only by default
    await expect(w.locator('[data-adapter-detail]')).toHaveCount(0) // every row collapsed
    await w.getByRole('combobox', { name: 'Provider kind' }).selectOption('any')
    await expect(w.locator('[data-adapters-tally]')).toContainText('4 shown of 4')
    await w.getByRole('combobox', { name: 'Adapter state' }).selectOption('off')
    await expect(w.locator('[data-adapter-row]')).toHaveCount(1)
    await expect(w.locator('[data-adapter-row="u4"]')).toBeVisible()
    await w.getByRole('combobox', { name: 'Adapter state' }).selectOption('')
    await w.getByRole('combobox', { name: 'Latest Qualify' }).selectOption('waiting') // passed, not yet admitted
    await expect(w.locator('[data-adapter-row]')).toHaveCount(2)
    await w.getByRole('combobox', { name: 'Latest Qualify' }).selectOption('')
    // the switched-off adapter says what switching off does, and switching on says what that does
    const off = await openAdapter(page, 'u4', ['switch', 'schedule'])
    await expect(off.locator('[data-adapter-consequence]')).toContainText('not applied to pages read from now on')
    await expect(off.locator('[data-adapter-consequence]')).toContainText('Values it already admitted stay')
    await off.locator('[data-adapter-switch="on"]').click()
    await expect.poll(() => page.l3calls.find(c => c.adapters === 'set_on')?.args).toMatchObject({ provider_ids: ['u4'], on: true, reason: 'Checked in the browser test' })
    // schedule: default cycle from the database, own cycle shown, set through the RPC with bounds from the database
    const row = await openAdapter(page, 'u3') // the schedule block is already open: block state is remembered per kind for the session
    await expect(row.locator('[data-adapter-schedule="u3"]')).toContainText('30 days')
    await expect(row.locator('[data-adapter-schedule="u3"]')).toContainText('hash')
    await row.getByRole('button', { name: 'Set the read cycle' }).click()
    // the prompt was answered with a sentence, not a number: refused here, with the bounds the database gave
    await expect(w.locator('.dq-alert')).toContainText('The read cycle is 7 to 365 days')
    expect(page.l3calls.find(c => c.adapters === 'set_cycle')).toBeUndefined()
  })

  test('Adapters: tick rows, the bulk bar counts what each action will touch, Admit takes each adapter\'s own latest Qualify', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept('Bulk check in the browser test'))
    await page.goto('/#layer-2-discovery')
    const w = page.locator('[data-adapters-workspace]')
    await w.getByLabel('Tick every row shown').check()
    const bar = w.locator('[data-adapters-bulk]')
    await expect(bar).toContainText('3 ticked')
    await expect(bar).toContainText('2 with an adapter')
    await expect(bar).toContainText('2 switched on')
    await expect(bar).toContainText('2 with a passing field not yet admitted') // u1 delivery, u3 fee
  })

  test('Adapters: bulk Qualify and Admit are tasks; Admit sends provider_ids and never one Qualify job', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept('Bulk check in the browser test'))
    await page.goto('/#layer-2-discovery')
    const w = page.locator('[data-adapters-workspace]')
    await w.getByLabel('Tick Example University').check()
    await w.getByLabel('Tick Southern University').check()
    const bar = w.locator('[data-adapters-bulk]')
    await bar.getByRole('button', { name: /^Qualify 2/ }).click()
    await expect.poll(() => page.l3calls.find(c => c.jobs === 'start' && c.args.kind === 'qualify_adapters')?.args).toMatchObject({ kind: 'qualify_adapters', args: { provider_ids: ['u1', 'u3'], scope: 'adapters' } })
    await bar.getByRole('button', { name: /^Admit 2/ }).click() // u1 (delivery) and u3 (fee) each have a passing field not yet admitted
    await expect.poll(() => page.l3calls.find(c => c.jobs === 'start' && c.args.kind === 'admit_qualified')?.args).toMatchObject({ kind: 'admit_qualified', args: { provider_ids: ['u1', 'u3'], scope: 'adapters' } })
    expect(page.l3calls.find(c => c.jobs === 'start' && c.args.kind === 'admit_qualified').args.args.qualification_job_id).toBeUndefined()
    await bar.getByRole('button', { name: 'Switch off' }).click()
    await expect.poll(() => page.l3calls.find(c => c.adapters === 'set_on')?.args).toMatchObject({ provider_ids: ['u1', 'u3'], on: false })
  })

  test('Adapters: a row holds everything cascading from the adapter: central pages, fee range, hosted courses, Firecrawl target, history', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept('Target change from the browser test'))
    const row = await openAdapter(page, 'u1', ['central', 'fees', 'hosted', 'firecrawl', 'history'])
    await expect(row.locator('[data-central-attach="u1"]')).toBeVisible()
    await expect(row.locator('[data-fee-range="u1"]')).toBeVisible()
    await expect(row.locator('[data-hosted="u1"]')).toBeVisible()
    await expect(row.locator('[data-ad-block="firecrawl"]')).toContainText('In the targets')
    await row.getByRole('button', { name: 'Take out of the targets' }).click()
    await expect.poll(() => page.l3calls.find(c => c.firecrawl === 'target')?.args).toMatchObject({ provider_id: 'u1', included: false })
    await expect(row.locator('[data-adapter-history="u1"]')).toContainText('Qualify 124 adapter(s) in AU')
    await expect(row.locator('[data-adapter-history="u1"]')).toContainText('Admission changed')
  })

  test('retired addresses open Adapters, and Source profiles now sit on Scrapers & fetchers', async ({ page }) => {
    await mockAdmin(page)
    for (const url of ['/#layer-2-discovery?tab=operations', '/#layer-2-discovery?tab=start', '/#layer-2-discovery?tab=history', '/#coverage?tab=universities', '/#administration?section=layer2-sources']) {
      await page.goto(url)
      await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
    }
    await page.goto('/#scrapers')
    await expect(page.locator('[data-card="scrapers.source-profiles"]')).toBeVisible()
  })

  test('Adapters: opening a card does not read what is inside a closed one', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery')
    await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
    await expect(page.locator('[data-firecrawl-targets]')).toHaveCount(0) // closed: nothing drawn, nothing read
    await openCard(page, 'adapters.firecrawl-targets')
    await expect(page.locator('[data-firecrawl-targets]')).toContainText('The University of Sydney')
  })

  test('Adapters: the fee-rules dry run is read only and reads nothing until its card is opened', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery')
    await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
    await expect(page.locator('[data-fee-rules-report]')).toHaveCount(0)
    expect(page.l3calls.filter(c => c.feeRules).length).toBe(0)
    await openCard(page, 'adapters.fee-rules')
    await expect(page.locator('[data-fee-rules-report]')).toContainText('2,349')
    await expect(page.locator('[data-fee-rules-report]')).toContainText('nothing is written')
    await expect(page.locator('[data-fee-rules-report]')).toContainText('Alpha University')
    await expect(page.locator('[data-fee-suspected-half]')).toContainText('Beta College')
    expect(page.l3calls.filter(c => c.feeRules).length).toBeGreaterThan(0)
  })
})
