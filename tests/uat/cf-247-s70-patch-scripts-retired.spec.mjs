// Guards: Release contract: legacy release history frozen at 2.15.78; patch scripts retired
// CF-247 (S70) v2.15.291, Phase 5 "retire the leftovers" (Platform Admin): the scripts index.html loaded after React drew the page,
// each patching the page with a MutationObserver, are retired. What they still showed is drawn by React; the version and release
// history come from one place (release-manifest.js, and public/release-history.json built from docs, the manifest and the legacy list).
// Nothing kept. UI only: no supabase/ change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { UI_VERSION, RELEASE } from '../../src/release-manifest.js'
import { LEGACY_BASELINE, LEGACY_RELEASES } from '../../src/release-history-legacy.js'

const RETIRED = ['StatisticsDatasetEnhancer.js', 'ranking-dataset-header.js', 'evidence-acquisition-provenance-entry.js', 'pim-version-entry.js', 'release-currentness-entry.js']

test('index.html loads only the React entry; the patch scripts are gone and nothing imports them', () => {
  const html = fs.readFileSync('index.html', 'utf8')
  expect(html.match(/<script\b[^>]*>/g)).toEqual(['<script type="module" src="/src/mature-main.jsx">'])
  const src = fs.readdirSync('src', { recursive: true }).filter(f => /\.(jsx?|css)$/.test(f)).map(f => fs.readFileSync(`src/${f}`, 'utf8')).join('\n')
  for (const f of RETIRED) {
    expect(fs.existsSync(`src/${f}`), f).toBe(false)
    expect(html, f).not.toContain(f)
    expect(src, f).not.toMatch(new RegExp(`from\\s*['"]\\./${f.replace(/\.js$/, '').replace(/[.-]/g, '\\$&')}(\\.js)?['"]`))
  }
})

test('one version source: the shell and the pill import the manifest; the legacy notes are data for the release history', () => {
  const shell = fs.readFileSync('src/mature-main.jsx', 'utf8'), pill = fs.readFileSync('src/ReleaseNotes.jsx', 'utf8')
  expect(shell).toContain("import{UI_VERSION}from'./release-manifest.js'")
  expect(shell).not.toMatch(/const UI_VERSION='2\.15\.\d+'/)
  expect(pill).toContain("import{UI_VERSION,RELEASE}from'./release-manifest.js'")
  expect(LEGACY_BASELINE).toBe('2.15.78')
  expect(LEGACY_RELEASES[0].version).toBe('2.15.78')
  expect(LEGACY_RELEASES.length).toBe(58)
  const build = fs.readFileSync('scripts/build-release-history.mjs', 'utf8'), verify = fs.readFileSync('scripts/verify-release-contract.mjs', 'utf8')
  expect(build).toContain("import{LEGACY_RELEASES}from'../src/release-history-legacy.js'")
  expect(build).not.toContain('pim-version-entry.js\')')
  expect(verify).toContain("read('src/release-history-legacy.js')")
  expect(verify).toContain('retired page-patch script')
  // The ported pieces live in their React components
  expect(shell).toContain("supabase.rpc('statistics_dataset_registry_read')")
  expect(shell).toContain('RANKING_DATASET_HEADER')
  // v2.15.293: the Evidence acquisition box ported here was then retired with the one-screen Evidence panel (S73).
  expect(fs.readFileSync('src/EvidenceWorkspace.jsx', 'utf8')).not.toContain('AcquisitionProvenance')
  expect(fs.readFileSync('src/evidence-workspace.css', 'utf8')).not.toContain('.cf-evidence-acq{')
  expect(fs.readFileSync('src/evidence-workspace.css', 'utf8')).toContain('.ev-sum{')
  expect(fs.readFileSync('src/release-notes.css', 'utf8')).toContain('.m-release-notes-dialog{')
})

test.describe('mocked browser', () => {
  test('the pill opens the release notes: current release first, then the built history; Escape closes and returns focus', async ({ page }) => {
    await page.route('**/release-history.json', r => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ current: UI_VERSION, count: 2, releases: [{ ...RELEASE, version: UI_VERSION }, LEGACY_RELEASES[0]] }) }))
    await mockAdmin(page)
    await page.goto('/#dashboard')
    await expect(page).toHaveTitle(`StudySearch PIM Admin v${UI_VERSION}`)
    expect(await page.evaluate(() => document.documentElement.dataset.cfReleaseVersion)).toBe(UI_VERSION)
    await expect(page.locator('.m-brand-copy small')).toHaveText(`PIM Admin v${UI_VERSION}`)
    const pill = page.locator('.m-release-pill')
    await expect(pill).toHaveText(`v${UI_VERSION}`)
    await expect(pill).toHaveAttribute('role', 'button')
    await expect(pill).toHaveAttribute('aria-haspopup', 'dialog')
    await pill.click()
    const dialog = page.getByRole('dialog', { name: 'Release notes' })
    await expect(dialog).toBeVisible()
    await expect(dialog.locator('[data-release-version]').first()).toHaveAttribute('data-release-version', UI_VERSION)
    await expect(dialog.locator(`[data-release-version="${UI_VERSION}"]`)).toContainText(RELEASE.title)
    await expect(dialog.locator(`[data-release-version="${UI_VERSION}"]`)).toHaveCount(1)
    await expect(dialog.locator('[data-release-version="2.15.78"]')).toContainText(LEGACY_RELEASES[0].title)
    await expect(dialog.getByRole('link', { name: 'All release notes (2) →' })).toHaveAttribute('href', '/release-history.html')
    await page.keyboard.press('Escape')
    await expect(dialog).toBeHidden()
    await expect(pill).toBeFocused()
    await page.keyboard.press('Enter')
    await expect(dialog).toBeVisible()
  })

  test('Rankings & statistics: cards follow the dataset registry with their description and one edition picker; a dataset page names the dataset', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#statistics-rankings')
    const cards = page.locator('.m-stats-grid .m-stats-card')
    // The registry fixture switches on QS only (ARWU is off): the others are hidden as the retired enhancer did.
    await expect(cards).toHaveCount(1)
    await expect(cards.first()).toHaveAttribute('data-dataset-key', 'qs_wur')
    await expect(cards.first().locator('.cf-stat-desc')).toHaveText('Global institutional ranking.')
    await expect(cards.first().locator('select')).toHaveCount(1)
    await expect(page.locator('.m-topbar h1')).toHaveText('Rankings & statistics')
    await page.goto('/#statistics-rankings?dataset=qs_wur&year=2027')
    await expect(page.locator('.m-topbar h1')).toHaveText('QS World University Rankings')
    await expect(page.locator('.m-topbar h1 + p')).toHaveText('QS ranking positions by edition, matched to our providers, with the source file kept.')
  })
})
