// Guards: Platform Admin directive 10 Nov 2026 (CF-247 F-CDESC.06): Fill description / Recheck description on demand from the Course Catalogue, Course Detail and Provider Catalogue
// through the EXISTING Enrich fields task: bounded, previewed, with a reason, idempotent; Missing / Source-ready / AI-read / Held / Machine-admitted / Human decision shown as distinct
// states; Website feed, Zoho feed and Verified HTTP kept apart (not applicable is not a failure, not checked is not a pass). Database behaviour: tests/fixtures/cdesc-on-demand/run.sh
// (isolated PostgreSQL). This spec holds the source contracts and the screens on the mocked admin.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockOnDemand, ORDER } from './support/cdesc-on-demand-mock.mjs'

const MIG = fs.readFileSync('supabase/migrations/20261110070000_cf247_cdesc_on_demand.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const REC = fs.readFileSync('supabase/held/cdesc_on_demand_forward_recovery.sql', 'utf8')
const UI = fs.readFileSync('src/CourseDescriptionOnDemand.jsx', 'utf8')
const MAIN = fs.readFileSync('src/mature-main.jsx', 'utf8')
const COURSE = '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'
const RPC = 'https://example.supabase.co/rest/v1/rpc/'

test('migration: one md5-guarded edit of public.admin_enrich_fields, new functions beside it, no new setting, table, job kind or consumer-API change', () => {
  expect(MIG).toMatch(/^-- Replaces: nothing/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain('c9701d334b732a729a30a5147d9d016b') // the live body this edit starts from (read 10 Nov 2026)
  expect(MIG).toContain('f11db4466add68c4d7de5cb7c87d9bce') // the body it ends with
  expect(MIG).toMatch(/already applied/)
  // no new operational value or setting: the bounds are the existing settings
  expect(code).not.toMatch(/insert into pipeline\.platform_toolset_settings/i)
  expect(code).not.toMatch(/update pipeline\.platform_toolset_settings[^;]*\b(value|min_value|max_value)\b/i)
  expect(code).toContain("security.pipeline_num_v1('run_now.pilot_cap', 20)")
  expect(code).toContain("security.pipeline_num_v1('enrich.course_text_items_per_day', 500)")
  // no new table, job kind, scheduler or reader; the task is the existing Enrich fields task
  expect(code).not.toMatch(/create\s+table\s/i)
  expect(code).not.toMatch(/admin_job_kinds|automation_catalogue/)
  expect(code).toMatch(/values \('enrich_fields', 'enrich', 'queued'/)
  // nothing dropped or deleted; no write to the catalogue or to the standing queue's own state
  expect(code).not.toMatch(/\b(drop\s+(table|function|view|schema)|delete\s+from|truncate\s+(?!pg_temp))/i)
  expect(code).not.toMatch(/\b(update|insert into)\s+catalogue\./i)
  expect(code).not.toMatch(/\b(update|insert into)\s+pipeline\.(manual_locks|layer4_review_items|layer4_decisions|coverage_course_pages)\b/i)
  // the locks, rejection memory, hidden providers and identity rule are read, never bypassed
  expect(code).toContain('security.coverage_identity_allowed')
  expect(code).toContain('security.provider_hidden_v1')
  expect(code).toContain('pipeline.manual_locks')
  expect(code).toContain("l4.rejected_ev")
  // the consumer API is read (the verify action), never changed (G3)
  expect(code).not.toMatch(/create\s+(or\s+replace\s+)?function\s+(public\.(website_v2_|website_edge_|website_api_v2_|zoho_edge_)|api\.|public\.svc_website_settings_v1)/i)
  expect(code).toContain('public.website_v2_course(r.sk)')
  // the machine-admission ledger is read in the shape agent D1's migration 20261110060000 defines: only a live admission counts, and nothing hides a wrong shape
  const ledger = code.slice(code.indexOf('function security.cdesc_machine_ids_v1'), code.indexOf('$function$;', code.indexOf('function security.cdesc_machine_ids_v1')))
  expect(ledger).toContain("m.outcome = ''admitted'' and m.withdrawn_at is null")
  expect(ledger).toMatch(/a\.attname in \('course_id', 'outcome', 'withdrawn_at'\)/)
  expect(ledger).not.toMatch(/exception\s+when\s+others/i)
  // two requests cannot queue the same course: locks are taken before the courses are chosen, in a fixed order; verify is bounded
  expect(code.indexOf('pg_advisory_xact_lock(hashtextextended(\'cdesc_course:\'')).toBeGreaterThan(-1)
  expect(code.indexOf('pg_advisory_xact_lock_shared')).toBeGreaterThan(-1)
  expect(code.indexOf('cdesc_course:')).toBeLessThan(code.indexOf('create temporary table if not exists pg_temp.cdesc_sel'))
  expect(code).toMatch(/v_vmax constant int := 10; -- fixed: /)
  expect(code).toMatch(/left\(sqlerrm, 160\); -- fixed: /)
  expect(code).toContain('least(v_max, v_room)')
  expect(code).toContain('enrich.course_description_pending_global_max')
  expect(code).toContain('this idempotency key was already used for a different request')
  // the recovery file restores the recorded body and is guarded
  expect(REC).toContain('f11db4466add68c4d7de5cb7c87d9bce')
  expect(REC).toContain('c9701d334b732a729a30a5147d9d016b')
  expect(REC).toMatch(/already restored/)
})

test('screens call only the existing Enrich fields engine and the read-only state; nothing in the file is an operating number', () => {
  const rpcs = [...UI.matchAll(/supabase\.rpc\('([a-z_0-9]+)'/g)].map((m) => m[1]).sort()
  expect([...new Set(rpcs)]).toEqual(['admin_course_description_state_v1', 'admin_enrich_fields'])
  expect(UI).not.toMatch(/admin_jobs|description_run|provider_description|from\('catalogue|\.from\(/)
  expect(UI).toMatch(/\['preview'|call\('preview'/)
  expect(UI).toContain("call('start'")
  expect(UI).toContain('idempotency_key')
  // the shared screens are touched in a few places only
  expect(MAIN).toContain("from'./CourseDescriptionOnDemand'")
  expect(MAIN).toContain('cdod.decorate(cols0)')
  expect(MAIN).toContain('<CourseDescriptionBlock courseId={data.id}')
  expect(MAIN).toContain('<ProviderDescriptionFill providerId={data.id}')
})

test.describe('mocked browser', () => {
  test('Course Catalogue: states are distinct; ticking does not open the course; Recheck previews who is in and out and why, asks for a reason, queues once', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const calls = await mockOnDemand(page)
    await page.goto('/#courses')
    const states = page.locator('[data-desc-state]')
    await expect(states.first()).toBeVisible()
    const seen = await states.evaluateAll((els) => els.map((e) => e.getAttribute('data-desc-state')))
    expect(seen.slice(0, 2)).toEqual(ORDER.slice(0, 2)) // Source-ready, Missing
    expect(new Set(seen).size).toBe(seen.length) // each shown state is its own
    await expect(page.locator('[data-cdod-bar]')).toContainText('Tick courses')
    const boxes = page.locator('.cdod-pick input[type="checkbox"]')
    await boxes.nth(0).check(); await boxes.nth(1).check()
    await expect(page.locator('.m-drawer-course')).toHaveCount(0) // ticking never opens the course
    await expect(page.locator('[data-cdod-bar]')).toContainText('2 selected')
    await page.getByRole('button', { name: 'Recheck description' }).click()
    const panel = page.locator('[data-cdod-panel="recheck"]')
    await expect(panel).toContainText('will be queued')
    // course 1 is source-ready but never tried: nothing to recheck; course 2 has no source
    await expect(panel.locator('[data-cdod-block="nothing_to_recheck"]')).toContainText('Not tried yet')
    await expect(panel.locator('[data-cdod-block="no_source"]')).toContainText('No stored course page')
    expect(calls.find((c) => c.name === 'preview')).toMatchObject({ mode: 'recheck', course_ids: expect.any(Array) })
    // nothing can be queued here: the button says so and stays disabled even with a reason
    await panel.getByLabel('Reason').fill('Pages were re-read')
    await expect(panel.getByRole('button', { name: /^Queue 0 courses/ })).toBeDisabled()
    await panel.getByRole('button', { name: 'Cancel' }).click()
    // Fill: course 1 is eligible
    await page.getByRole('button', { name: 'Fill description' }).click()
    const fill = page.locator('[data-cdod-panel="fill"]')
    await expect(fill.locator('[data-cdod-course][data-will-queue="yes"]')).toHaveCount(1)
    await expect(fill.locator('[data-cdod-course][data-will-queue="no"]')).toContainText('No stored course page')
    await expect(fill.locator('[data-cdod-estimate]')).toContainText('US$0.0031')
    await expect(fill.locator('[data-cdod-estimate]')).toContainText('No scraper credits')
    const go = fill.getByRole('button', { name: /^Queue 1 course/ })
    await expect(go).toBeDisabled() // a reason is needed
    await fill.getByLabel('Reason').fill('New pages stored')
    await go.click()
    await expect(fill.locator('[data-cdod-done]')).toContainText('abcdef12')
    const starts = calls.filter((c) => c.name === 'start')
    expect(starts).toHaveLength(1)
    expect(starts[0]).toMatchObject({ mode: 'fill', reason: 'New pages stored', idempotency_key: expect.stringMatching(/^cdod:/) })
    expect(starts[0].course_ids).toHaveLength(2)
    // the saved task list is read from the server
    await page.locator('.cdod-tasks-fold > summary').first().click()
    await expect(page.locator('[data-cdod-tasks]')).toContainText('Recheck description · 2 course(s)')
    expect(calls.some((c) => c.name === 'description_tasks')).toBe(true)
  })

  test('Course Catalogue: a changed selection is a new request: the earlier result is cleared and the next Queue uses a new key', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const calls = await mockOnDemand(page)
    await page.goto('/#courses')
    const boxes = page.locator('.cdod-pick input[type="checkbox"]')
    await boxes.nth(0).check()
    await page.getByRole('button', { name: 'Fill description' }).click()
    const panel = page.locator('[data-cdod-panel="fill"]')
    await panel.getByLabel('Reason').fill('First request')
    await panel.getByRole('button', { name: /^Queue 1 course/ }).click()
    await expect(panel.locator('[data-cdod-done]')).toBeVisible()
    await boxes.nth(1).check() // another course joins the selection while the panel is open
    await expect(panel.locator('[data-cdod-done]')).toHaveCount(0)
    await panel.getByLabel('Reason').fill('Second request')
    await panel.getByRole('button', { name: /^Queue \d+ course/ }).click()
    await expect(panel.locator('[data-cdod-done]')).toBeVisible()
    const starts = calls.filter((c) => c.name === 'start')
    expect(starts).toHaveLength(2)
    expect(starts[0].idempotency_key).not.toBe(starts[1].idempotency_key)
  })

  test('Course Catalogue: a Curator can preview but not start; a lower role sees no Fill or Recheck at all', async ({ page }) => {
    await mockAdmin(page, { rank: 3 })
    await mockOnDemand(page)
    await page.goto('/#courses')
    await page.locator('.cdod-pick input').first().check()
    await page.getByRole('button', { name: 'Fill description' }).click()
    const panel = page.locator('[data-cdod-panel="fill"]')
    await expect(panel).toContainText('Starting needs the Pipeline Operator role')
    await expect(panel.getByRole('button', { name: /^Queue/ })).toBeDisabled()
    const p2 = await page.context().newPage()
    await mockAdmin(p2, { rank: 2 }); await mockOnDemand(p2)
    await p2.goto('/#courses')
    await expect(p2.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
    await expect(p2.locator('[data-cdod-bar]')).toHaveCount(0)
    await expect(p2.locator('[data-desc-state]')).toHaveCount(0)
  })

  test('Course Catalogue: a refused start is shown plainly and nothing is reported as queued', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    await mockOnDemand(page, { startError: 'nothing to queue: Tried recently (1)' })
    await page.goto('/#courses')
    await page.locator('.cdod-pick input').first().check()
    await page.getByRole('button', { name: 'Fill description' }).click()
    const panel = page.locator('[data-cdod-panel="fill"]')
    await panel.getByLabel('Reason').fill('Try it')
    await panel.getByRole('button', { name: /^Queue 1 course/ }).click()
    await expect(panel.getByRole('alert')).toContainText('nothing to queue')
    await expect(panel.locator('[data-cdod-done]')).toHaveCount(0)
  })

  test('Course Detail: state, source, evidence, last attempt, next retry and gain; a blocked action says why; the feeds are read back as three separate states', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const calls = await mockOnDemand(page)
    await page.goto(`/#courses?id=${COURSE}`)
    const block = page.locator('[data-cdod-block]')
    await expect(block).toBeVisible()
    await expect(block.locator('[data-desc-state="source_ready"]')).toContainText('Source-ready')
    await expect(block).toContainText('Source page')
    await expect(block).toContainText('Evidence')
    await expect(block).toContainText('Never tried')
    await expect(block).toContainText('No description yet.')
    await expect(block.getByRole('button', { name: 'Fill description' })).toBeEnabled()
    await expect(block.getByRole('button', { name: 'Recheck description' })).toBeDisabled()
    await expect(block.locator('[data-cdod-why]')).toContainText('Not tried yet')
    await block.getByRole('button', { name: 'Check the feeds' }).click()
    const feeds = block.locator('[data-cdod-feeds]')
    await expect(feeds.locator('[data-feed-state="matched"]')).toContainText('Same words')
    await expect(feeds.locator('[data-feed-state="not_applicable"]')).toContainText('Not applicable')
    await expect(feeds.locator('[data-feed-state="not_checked"]')).toContainText('Not checked')
    expect(calls.find((c) => c.name === 'verify')).toMatchObject({ course_ids: [COURSE] })
    await block.getByRole('button', { name: 'Fill description' }).click()
    await block.getByLabel('Reason').fill('One course')
    await block.getByRole('button', { name: /^Queue 1 course/ }).click()
    await expect(block.locator('[data-cdod-done]')).toBeVisible()
    expect(calls.filter((c) => c.name === 'start')[0].course_ids).toEqual([COURSE])
  })

  test('Provider Catalogue: Fill course descriptions previews the university and starts it through provider_ids', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const calls = await mockOnDemand(page)
    await page.route(RPC + 'admin_read', async (route) => {
      const b = route.request().postDataJSON() || {}
      if (b.p_operation === 'providers_page') return route.fulfill({ json: { total: 1, items: [{ id: 'p-uwa', canonical_name: 'The University of Western Australia', country_code: 'AU', course_count: 330, lifecycle_status: 'active', publication_status: 'published' }] } })
      if (b.p_operation === 'provider_detail') return route.fulfill({ json: { id: 'p-uwa', canonical_name: 'The University of Western Australia', display_name: 'The University of Western Australia', country_code: 'AU' } })
      return route.fallback()
    })
    await page.goto('/#providers')
    await page.getByText('The University of Western Australia').first().click()
    const blk = page.locator('[data-cdod-provider]')
    await expect(blk).toBeVisible()
    await blk.getByRole('button', { name: 'Fill course descriptions' }).click()
    const panel = blk.locator('[data-cdod-panel="fill"]')
    await expect(panel).toContainText('will be queued')
    expect(calls.find((c) => c.name === 'preview')).toMatchObject({ mode: 'fill', provider_ids: ['p-uwa'] })
    await panel.getByLabel('Reason').fill('Whole university')
    await panel.getByRole('button', { name: /^Queue/ }).click()
    await expect(panel.locator('[data-cdod-done]')).toBeVisible()
    expect(calls.find((c) => c.name === 'start')).toMatchObject({ mode: 'fill', provider_ids: ['p-uwa'], reason: 'Whole university' })
  })
})
