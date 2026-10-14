// CF-247 v2.15.273 (S36): Platform Admin, 14 Oct 2026 10:41: "create a job to enrich data for specific or multiple fields across uni or
// countries using scraper and ai in layer 2 and layer 3. Keep it simple"; decisions: build the full job first, campus lists admitted when
// the AI list and the course pages agree, international by the institution rule.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = f => fs.readFileSync(f, 'utf8')
const mig = read('supabase/migrations/20261014013500_cf247_enrich_fields_job.sql')
const fix = read('supabase/migrations/20261014013600_cf247_enrich_fields_fix_ai_next.sql')
const batch = read('supabase/migrations/20261014013700_cf247_enrich_fields_ai_batching.sql')
const worker = read('supabase/functions/coverage-sweep/index.ts')

test('the job: field sources by country, one item per course and field, only missing values, never a hand-set value', () => {
  expect(mig).toContain('create table if not exists pipeline.field_source_rules (')
  expect(mig).toContain("('ALL', 'international', array['institution_rule', 'adapter', 'ai_stored']")
  expect(mig).toContain('unique nulls not distinct (job_id, provider_id, course_id, field)')
  expect(mig).toContain("values ('enrich_fields', 'Enrich fields',")
  expect(mig).toContain("if v_j.kind = 'enrich_fields' then return security.enrich_fields_slice_v1(p_id, p_items); end if;")
  // only missing values; hand locks respected
  expect(mig).toContain('where id = i.course_id and duration_value is null;')
  expect(mig).toContain("v_lock := exists (select 1 from pipeline.manual_locks l")
  // scraper only when the task allows it; AI within its daily guard
  expect(mig).toContain("continue when v_src = 'scraper' and not v_scr;")
  expect(mig).toContain("if not security.ai_use_allowed_v1('enrich_fields') then return 0; end if;")
  expect(mig).toContain("('enrich_fields', 'Enrich fields with AI', 5)")
  // campus lists: admitted when the course pages agree (a setting)
  expect(mig).toContain("security.pipeline_num_v1('enrich.campus_min_pages', 2)")
  // international: the IRCC list for Canada
  expect(mig).toContain("it.cc = 'CA' and exists (select 1 from catalogue.provider_identifiers i where i.provider_id = it.provider_id and i.scheme = 'ircc_dli')")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(fix).toContain("select jsonb_agg(g.x) from (")
  expect(batch).toContain("security.pipeline_num_v1('enrich.ai_items_per_call', 30)")
})

test('worker v0.22.0: every AI value must quote the stored page; the scraper reads a home page only when allowed and keeps a copy', () => {
  expect(worker).toContain('if (mode === "enrich_ai") {')
  expect(worker).toMatch(/const proven = val != null && on\(page, q\) && strong( && !feeLine)?;/)  // v0.23.2 adds the fee-line rule for duration
  expect(worker).toContain('if (!(await useFc("enrich_address", p.provider_id, p.website, true)))')
  expect(worker).toContain('const up = await c.storage.from("evidence").upload(path, await gzip(text)')
  expect(worker).toContain('if (d?.model && !String(d.model).startsWith(model))')
  // v0.22.1: stored copies read whether gzip or plain; v0.22.2: international needs a quote about the course's students or fees (not a site footer)
  expect(worker).toContain('if (buf[0] === 0x1f && buf[1] === 0x8b)')
  expect(worker).toContain('"only a site-wide line mentions international"')
})

test('screen: Layer 2 › Enrich fields', () => {
  expect(read('src/nav-map.js')).toContain("{ key: 'enrich', label: 'Enrich fields', min: 3 }")
  expect(read('src/mature-main.jsx')).toContain("if(tab==='enrich')return <EnrichFields rank={rank} onError={err}/>")
})

test.describe('mocked browser', () => {
  test('preview what is missing, start a task with a reason, change a field source', async ({ page }) => {
    await mockAdmin(page)
    const calls = []
    const fields = [{ field: 'campus', label: 'Campus (with the campus list)', allowed: ['adapter', 'ai_stored'] }, { field: 'duration', label: 'Duration', allowed: ['adapter', 'ai_stored'] }]
    const meta = { fields, countries: ['AU', 'CA', 'NZ'], can_start: true, can_manage: true, rules: [{ country: 'ALL', field: 'campus', sources: ['adapter', 'ai_stored'] }, { country: 'ALL', field: 'duration', sources: ['adapter', 'ai_stored'] }] }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_enrich_fields', async route => {
      const b = route.request().postDataJSON() || {}
      calls.push(b)
      const r = b.p_action === 'fields' ? meta : b.p_action === 'jobs' ? { jobs: [] } : b.p_action === 'preview' ? { courses: 6474, universities: 287, fields: [{ field: 'duration', missing: 6474, stored_page: 5543, adapter_value: 1174 }] }
        : b.p_action === 'start' ? { job_id: 'j1', items: 6474 } : b.p_action === 'rule_set' ? meta : {}
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r) })
    })
    await page.goto('/#layer-2-discovery?tab=enrich')
    const start = page.locator('[data-enrich-start]')
    await start.locator('.cf-card-toggle').click()
    await start.getByLabel('New Zealand').check()
    await start.locator('[data-enrich-field="duration"] input').check()
    await start.getByRole('button', { name: 'Preview' }).click()
    await expect(start.locator('[data-preview-field="duration"]')).toContainText('1,174')
    await start.getByPlaceholder('Reason (kept with the task)').fill('Fill NZ durations from stored pages')
    await start.getByRole('button', { name: 'Start task' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'start')?.p_args).toEqual({ countries: ['NZ'], provider_ids: [], fields: ['duration'], ai: true, scraper: false, reason: 'Fill NZ durations from stored pages' })
    await expect(start.getByRole('status')).toContainText('6,474 item(s) to settle')
    const src = page.locator('[data-field-sources]')
    await src.locator('.cf-card-toggle').click()
    await src.locator('[data-source-rule="duration"]').getByRole('button', { name: 'Change' }).click()
    await src.getByRole('button', { name: 'Move AI reads the stored page up' }).click()
    await src.getByLabel('Reason').fill('Stored page first for duration')
    await src.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'rule_set')?.p_args).toEqual({ country: 'ALL', field: 'duration', sources: ['ai_stored', 'adapter'], reason: 'Stored page first for duration' })
  })
})
