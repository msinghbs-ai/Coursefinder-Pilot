// Guards: CF-247 v2.15.248 (S14): Platform Admin bugs 11/10-5. "Manually ran 4 unis scholarship, job completed and scholarship didn't show up ...
// CF-247 v2.15.248 (S14): Platform Admin bugs 11/10-5. "Manually ran 4 unis scholarship, job completed and scholarship didn't show
// up ... the journey that platform admin should know what is happening and how long it's going to take ... not complete auditing."
// Every page a task finds and reads is recorded with the task (Feature 2) and shown as a journey per university, on the task and on
// the university's Coverage panel (Feature 1); Jobs rows name the universities (Fix 1); every page read keeps a copy (Fix 2);
// non-scholarship pages are skipped by address rules (Fix 3); listing pages are suggested (Fix 4); an automatically published
// scholarship that now fails a check is held (Fix 5).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('migration: item record, journey, evidence, skip rules, listing suggestions, auto-hold; nothing dropped', () => {
  const sql = read('supabase/migrations/20261011010200_cf247_scholarship_task_journey_evidence_skip_rules.sql')
  for (const s of ['create table if not exists pipeline.admin_job_items', 'create or replace function security.scholarship_job_items_sync_v1', 'create or replace function security.scholarship_job_journey_v1',
    'create or replace function public.admin_scholarship_job_journey', 'create or replace function public.admin_scholarship_provider_runs', 'create table if not exists pipeline.scholarship_skip_rules',
    "'scholarship_candidate_page'", "insert into pipeline.scholarship_listing_pages(provider_id,url,url_norm,source,active,status)", "'Failed a check after publishing: '", "like 'auto-publish%'",
    "perform security.scholarship_job_items_sync_v1(v_j.id);", "'provider_names'", 'task_title', "c.url ~* r.pattern and c.url !~* r.unless_pattern"]) expect(sql).toContain(s)
  for (const md5 of ['0080ad829614bf699f313e71db77417e', '70ae63d8f4600ba9e59abcb257c4ef5d', 'e6f873541c91a1dae6d5cddcd1b977b0', '90a14cb34e5383cdb265e7ec4c46a56e', '54edd7ac2ad149f0fefa5d92da88e22f', 'b5d89ce1e5b3b7c3de2398d5ef27289d']) expect(sql).toContain(md5)
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/^alter table .* drop /im)
})

test('worker v0.19.2 keeps a copy of every candidate page read, refused and too-thin pages too', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('if (pg.html && (pg.status === "read" || pg.status === "too_thin")) {')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(19\.[2-9]|[2-9]\d\.\d+)"/) // v0.19.2 or later
})

test('mocked browser: a university\'s Coverage panel tells the journey of its last run, with reasons and stored copies', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scholarships?tab=coverage')
  await page.locator('[data-cov-row="vu-1"]').click()
  const runs = page.locator('[data-provider-runs]')
  await expect(runs).toContainText('Find scholarships runs')
  await expect(runs.locator('.sj-sentence').first()).toContainText('2 new pages to check (1 refused, 1 skipped by a rule)')
  await expect(runs.locator('.sj-sentence').first()).toContainText('1 scholarship cannot be published yet')
  await runs.getByRole('button', { name: /Find scholarships now: 2 providers/ }).click()
  const j = runs.locator('[data-journey-provider="cdu"]')
  await expect(j.locator('[data-journey-publish]')).toContainText('Australia Award Scholarships')
  await expect(j.locator('[data-journey-publish]')).toContainText('not for international students')
  await expect(j.locator('[data-journey-item="refused"]')).toContainText('For domestic students only')
  await expect(j.locator('[data-journey-item="refused"] [data-journey-evidence]')).toHaveAttribute('href', '#evidence?evidence_id=ev-1')
  await expect(j.locator('[data-journey-item="skipped"]')).toContainText('Skipped: Course page')
})

test('mocked browser: Settings and jobs lists the skip rules with the pages each skipped', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scholarships?tab=coverage')
  await page.locator('[data-cov-row="vu-1"]').click()
  await page.locator('[data-scholarship-controls] > summary').click()
  await expect(page.locator('[data-skip-rules]')).toContainText('Course page')
  await expect(page.locator('[data-skip-rule="1"]')).toContainText('27')
})

test('mocked browser: a finished task in Jobs is named with its title and universities', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scheduled-jobs?tab=jobs')
  await expect(page.locator('[data-task-row-title]').first()).toContainText('Qualify 2 adapter(s) in AU-NSW')
  await expect(page.locator('[data-task-row-providers]').first()).toContainText('University of Technology Sydney, University of New England')
})

test('source: the Task manager shows the journey for scholarship tasks; Coverage shows the runs', () => {
  expect(read('src/AdminTasks.jsx')).toContain('<ScholarshipJourney jobId={job.id}/>')
  expect(read('src/ScholarshipCoverage.jsx')).toContain('<ProviderRuns providerId={providerId}/>')
  expect(read('src/ScholarshipJourney.jsx')).toContain("supabase.rpc('admin_scholarship_job_journey',{p_job:jobId})")
})
