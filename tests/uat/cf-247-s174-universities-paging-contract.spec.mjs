// Guards: CF-247 decision W33 (30 Oct 2026): Layer 2/3 › Universities reads one page at a time from admin_layer23('universities_page'), with its filters, search and order on the server and its page size a setting
// CF-247 S174, Workstream 3 (release health). The whole list was 2,421 rows and 1,967,164 bytes in one reply against the 700 KB screen budget
// (performance-deployed). The screen keeps what it offered: every filter, the name search, the order by name, the counts, Show more, Tick every
// row shown (every matching row, not only the rows read so far) and links that open one university. The budget itself is guarded by
// performance-deployed, unchanged; settings and housekeeping are guarded centrally (s32, s42), so they are not re-asserted here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = fs.readdirSync('supabase/migrations').find((f) => /^2026103\d{7}_cf247_universities_paging\.sql$/.test(f) || f === '20261030040000_cf247_universities_paging.sql')
const sql = fs.readFileSync(`supabase/migrations/${MIG}`, 'utf8')
const screen = fs.readFileSync('src/AdaptersWorkspace.jsx', 'utf8')

test('the server answers one page: an md5-guarded edit adds universities_page beside the two actions it keeps, with its size from a setting', () => {
  expect(sql).toContain("select pg_temp.edit_n('public.admin_layer23(text,jsonb)', 'aaf0e7d8438ffb863375c9617e619fea', array[")
  expect(sql).toContain("  if p_action = 'universities_page' then")
  expect(sql).toContain("v_size int := greatest(security.pipeline_num_v1('layer23.universities_page_size', 100)::int, 1);")
  expect(sql).toContain("v_tick_max int := greatest(security.pipeline_num_v1('layer23.universities_tick_max', 2000)::int, 1);")
  expect(sql).toMatch(/order by f\.name, f\.provider_id offset v_off limit v_size/)
  for (const k of ["'matched'", "'total'", "'tally'", "'countries'", "'states'", "'page_size'", "'ticks'"]) expect(sql).toContain(k)
  // the stage and the course-page counts are worked out for the rows of the page only
  expect(sql).toMatch(/'stage', security\.provider_onboarding_stage_v1\(ob\.status, ob\.stop_reason, ob\.result\)[\s\S]*from pg left join/)
  // the post-check refuses the change unless operations, universities and universities_page are all there
  expect(sql).toContain("raise exception 'W33 post-check: public.admin_layer23 does not hold operations, universities and universities_page'")
  for (const key of ['layer23.universities_page_size', 'layer23.universities_tick_max']) expect(sql).toMatch(new RegExp(`\\('pipeline', '${key.replace('.', '\\.')}', '[^']+',\\n`))
})

test('every choice the screen offers is a filter the server applies', () => {
  const values = (label) => [...screen.slice(screen.indexOf(`aria-label="${label}"`)).split('</select>')[0].matchAll(/<option value="([^"]+)"/g)].map((m) => m[1])
  for (const v of values('Adapter state')) expect(sql, `adapter ${v}`).toMatch(v === 'none' ? /v_adapter = 'none' and u\.adapter_state is null/ : /u\.adapter_state = v_adapter/)
  for (const v of values('Latest Qualify')) expect(sql, `qualify ${v}`).toMatch(v === 'failing' ? /v_qualify not in \('never', 'passing', 'waiting'\)/ : new RegExp(`v_qualify = '${v}'`))
  for (const v of values('Firecrawl target')) expect(sql, `target ${v}`).toMatch(/v_target = 'in' and coalesce\(u\.target_included, false\)\) or \(v_target <> 'in'/)
  const stages = [...screen.slice(screen.indexOf('const STAGE_FILTERS='), screen.indexOf('\n', screen.indexOf('const STAGE_FILTERS='))).matchAll(/\['(\w+)','[^']+'\]/g)].map((m) => m[1])
  expect(stages).toEqual(['working', 'person', 'stopped', 'inbox', 'done', 'none'])
  for (const v of stages) expect(sql, `stage ${v}`).toContain(`v_stage = '${v}'`)
  expect(sql).toContain("v_kind <> 'university' or u.university")
  expect(sql).toContain('strpos(lower(u.name), lower(v_q)) > 0')
  // the screen sends its filters and never reads the whole list, nor holds a page size of its own
  expect(screen).toContain("supabase.rpc('admin_layer23',{p_action:'universities_page',p_args:args})")
  expect(screen).not.toContain("p_action:'universities',")
  expect(screen).not.toContain("admin_adapters',{p_action:'list'")
  expect(screen).not.toMatch(/const PAGE\s*=/)
})

test('browser: one page is read, the counts come from the server, Show more reads the next page and filters are sent', async ({ page }) => {
  await mockAdmin(page, { universitiesPageSize: 2 })
  await page.goto('/#layer-2-discovery?tab=universities')
  const w = page.locator('[data-adapters-workspace]')
  await expect(w.locator('[data-adapters-tally]')).toContainText('3 shown of 4')
  await expect(w.locator('[data-adapter-row]')).toHaveCount(2)
  await expect(w.locator('[data-adapters-page-size]')).toHaveAttribute('data-adapters-page-size', '2')
  await w.locator('[data-adapters-more]').click()
  await expect(w.locator('[data-adapter-row]')).toHaveCount(3)
  await expect(w.locator('[data-adapters-more]')).toHaveCount(0)
  expect([...new Set(page.l3calls.filter((c) => c.layer23 === 'universities_page').map((c) => c.args.offset))]).toEqual([0, 2])
  await w.getByRole('combobox', { name: 'Provider kind' }).selectOption('any')
  await w.getByRole('combobox', { name: 'Adapter state' }).selectOption('testing')
  await expect(w.locator('[data-adapters-tally]')).toContainText('1 shown of 4 · admitting 0 · testing 1')
  await expect.poll(() => page.l3calls.filter((c) => c.layer23 === 'universities_page').at(-1)?.args).toMatchObject({ kind: 'any', adapter: 'testing', offset: 0 })
  await w.getByRole('combobox', { name: 'Adapter state' }).selectOption('')
  await w.getByRole('searchbox', { name: 'Find a university' }).fill('north')
  await expect(w.locator('[data-adapter-row]')).toHaveCount(1)
  await expect(w.locator('[data-adapter-row="u2"]')).toBeVisible()
  expect(page.l3calls.some((c) => c.layer23 === 'universities')).toBe(false)
})

test('browser: Tick every row shown ticks every matching row, also those not read yet, and the bulk bar counts them', async ({ page }) => {
  await mockAdmin(page, { universitiesPageSize: 2 })
  page.on('dialog', (d) => d.accept('Bulk check in the browser test'))
  await page.goto('/#layer-2-discovery?tab=universities')
  const w = page.locator('[data-adapters-workspace]')
  await expect(w.locator('[data-adapter-row]')).toHaveCount(2)
  await w.getByLabel('Tick every row shown').check()
  const bar = w.locator('[data-adapters-bulk]')
  await expect(bar).toContainText('3 ticked')
  await expect(bar).toContainText('2 with an adapter')
  await expect(bar).toContainText('2 with a passing field not yet admitted')
  expect(page.l3calls.find((c) => c.layer23 === 'universities_page' && c.args.mode === 'ticks').args).toMatchObject({ kind: 'university' })
  await bar.getByRole('button', { name: /^Qualify 2/ }).click()
  await expect.poll(() => page.l3calls.find((c) => c.jobs === 'start' && c.args.kind === 'qualify_adapters')?.args?.args?.provider_ids).toEqual(['u1', 'u3'])
  await w.getByLabel('Tick every row shown').uncheck()
  await expect(bar).toHaveCount(0)
})

test('browser: the most rows ticked at once is the server\'s, and a link with ?provider= opens that university found by its id', async ({ page }) => {
  await mockAdmin(page, { universitiesTickMax: 2 })
  await page.goto('/#layer-2-discovery?tab=universities')
  const w = page.locator('[data-adapters-workspace]')
  await w.getByLabel('Tick every row shown').check()
  await expect(w.locator('[data-adapters-bulk]')).toContainText('2 ticked')
  await expect(w.locator('[data-adapters-tick-capped]')).toContainText('Only the first 2 by name were ticked')
  await page.goto('/#layer-2-discovery?tab=universities&provider=u4')
  await expect(page.locator('[data-adapter-detail="u4"]')).toBeVisible()
  await expect(w.getByRole('searchbox', { name: 'Find a university' })).toHaveValue('Coastal Institute of Technology')
  expect(page.l3calls.some((c) => c.layer23 === 'universities_page' && c.args.provider_id === 'u4')).toBe(true)
})
