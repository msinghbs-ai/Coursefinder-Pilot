// Guards: UI audit Phase 5 first slice (Platform Admin 18 Nov 2026 09:30 "Phase 5 before Phase 4" and 10:09; decisions of 16 Nov 2026 05:12, admin docs/platform/ui-audit/ui-ux-settings-audit-2026-11-15.md §4.2): Layer 4 Review › Review grid with the shared views AER Audit Samples, Official URLs and Provider Blockers, personal views (owner only), shared views changed only by a Platform Admin with a reason, and the Source quote vs extracted value drawer; a view only filters what is shown (holds B and F: the AER audit sample and the Layer 4 URL rules are unchanged); decisions stay in the Inbox.
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/phase5-review-grid/run.sh (workflow phase5-review-grid-test); these checks keep the rules in the migration and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations/20261118120000_cf247_phase5_review_grid_saved_views.sql')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const screen = read('src/Layer4ReviewGrid.jsx')

test('the migration adds the saved views table and the grid function beside the Inbox, and drops, deletes or rewrites nothing', () => {
  expect(m).toMatch(/^-- Replaces: nothing/m); expect(m).toMatch(/^-- Retires: nothing$/m)
  for (const l of c.split('\n')) expect(l).not.toMatch(/^\s*(drop|delete|truncate|alter function|alter view)\b/i)
  expect(c).not.toMatch(/\bdelete from\b/i)
  expect(c).toContain('create table if not exists pipeline.saved_views (')
  expect(c).toContain('comment on table pipeline.saved_views is ')
  expect(c).toContain('alter table pipeline.saved_views enable row level security;')
  expect(c).toContain('revoke all on pipeline.saved_views from anon, authenticated;')
  // the Inbox's own functions are read, never replaced
  expect(c).not.toMatch(/create or replace function (public\.admin_layer4_inbox|security\.layer4_inbox_)/)
  expect(c).toContain('from security.layer4_inbox_items_v2(v_pid, v_one, null, v_det) i')
  // the only writes are views and their control events
  const fn = c.slice(c.indexOf('create or replace function public.admin_review_grid'), c.indexOf('revoke all on function public.admin_review_grid'))
  expect(fn.match(/insert into [a-z_.]+/g).sort()).toEqual(['insert into pipeline.admin_control_events', 'insert into pipeline.admin_control_events', 'insert into pipeline.saved_views'])
  expect(fn.match(/\bupdate [a-z_.]+/g).sort()).toEqual(['update pipeline.saved_views', 'update pipeline.saved_views'])
})

test('three shared views are seeded; only a Platform Admin changes a shared view, with a reason; personal views are the owner\'s alone', () => {
  for (const [k, n] of [['aer_audit_samples', 'AER Audit Samples'], ['official_urls', 'Official URLs'], ['provider_blockers', 'Provider Blockers']]) expect(c).toContain(`('shared', '${k}', '${n}',`)
  expect(c).toContain(`'{"kinds": ["aer_review"], "why_codes": ["audit_sample"]}'`)
  expect(c).toContain(`'{"kinds": ["course_link"], "field_codes": ["official_course_url"]}'`)
  expect(c).toContain("if v_rank < 3 then raise exception 'Curator (rank 3) or above is needed for the Review grid'")
  expect(c.match(/if v_v\.scope = 'shared' and v_rank < 6 then raise exception 'only a Platform Admin \(rank 6\) can change a shared view'/g).length).toBe(2)
  expect(c.match(/if v_v\.scope = 'shared' and v_reason is null then raise exception 'a reason is needed to change a shared view'/g).length).toBe(2)
  expect(c).toContain("(s.scope = 'shared' or s.owner_id = v_uid)")
  expect(c).toContain("check ((scope = 'shared' and owner_id is null and view_key is not null) or (scope = 'personal' and owner_id is not null))")
  expect(c).toContain('revoke all on function public.admin_review_grid(text, jsonb) from public, anon;')
})

test('G2: page sizes, drawer sizes and the personal view cap are settings read through pipeline_num_v1', () => {
  for (const k of ['layer4.grid_page_rows', 'layer4.grid_page_max', 'layer4.grid_drawer_pairs_max', 'layer4.grid_history_rows', 'layer4.saved_views_per_user']) {
    expect(c).toContain(`('pipeline', '${k}', `); expect(c).toContain(`security.pipeline_num_v1('${k}', `)
  }
  expect(c).not.toMatch(/\blimit \d{2,}/)
})

test('the screen: one entry point, the views bar, filters, the drawer and the Inbox link; tokens only', () => {
  expect(screen).toContain("supabase.rpc('admin_review_grid',{p_action:action,p_args:args||{}})")
  expect(screen.match(/supabase\.rpc\(/g).length).toBe(1)
  for (const k of ['data-review-grid', 'data-review-grid-help', 'data-review-grid-views', 'data-review-grid-filters', 'data-review-grid-save', 'data-review-grid-drawer', 'data-review-grid-pairs', 'data-review-grid-evidence', 'data-review-grid-history', 'data-review-grid-open-inbox']) expect(screen).toContain(k)
  expect(screen).not.toMatch(/'decide'|admin_layer4_inbox/)
  expect(read('src/layer4-review-grid.css')).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
  expect(read('src/nav-map.js')).toContain("{ key: 'grid', label: 'Review grid', min: 3 },")
  expect(read('src/mature-main.jsx')).toContain("case'layer4':return tab==='grid'?<Layer4ReviewGrid onError={err}/>:<Layer4Inbox onError={err} routeParams={routeParams}/>")
})

test('mocked browser: the shared views list first; a view filters the grid; the drawer shows the quote beside the value and opens the item in the Inbox', async ({ page }) => {
  await mockAdmin(page); const calls = page.l3calls
  await page.goto('/#layer-4-review?tab=grid')
  const g = page.locator('[data-review-grid]')
  await expect(g.locator('[data-review-grid-views] [role="tab"]')).toHaveText(['AER Audit Samplesshared', 'Official URLsshared', 'Provider Blockersshared', 'Everything waiting'])
  await expect(g.locator('[data-review-grid-total]')).toHaveText('60 items')
  await expect(g.locator('tbody tr[data-row]')).toHaveCount(50)
  await g.locator('[data-view-key="official_urls"]').click()
  await expect(g.locator('[data-review-grid-total]')).toHaveText('12 items')
  expect(calls.filter((x) => x.reviewGrid?.p_action === 'rows').at(-1).reviewGrid.p_args).toMatchObject({ view_id: 'v-url', offset: 0, filters: {} })
  await g.locator('[data-review-grid-filters] input[aria-label="Search"]').fill('Course 1')
  await expect.poll(() => calls.filter((x) => x.reviewGrid?.p_action === 'rows').at(-1).reviewGrid.p_args.filters).toEqual({ q: 'Course 1' })
  await g.locator('tbody tr[data-row]').first().click()
  const d = page.locator('[data-review-grid-drawer]')
  await expect(d.locator('[data-review-grid-pairs] blockquote')).toHaveText('“Entry score: ATAR 83.70”')
  await expect(d.locator('[data-review-grid-pairs] [role="row"]').nth(1)).toContainText('ATAR 83.70')
  await expect(d.locator('[data-review-grid-evidence] a')).toHaveAttribute('href', 'https://one.example/c1')
  await expect(d.locator('[data-review-grid-history] li')).toContainText('Rule aer-machine-v1')
  const href = await d.locator('[data-review-grid-open-inbox]').getAttribute('href')
  expect(href).toMatch(/^#layer-4-review\?kind=aer_review&provider=p-1&ref=00000000-0000-4000-8000-\d{12}&review_at=/)
  await page.keyboard.press('Escape'); await expect(d).toHaveCount(0)
  await g.locator('[data-review-grid-save]').click()
  await g.locator('[data-review-grid-save-form] input[aria-label="View name"]').fill('My course links')
  await g.locator('[data-review-grid-save-form] button[type="submit"]').click()
  expect(calls.filter((x) => x.reviewGrid?.p_action === 'view_save').at(-1).reviewGrid.p_args).toMatchObject({ name: 'My course links', filters: { kinds: ['course_link'], field_codes: ['official_course_url'], q: 'Course 1' } })
})
