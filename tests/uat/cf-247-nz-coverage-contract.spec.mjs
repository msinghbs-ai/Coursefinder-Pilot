// Decision 217: New Zealand course pages, search and tuition; fee schedules follow the Coverage country.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { mockAdmin } from './support/admin-mock.mjs'

async function load() {
  const out = path.join(os.tmpdir(), `nzcov-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/extract.ts', '--format=esm', `--outfile=${out}`])
  return import(out)
}
const pg = (title, h1, body) => `<html><head><title>${title}</title></head><body><h1>${h1}</h1><p>${body}</p></body></html>`

test('NZ identity: NZQA title with the same level, labelled NZQA number; Australia unchanged', async () => {
  const { identity, htmlToText } = await load()
  const id = (html, title, code) => identity(html, htmlToText(html), title, code)
  // heading without the level, page shows the same level
  expect(id(pg('Bachelor of Applied Information Technology | Wintec', 'Bachelor of Applied Information Technology', 'NZQA Level 7 degree'), 'Bachelor of Applied Information Technology (Level 7)', '3187')).toBe('title_level')
  // "+" for "and", and "NZ" for "New Zealand"
  expect(id(pg('NZ Certificate in Health + Wellbeing (Level 2) | X', 'NZ Certificate in Health + Wellbeing (Level 2)', ''), 'New Zealand Certificate in Health and Wellbeing (Level 2)', '2469')).toBe('title_level')
  // another level in the heading: rejected
  expect(id(pg('New Zealand Certificate in Health and Wellbeing (Level 4) | X', 'New Zealand Certificate in Health and Wellbeing (Level 4)', 'Level 4'), 'New Zealand Certificate in Health and Wellbeing (Level 3)', '2470')).toBeNull()
  // heading without a level but the page does not show the level: rejected
  expect(id(pg('Bachelor of Applied Information Technology | Wintec', 'Bachelor of Applied Information Technology', 'Apply now'), 'Bachelor of Applied Information Technology (Level 7)', '3187')).toBeNull()
  // one page for several levels of the same qualification: rejected on title
  expect(id(pg('New Zealand Certificate in Cookery | EIT', 'New Zealand Certificate in Cookery', 'New Zealand Certificate in Cookery Level 3 and New Zealand Certificate in Cookery Level 4'), 'New Zealand Certificate in Cookery (Level 4)', '2489')).toBeNull()
  // a longer course name that starts with the title: rejected
  expect(id(pg('Bachelor of Arts and Science | Uni', 'Bachelor of Arts and Science', 'Level 7'), 'Bachelor of Arts (Level 7)', '1234')).toBeNull()
  // a labelled NZQA number on the page
  expect(id(pg('Some heading', 'Some heading', 'NZQA qualification number: 3187'), 'Bachelor of Something Else (Level 7)', '3187')).toBe('nzqa_code')
  // a bare 4-digit number is not enough
  expect(id(pg('Some heading', 'Some heading', 'Call 3187 today'), 'Bachelor of Something Else (Level 7)', '3187')).toBeNull()
  // Australia: unchanged
  expect(id(pg('Bachelor of Science | Uni', 'Bachelor of Science', 'CRICOS 058837J'), 'Bachelor of Science', '058837J')).toBe('cricos_code')
  expect(id(pg('Bachelor of Science | Uni', 'Bachelor of Science', ''), 'Bachelor of Science', '000000A')).toBe('exact_title')
})

test('NZ fees are read in NZD; amounts in other currencies are left out', async () => {
  const { fee } = await load()
  expect(fee('International students: tuition fees $32,500 per year (2027).', 'NZD')).toMatchObject({ value: 32500, currency: 'NZD' })
  expect(fee('International fees NZ$28,000 per year. Australian students AUD $9,000.', 'NZD').value).toBe(28000)
  expect(fee('International tuition fee US$25,000 per year', 'NZD').value).toBeNull()
  expect(fee('International students AUD 41,000 per year').value).toBe(41000)
  expect(fee('International students AUD 41,000 per year').currency).toBeUndefined()
})

test('migrations: NZ rule, country-aware tuition hand-off, title search without the level, NZ queue', () => {
  const m = fs.readFileSync('supabase/migrations/20261002181300_cf247_nz_pages_search_tuition.sql', 'utf8')
  for (const g of ['e8fce44b38f378aa79a88b05b5b6a6cb','2ec830f93d4dbd42193df2f1da1a3be6','4bba0336ee8c63c54398d502f40b5c8f','3ba55afcac79599090d3fbe6bde13eee','b7c9abd5921dcd27b0d97d751ad21386']) expect(m).toContain(g)
  expect(m).toContain(`'tuition',      '["cricos_code","nzqa_code"]'::jsonb`)
  expect(m).toContain(`security.coverage_identity_allowed(p.provider_id, p.identity_basis, 'tuition')`)
  expect(m).toContain(`v_target:=v_target||jsonb_build_object('currency_code',v_cur);`)
  const d = fs.readFileSync('supabase/migrations/20261002181400_cf247_nz_reread_and_search.sql', 'utf8')
  expect(d).toContain(`select c.id, c.provider_id, 'title', 'queued', now()`)
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  // Decision 220: the reader's currency now comes from currencyFor (NZ → NZD, CA → CAD, otherwise AUD).
  expect(w).toContain('fee(text, currencyFor(it.country))')
})

test('browser: fee schedules follow the Coverage country', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#coverage?tab=attributes')
  const fsx = page.locator('[data-fee-schedules]')
  await expect(fsx.locator('[data-doc="fs1"]')).toHaveCount(1)
  await expect(fsx.locator('[data-fee-scope]')).toHaveCount(0)
  await page.getByLabel('Coverage country').selectOption('NZ')
  await expect(fsx.locator('[data-fee-scope]')).toContainText('No fee schedules for New Zealand')
  await expect(fsx.locator('[data-fee-scope]')).toContainText('Australian providers only')
  await expect(fsx.locator('[data-doc="fs1"]')).toHaveCount(0)
  await page.getByLabel('Coverage country').selectOption('AU')
  await expect(fsx.locator('[data-fee-scope]')).toContainText('Showing')
  await expect(fsx.locator('[data-doc="fs1"]')).toHaveCount(1)
})

test('platform guide explains NZ page rules and fee schedule scope', () => {
  const g = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  expect(g).toContain('Fee schedules follow the country and university chosen above')
  expect(g).toContain('NZQA title without')
})

test('rejected NZ pages flow into the title search each minute (non-CRICOS courses only)', () => {
  const m = fs.readFileSync('supabase/migrations/20261002181500_cf247_nz_mismatch_to_search.sql', 'utf8')
  expect(m).toContain("if md5(s) is distinct from '7895c1193a3cae89d5c5bb4c0319c62a' then raise exception")
  expect(m).toContain("and coalesce(c.course_code, '') !~ '^[0-9]{6}[0-9A-Z]$'")
  expect(m).toContain("and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p.course_id and k.field = 'official_url')")
})
