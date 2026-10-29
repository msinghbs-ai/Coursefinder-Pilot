// Guards: CF-247 Platform Admin mandate 29 Oct 2026 12:23 section A4: one shared AER country order (India, Nepal, Singapore, then the other available countries A–Z) for the Course detail selector and the Entry requirements workspace country lists; the course choice survives a reload and only asks the resolver
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { orderAerCountries, AER_PRIORITY_COUNTRIES, AER_COURSE_COUNTRY_KEY } from '../../src/aer-countries.js'
import * as F from './support/admin-fixtures.mjs'

const drawer = fs.readFileSync('src/EntryRequirements.jsx', 'utf8')
const ws = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')

const RAW = [{ code: 'VN', name: 'Vietnam' }, { code: 'SG', name: 'Singapore' }, { code: 'AU', name: 'Australia' }, { code: 'IN', name: 'India' },
  { code: 'NP', name: 'Nepal' }, { code: 'BD', name: 'Bangladesh' }, { code: 'IN', name: 'India' }, { code: '', name: 'Blank' }, { code: 'LK', name: 'Sri Lanka' }]
const ORDER = ['India', 'Nepal', 'Singapore', 'Australia', 'Bangladesh', 'Sri Lanka', 'Vietnam']

test('helper: India, Nepal, Singapore first, then the rest A–Z; no repeats or blanks; only the countries given', () => {
  expect(AER_PRIORITY_COUNTRIES).toEqual(['IN', 'NP', 'SG'])
  expect(orderAerCountries(RAW).map(c => c.name)).toEqual(ORDER)
  // a priority country that is not available is never invented
  expect(orderAerCountries([{ code: 'NZ', name: 'New Zealand' }, { code: 'SG', name: 'Singapore' }, { code: 'CN', name: 'China' }]).map(c => c.code)).toEqual(['SG', 'CN', 'NZ'])
  expect(orderAerCountries([{ code: 'np', name: 'Nepal' }, { code: 'NP', name: 'Nepal' }, { code: 'in', name: 'India' }]).map(c => c.name)).toEqual(['India', 'Nepal'])
  expect(orderAerCountries(null)).toEqual([])
  expect(orderAerCountries(undefined)).toEqual([])
  // the input is not changed
  const input = [{ code: 'NP', name: 'Nepal' }, { code: 'IN', name: 'India' }]; orderAerCountries(input)
  expect(input.map(c => c.code)).toEqual(['NP', 'IN'])
})

test('source: every AER country list uses the shared helper', () => {
  expect(drawer).toContain("import{orderAerCountries,readAerCountry,saveAerCountry}from'./aer-countries'")
  expect(drawer).toContain('{orderAerCountries(d.countries).map(c=><option key={c.code} value={c.code}>{c.name}</option>)}')
  expect(drawer).not.toContain('(d.countries||[]).map(')
  expect(ws).toContain("import{orderAerCountries}from'./aer-countries'")
  expect(ws).toContain('options={orderAerCountries(o.countries).map(c=>opt(c.code,c.name,c.code))}')
  expect(ws).toContain('options={orderAerCountries(o.all_countries).map(c=>opt(c.code,c.name,c.code))}')
  expect(ws.split('{orderAerCountries(o.all_countries).map(c=><option key={c.code} value={c.code}').length - 1).toBe(2)
  expect(ws).not.toMatch(/\(o\.(all_)?countries\|\|\[\]\)\.map\(/)
})

const RPC = 'https://example.supabase.co/rest/v1/rpc/'

async function watch(page) {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page)
  const calls = []; page.entryCalls = calls
  await page.route(`${RPC}admin_entry_requirements`, async route => {
    const b = route.request().postDataJSON() || {}
    calls.push({ fn: 'admin_entry_requirements', action: b.p_action, args: b.p_args })
    if (b.p_action === 'course') return route.fulfill({ json: { rows: [], reads: [], can_read: true, countries: RAW } })
    if (b.p_action === 'resolve') return route.fulfill({ json: { outcome: 'contact_provider', rule: 'contact_provider', rows: [], note: `resolved for ${b.p_args.country}` } })
    return route.fulfill({ json: {} })
  })
  // anything that would read with AI or start a read is recorded
  page.on('request', r => { const u = r.url(); if (u.startsWith(RPC) && /(admin_aer|enrich|_ai|layer3|course_entry_batch|admin_jobs)/.test(u) && r.method() === 'POST') { let b = {}; try { b = r.postDataJSON() || {} } catch {} calls.push({ fn: u.slice(RPC.length), action: b.p_action }) } })
}

test.describe('mocked browser', () => {
  test('Course detail: the country selector is in the shared order, a change only asks the resolver, and the choice survives a reload', async ({ page }) => {
    await watch(page)
    await page.goto(`/#courses?id=${F.courseDetail.id}`)
    const sel = page.getByLabel('Country of prior education')
    await expect(sel).toBeVisible()
    expect(await sel.locator('option').allTextContents()).toEqual(['Choose…', ...ORDER])
    const before = page.entryCalls.length
    await sel.selectOption('NP')
    await expect(page.locator('[data-entry-resolution]')).toContainText('resolved for NP')
    const after = page.entryCalls.slice(before).filter(c => !(c.fn === 'admin_jobs' && c.action === 'read'))
    expect(after).toEqual([{ fn: 'admin_entry_requirements', action: 'resolve', args: { course_id: F.courseDetail.id, country: 'NP' } }])
    expect(await page.evaluate(k => localStorage.getItem(k), AER_COURSE_COUNTRY_KEY)).toBe('NP')
    // keyboard: the native select still moves with the arrow keys and asks the resolver for the next country only
    await sel.focus(); await page.keyboard.press('ArrowDown')
    await expect(sel).toHaveValue('SG')
    await expect(page.locator('[data-entry-resolution]')).toContainText('resolved for SG')
    await page.reload()
    await expect(page.getByLabel('Country of prior education')).toHaveValue('SG')
    await expect(page.locator('[data-entry-resolution]')).toContainText('resolved for SG')
    const actions = new Set(page.entryCalls.filter(c => c.fn === 'admin_entry_requirements').map(c => c.action))
    expect([...actions].sort()).toEqual(['course', 'resolve'])
    expect(page.entryCalls.filter(c => c.fn !== 'admin_entry_requirements' && !(c.fn === 'admin_jobs' && c.action === 'read'))).toEqual([])
  })

  test('phone width: the Course detail country selector stays inside its card (live tour 29 Oct 2026) @responsive', async ({ page }) => {
    expect(page.viewportSize().width).toBeLessThan(500)
    await watch(page)
    // the longest live option name sets the selector's natural width (DP020 lists every country)
    await page.route(`${RPC}admin_entry_requirements`, async route => {
      const q = route.request().postDataJSON() || {}
      if (q.p_action === 'course') return route.fulfill({ json: { rows: [], reads: [], can_read: true, countries: [...RAW, { code: 'GS', name: 'South Georgia and the South Sandwich Islands' }] } })
      return route.fallback()
    })
    await page.goto(`/#courses?id=${F.courseDetail.id}`)
    const sel = page.getByLabel('Country of prior education')
    await expect(sel).toBeVisible()
    await sel.selectOption('IN')
    await expect(page.locator('[data-entry-resolution]')).toContainText('resolved for IN')
    const box = await sel.evaluate((el) => { const r = el.getBoundingClientRect(); const c = el.closest('[data-course-entry-resolve]').parentElement.getBoundingClientRect(); return { right: r.right, cardRight: c.right, left: r.left, cardLeft: c.left } })
    expect(box.right).toBeLessThanOrEqual(box.cardRight + 1)
    expect(box.left).toBeGreaterThanOrEqual(box.cardLeft - 1)
  })

  test('Entry requirements workspace: the matrix Country filter and the Resolution country picker use the shared order', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    await page.route(`${RPC}admin_aer`, async route => {
      const b = route.request().postDataJSON() || {}
      if (b.p_action === 'options') return route.fulfill({ json: { providers: [], countries: RAW, all_countries: RAW, levels: [], level_labels: [], bands: [], editions: [], intake_years: [], matrix_kinds: [], requirement_kinds: [], scales: [], audiences: [] } })
      if (b.p_action === 'summary') return route.fulfill({ json: { matrix: {}, course: {}, sources: {}, can_edit: false } })
      if (b.p_action === 'matrix_list') return route.fulfill({ json: { total: 0, rows: [] } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#entry-requirements')
    await page.locator('.m-filter-select').getByRole('button', { name: /^Country/ }).click()
    expect(await page.locator('.m-filter-popover > button span').allTextContents()).toEqual(['All', ...ORDER])
    await page.keyboard.press('Escape')
    await page.goto('/#entry-requirements?tab=resolve')
    await page.getByRole('button', { name: /Country of prior education/ }).click()
    expect(await page.locator('.m-filter-popover > button span').allTextContents()).toEqual(['Choose…', ...ORDER])
  })
})
