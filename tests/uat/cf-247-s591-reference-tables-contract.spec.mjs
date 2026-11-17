// Guards: UI audit of the new API v3 fields (Platform Admin 17 Nov 2026 23:05): Reference data shows the API field dictionary and the grade scale conversions as read-only, searchable, filterable lists for Curator and above; the read changes nothing, pages by a setting and touches no consumer API object.
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/admin-reference-tables/run.sh (workflow admin-reference-tables-test); these checks keep the rules in the migration and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations/20261118005000_cf247_admin_reference_tables_read.sql')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const screen = read('src/ReferenceTables.jsx')

test('the migration adds one read-only function and one setting beside what exists', () => {
  expect(m).toMatch(/^-- Replaces: nothing$/m); expect(m).toMatch(/^-- Retires: nothing$/m)
  for (const l of m.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate|update|alter)\b/i)
  expect(c.match(/create or replace function /g).length).toBe(1)
  expect(c).toContain('create or replace function public.admin_reference_table_read(p_kind text, p_args jsonb default \'{}\'::jsonb) returns jsonb\nlanguage plpgsql stable security definer set search_path = \'\'')
  expect(c).toContain("if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for Reference data'")
  expect(c).toContain('revoke all on function public.admin_reference_table_read(text, jsonb) from public, anon;')
  // the only write of the migration is its own setting; the function body writes nothing
  const body = c.slice(c.indexOf('create or replace function public.admin_reference_table_read'), c.indexOf('comment on function public.admin_reference_table_read'))
  expect(body).not.toMatch(/\b(insert into|update |delete from|perform set_config)\b/i)
  expect(c.match(/insert into /g).length).toBe(1); expect(c).toContain("('pipeline', 'admin.reference_table_page_rows', 'Reference data: rows per page',")
  expect(c).toContain('on conflict (toolset_key, key) do nothing;')
})

test('G2: the page size is a setting; typed search text is matched literally', () => {
  expect(c).toContain("security.pipeline_num_v1('admin.reference_table_page_rows', 50)")
  expect(c).not.toMatch(/limit \d/)
  expect(c).toContain("v_like := '%' || replace(replace(replace(v_q, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%';")
})

test('the screen: two more types on Reference data, read-only, with search, filters and pages', () => {
  const main = read('src/mature-main.jsx')
  expect(main).toContain("const REFERENCE_TABLES=['api_fields','grade_scales']")
  expect(main).toContain('{REFERENCE_TABLES.includes(type)?<ReferenceTables kind={type} onError={onError}/>:<>')
  expect(screen).toContain("rpc('admin_reference_table_read',{p_kind:kind,p_args:f})")
  for (const k of ['data-reference-table={kind}', 'data-rft-search', 'data-rft-surface', 'data-rft-version', 'data-rft-country', 'data-rft-active', 'data-rft-clear', 'data-rft-pager', 'data-rft-count']) expect(screen).toContain(k)
  // read-only: no save, edit or delete call
  expect(screen.match(/rpc\('/g).length).toBe(1); expect(screen).not.toMatch(/_save|_edit|_set|_delete/)
  expect(read('src/reference-tables.css')).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
})

test('mocked browser: the dictionary is searched, filtered and paged; grade scales say plainly that none are loaded', async ({ page }) => {
  await mockAdmin(page); const calls = page.l3calls
  await page.goto('/#reference-data?type=api_fields')
  const t = page.locator('[data-reference-table="api_fields"]')
  await expect(t.locator('[data-rft-row]')).toHaveCount(50)
  await expect(t.locator('[data-rft-count]')).toHaveText('120 fields')
  await expect(page.locator('[data-key-dates]')).toHaveCount(0) // the editable lists are not drawn beside a reference table
  await t.locator('[data-rft-next]').click()
  await expect(t.locator('[data-rft-pager]')).toContainText('51 to 100 of 120')
  await t.locator('[data-rft-search]').fill('study_load'); await t.locator('[data-rft-go]').click()
  await expect(t.locator('[data-rft-row]')).toHaveCount(1)
  await expect(t.locator('[data-rft-row]')).toContainText('catalogue.courses.study_load'); await expect(t.locator('[data-rft-row]')).toContainText('R33, REQ-76')
  await expect(t.locator('[data-rft-count]')).toHaveText('1 of 120 fields')
  await t.locator('[data-rft-clear]').click(); await t.locator('[data-rft-surface]').selectOption('zoho')
  await expect(t.locator('[data-rft-count]')).toHaveText('60 of 120 fields')
  expect(calls.filter((x) => x.referenceTable).at(-1).referenceTable).toEqual({ p_kind: 'api_fields', p_args: { query: '', offset: 0, surface: 'zoho' } })
  await page.locator('[data-reference-type="grade_scales"]').click()
  await expect(page.locator('[data-reference-table="grade_scales"]')).toContainText('No grade scale conversions are loaded yet')
})
