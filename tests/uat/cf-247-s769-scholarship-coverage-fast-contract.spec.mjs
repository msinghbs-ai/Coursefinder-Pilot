// Guards: Platform Admin 19 Nov 2026 13:04 AEDT (chat S1-Build, s769; ref 8XEY7B): Scholarships › Coverage loads inside the authenticated role's 8-second statement limit. The listing matcher (security.scholarship_listing_match_v1) works out each item's and each record's key, words and addresses once (materialised CTEs), not for every pair; the coverage read (public.admin_scholarship_coverage_read) returns at most 50 providers a page; the screen pages through them. No table, column, index or job; consumer API untouched.
// The live rolled-back dry run (label live-dry-run) runs the migration's pre- and post-checks against production: the matches of the sampled watch-list providers are unchanged, the watch-list rows and the largest provider's row are timed; these checks keep the rules in the file.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119130000_cf247_s769_scholarship_coverage_fast.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const a = c.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return c.slice(a, c.indexOf('$function$;', a)) }
const screen = fs.readFileSync(new URL('../../src/ScholarshipCoverage.jsx', import.meta.url), 'utf8')

test('each live function is replaced only from the definition that was read; nothing else is created or dropped', () => {
  for (const [sig, md5] of [['security.scholarship_listing_match_v1(uuid)', '2725ab7c6bde402d50083dbe9fbec90a'], ['security.scholarship_coverage_row_v1(uuid)', '9d1daac45a20a180f0ac03891a479976'],
    ['public.admin_scholarship_coverage_read(text,text,integer,integer)', '1c27d8194e2da7c6e8e9ced614caed6e']])
    expect(c).toContain(`if md5(pg_get_functiondef('${sig}'::regprocedure)) <> '${md5}' then`)
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: nothing/m)
  expect(c).not.toMatch(/\bcreate\s+(temp\w*\s+|unlogged\s+)?table\b/i)
  expect(c).not.toMatch(/\b(drop|truncate|delete\s+from|alter\s+table|create\s+(unique\s+)?index)\b/i)
  expect(c.match(/create or replace function /g)).toHaveLength(2)
})

test('the matcher works out keys once per item and once per record, then compares them', () => {
  const f = fn('security.scholarship_listing_match_v1')
  expect(f).toContain('ix as materialized (')
  expect(f).toContain('recs as materialized (')
  expect(f).toContain('jsonb_array_elements(l.items) with ordinality e(e, ord)')
  expect(f).toContain("order by lower(btrim(e->>'name')), (nullif(btrim(e->>'url'), '') is null), l.id, e.ord)")
  // the regular expressions run inside the two materialised CTEs only, never in the pairwise comparison
  const pair = f.slice(f.indexOf('left join lateral ('))
  expect(pair).not.toMatch(/scholarship_series_key_v1|scholarship_url_norm|regexp_split_to_array/)
  // the same rule as v2.15.249 (Fix 5)
  expect(pair).toContain('where r.k = x.ik')
  expect(pair).toContain('or (x.il and r.rl and (strpos(r.k, x.ik) > 0 or strpos(x.ik, r.k) > 0))')
  expect(pair).toContain('or (x.iu is not null and x.iu = any(r.urls)')
  expect(pair).toContain('(select count(*) from unnest(x.ikw) w where w = any(r.kw)) >= 2))')
  expect(pair).toContain("order by (x.iu is not null and x.iu = any(r.urls)) desc, (r.k = x.ik) desc, (r.publication_status = 'published') desc, r.id")
  expect(f).toContain("where length(w) > 3 and w not in ('scholarship', 'scholarships', 'university', 'international')) ikw")
})

test('the coverage read returns at most 50 providers a page, in a stable order, and says which page', () => {
  const f = fn('public.admin_scholarship_coverage_read')
  expect(f).toContain('v_limit int := greatest(1, least(coalesce(p_limit, 50), 50)); v_offset int := greatest(0, coalesce(p_offset, 0));')
  expect(f).toContain('from (select * from ids order by n, code limit v_limit offset v_offset) x;')
  expect(f).toContain("'total', v_total, 'rows', v_rows, 'limit', v_limit, 'offset', v_offset,")
  expect(f).toContain("raise exception 'Curator role or above required' using errcode = '42501'")
  expect(f).not.toContain('300')
})

test('the dry run proves the matches unchanged and the rows inside the limit', () => {
  expect(c).toContain("perform set_config('cf247.s769_before', (")
  expect(c).toContain("raise exception 'post-check: the matches of the sampled watch-list providers changed (% before, % after)'")
  expect(c).toContain("raise exception 'post-check: the watch-list rows took % ms'")
  expect(c).toContain("perform security.scholarship_coverage_row_v1('68022bdf-43e8-44b3-ac14-e9eed9f71e83');")
  expect(c).toContain("raise exception 'post-check: the coverage read is not capped at 50 a page'")
})

test('the screen asks for 50 a page and pages with Previous and Next', () => {
  expect(screen).toContain('const COV_PAGE=50')
  expect(screen).toContain('p_limit:COV_PAGE,p_offset:pageRef.current*COV_PAGE')
  expect(screen).not.toContain('p_limit:300')
  expect(screen).toContain('data-cov-pager')
})

test('Coverage pages through providers 50 at a time', async ({ page }) => {
  const calls = []
  const row = (i) => ({ provider_id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, name: `Provider ${String(i).padStart(3, '0')}`, watch: false, listing_pages: 1, suggested_pages: 0,
    listed: 3, found: 2, published: 1, missing: 1, records: 2, records_published: 1, extra: 0, state: 'to_check', code: null })
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_scholarship_coverage_read', async (r) => {
    const body = r.request().postDataJSON() || {}
    calls.push(body)
    const off = Number(body.p_offset || 0), lim = Number(body.p_limit || 50)
    const rows = Array.from({ length: Math.max(0, Math.min(lim, 120 - off)) }, (_, k) => row(off + k + 1))
    await r.fulfill({ json: { scope: body.p_scope || 'watch', total: 120, rows, limit: lim, offset: off, can_manage: true, can_watch: true, auto_publish: { on: false, recent: [] },
      totals: { watch: 27, with_listing: 120, suggested: 0, checked: 3, active: 2187, published: 900 } } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_scholarship_layer_read', r => r.fulfill({ json: { can_manage: true, settings: [], jobs: [] } }))
  await page.goto('/#scholarships?tab=coverage')
  const pager = page.locator('[data-cov-pager]')
  await expect(pager).toContainText('Showing 1–50 of 120 providers')
  await expect(page.locator('[data-cov-row]')).toHaveCount(50)
  await expect(page.locator('[data-cov-prev]')).toBeDisabled()
  await page.locator('[data-cov-next]').click()
  await expect(pager).toContainText('Showing 51–100 of 120 providers')
  await page.locator('[data-cov-next]').click()
  await expect(pager).toContainText('Showing 101–120 of 120 providers')
  await expect(page.locator('[data-cov-row]')).toHaveCount(20)
  await expect(page.locator('[data-cov-next]')).toBeDisabled()
  expect(calls.every((b) => Number(b.p_limit) === 50)).toBe(true)
  expect(calls.map((b) => Number(b.p_offset))).toEqual(expect.arrayContaining([0, 50, 100]))
})
