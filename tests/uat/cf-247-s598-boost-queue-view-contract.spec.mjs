// Guards: Platform Admin decision 18 Nov 2026 07:03 (Boost priority score and Country tier): the two values are worked out when the Boost queue is read, from the boost.matrix settings through S2 - BOOST's own weight function, and are shown, filtered and sorted only on the Boost queue (Platform health › Queues & yield); no column is added to a course and the Course catalogue does not carry them.
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/admin-boost-queue/run.sh (workflow admin-boost-queue-test); these checks keep the rules in the migration and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { COURSE_COLUMNS } from '../../src/catalogue-columns.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations/20261118080000_cf247_admin_boost_queue_read.sql')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const screen = read('src/BoostQueue.jsx')

test('nothing is stored: the migration adds one read-only function and one setting, and no column anywhere', () => {
  expect(m).toMatch(/^-- Replaces: nothing$/m); expect(m).toMatch(/^-- Retires: nothing$/m)
  for (const l of m.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate|update|alter)\b/i)
  expect(c).not.toMatch(/\badd column\b|\bcreate table\b|\bcreate index\b/i)
  expect(c.match(/create or replace function /g).length).toBe(1)
  expect(c).toContain("create or replace function public.admin_boost_queue_read(p_args jsonb default '{}'::jsonb) returns jsonb\nlanguage plpgsql stable security definer set search_path = ''")
  const body = c.slice(c.indexOf('create or replace function public.admin_boost_queue_read'), c.indexOf('comment on function public.admin_boost_queue_read'))
  expect(body).not.toMatch(/\b(insert into|update |delete from)\b/i)
  expect(c.match(/insert into /g).length).toBe(1); expect(c).toContain("('pipeline', 'admin.boost_queue_page_rows', 'Boost queue: rows per page',")
  expect(c).toContain("if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for the Boost queue'")
  expect(c).toContain('revoke all on function public.admin_boost_queue_read(jsonb) from public, anon;')
})

test('the score and tier come from the live boost.matrix settings through one definition, worked out once per lane and country', () => {
  expect(c).toContain('security.boost_country_category_weight_v1(c.country_code, k.category) priority_score,')
  expect(c).toContain("v_t1 text[] := security.pipeline_list_v1('boost.matrix.tier_1'); v_t2 text[] := security.pipeline_list_v1('boost.matrix.tier_2');")
  expect(c).toContain('case when k.canon = any(v_t1) then 1 when k.canon = any(v_t2) then 2 end country_tier')
  expect(c).toContain('from (select distinct e.lane, e.country_code from pipeline.boost_extract_items e) c')
  // G2: no weight, tier list or page size is written into the function
  expect(c).not.toMatch(/'(AU|NZ|CA|UK|IE|US)'/); expect(c).toContain("security.pipeline_num_v1('admin.boost_queue_page_rows', 50)"); expect(c).not.toMatch(/limit (?!1\b)\d/)
})

test('only the Boost queue shows them: the Course catalogue has no tier or score column or filter', () => {
  expect(COURSE_COLUMNS.map((x) => x.key).filter((k) => /tier|priority|boost/.test(k))).toEqual([])
  const main = read('src/mature-main.jsx')
  expect(main).not.toMatch(/country_tier|priority_score/)
  expect(main).toContain('<QueueWatch onError={onError}/><BoostQueue onError={onError}/></div>')
  expect(screen).toContain("rpc('admin_boost_queue_read',{p_args:f})")
  for (const k of ['data-boost-queue', 'data-bq-tier', 'data-bq-country', 'data-bq-lane', 'data-bq-state', 'data-bq-sort', 'data-bq-summary', 'data-bq-row-score', 'data-bq-pager']) expect(screen).toContain(k)
  expect(screen.match(/rpc\('/g).length).toBe(1); expect(screen).not.toMatch(/_save|_set\b|_delete/)
  expect(read('src/boost-queue.css')).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
})

test('mocked browser: the queue lists tier and score, highest score first; the tier filter and the sort are sent to the read', async ({ page }) => {
  await mockAdmin(page); const calls = page.l3calls
  await page.goto('/#platform-health?tab=queues')
  const q = page.locator('[data-boost-queue]')
  await expect(q.locator('[data-bq-row]')).toHaveCount(50)
  await expect(q.locator('[data-bq-count]')).toHaveText('60 items')
  await expect(q.locator('[data-bq-row]').first().locator('[data-bq-row-tier="1"]')).toHaveText('Tier 1'); await expect(q.locator('[data-bq-row]').first().locator('[data-bq-row-score]')).toHaveText('80')
  await expect(q.locator('[data-bq-summary] tbody tr')).toHaveCount(2)
  await q.locator('[data-bq-tier]').selectOption('2')
  await expect(q.locator('[data-bq-count]')).toHaveText('7 of 60 items'); await expect(q.locator('[data-bq-row]').first().locator('[data-bq-row-score]')).toHaveText('40')
  await q.locator('[data-bq-tier]').selectOption('none')
  await expect(q.locator('[data-bq-row]').first().locator('[data-bq-row-tier="none"]')).toHaveText('No tier')
  await q.locator('[data-bq-clear]').click(); await q.locator('[data-bq-sort]').selectOption('score:asc')
  await expect(q.locator('[data-bq-row]').first().locator('[data-bq-row-score]')).toHaveText('0')
  expect(calls.filter((x) => x.boostQueue).at(-1).boostQueue).toEqual({ p_args: { offset: 0, sort: 'score', direction: 'asc' } })
})
