// Guards: CF-247 v2.15.246 (S12): Platform Admin bugs 11/10-3. A register run is one row in Jobs with its batches and evidence (Fix 1);
// CF-247 v2.15.246 (S12): Platform Admin bugs 11/10-3. A register run is one row in Jobs with its batches and evidence (Fix 1);
// a register whose file changes on every read but yields no change is not rerun every few hours (Fix 2); the Task manager shows
// everything using resources now and in the last 15 minutes, and never hides an error (Fix 3); the Automations read is fast
// (Fix 4); retired scholarship registers stop (Fix 5); an unhealthy source says why (Fix 6); Reference sources and Layer 1 › Sources
// are one list pattern with expandable rows (Fix 7, Feature 2); Manual batch runs is retired.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, resolveTarget } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')
const noDrops = sql => { expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im); expect(sql).not.toMatch(/^alter table .* drop /im) }

test('migrations: task board, jobs per run, noisy-register rule, retired registers, fast Automations, add source', () => {
  const a = read('supabase/migrations/20261011009800_cf247_task_board_jobs_runs_register_reruns.sql')
  for (const s of ['layer1_auto_ingest_tick_v1()', "'recent_jobs'", "'recent_calls'", "'credits_15m'", "'ai_15m'", "'queues'", "'uncatalogued'", 'create or replace function security.layer1_run_for_job_v1', "'run', security.layer1_run_for_job_v1(v_id)"]) expect(a).toContain(s)
  for (const id of ['17a7d379-9448-41ca-bca5-bb7537ffff4b', 'a9443687-678b-436f-9c16-62fcb800af14', '717432c7-32f9-47c3-9111-7f75fd79c128']) expect(a).toContain(id)
  noDrops(a)
  expect(read('supabase/migrations/20261011009900_cf247_automations_read_last_once.sql')).toContain('last as materialized')
  const c = read('supabase/migrations/20261011010000_cf247_layer1_add_source.sql')
  expect(c).toContain('create or replace function public.admin_layer1_add_source(p_args jsonb)')
  expect(c).toContain("security.current_role_rank() < 6")
  expect(c).toContain("'needs_reader', true")
  noDrops(c)
})

test('navigation: Layer 1 is one Sources page (v2.15.301); old Runs, Source settings and Manual batch runs addresses open it', () => {
  expect(PAGES.layer1.tabs).toBeUndefined()
  expect(PAGES.layer1.min).toBe(4)
  for (const tab of ['settings', 'batch', 'operations']) expect(resolveTarget('layer-1-register', new URLSearchParams({ tab }))).toMatchObject({ page: 'layer1', tab: '' })
  expect(resolveTarget('regulatory-settings')).toMatchObject({ page: 'layer1', tab: '' })
  expect(resolveTarget('layer-1-register', new URLSearchParams({ tab: 'scholarships' }))).toMatchObject({ page: 'layer2', tab: 'scholarships' })
  expect(read('src/mature-main.jsx')).toContain("{layer==='all'?<SourcesWorkspace/>:<Layer1Sources/>}")
})

test('mocked browser: Layer 1 › Sources is a list; a failing source says why; a row opens to edit; + Add source', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.accept('Testing the list'))
  await page.goto('/#layer-1-register')
  const l = page.locator('[data-l1-sources]')
  await expect(l.locator('[data-l1-source]')).toHaveCount(2) // the retired register is hidden
  await expect(l.locator('[data-l1-source]').first()).toContainText('Centennial') // needs attention sorts first
  await l.getByRole('button', { name: 'Open Centennial College Program Catalogue API' }).click()
  await expect(l.locator('[data-l1-health-reason]')).toContainText('expected 195 unique source codes got 200')
  const f = l.locator('[data-l1-source-form]')
  await f.getByLabel('Load every (days)').fill('14')
  await f.getByLabel('Reason for the change (kept in the log)').fill('Weekly is too often')
  await f.getByRole('button', { name: 'Save changes' }).click()
  await expect.poll(() => page.l3calls.find(c => c.l1Command?.p_operation === 'save_source')?.l1Command.p_args).toMatchObject({ source_id: 'l1-centennial', ingestion_cadence_days: 14, reason: 'Weekly is too often' })
  await l.getByLabel('Show retired').check()
  await expect(l.locator('[data-l1-source]')).toHaveCount(3)
  await l.getByRole('button', { name: 'Add source' }).click()
  const a = page.locator('[data-l1-add-source]')
  await a.getByLabel('Country code (for example AU, NZ, CA)').fill('ca')
  await a.getByLabel('Name').fill('Ontario Colleges register')
  await a.getByLabel('Source address (https)').fill('https://www.ontariocolleges.ca/')
  await a.getByLabel('Authority that publishes it').fill('Ontario Colleges')
  await a.getByRole('button', { name: 'Add source' }).click()
  await expect.poll(() => page.l3calls.find(c => c.l1Add)?.l1Add).toMatchObject({ country_code: 'CA', label: 'Ontario Colleges register', url: 'https://www.ontariocolleges.ca/', ingestion_cadence_days: 30 })
  await expect(l).toContainText('Ontario Colleges register added')
})

test('mocked browser: Task manager links to Progress › Running now (v2.15.266; its own Running now board is retired)', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scheduled-jobs?tab=tasks')
  await expect(page.locator('[data-task-running-link] a')).toHaveAttribute('href', '#layer-2-discovery') // v2.15.301: Progress › Running now retired; this is the board
  await expect(page.locator('[data-running-now]')).toHaveCount(0)
})

test('source: the Task manager shows an error instead of loading for ever; Jobs folds a register run and opens it', () => {
  const t = read('src/AdminTasks.jsx')
  expect(t).toContain('The task manager could not be read: {err}')
  const j = read('src/pipeline-ops-entry.jsx')
  expect(j).toContain('if(data.run)return <RunDetail run={data.run} job={data.job}/>')
  expect(j).toContain('href={`#evidence?evidence_id=${e.id}`}')
  expect(j).toContain('data-register-run={row.run_id}')
  expect(read('src/Automations.jsx')).toContain('Not catalogued: no label or owner')
})
