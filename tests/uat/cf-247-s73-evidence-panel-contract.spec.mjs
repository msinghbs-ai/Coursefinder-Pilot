// Guards: CF-247 (S73) v2.15.293. Platform Admin, 19 Oct 2026: "explain why the evidence details panel is so bloated and hard to read ...
// CF-247 (S73) v2.15.293. Platform Admin, 19 Oct 2026: "explain why the evidence details panel is so bloated and hard to read ... simplify ...
// readability". The Evidence panel is one screen from public.admin_evidence_summary: what the saved page is, its course, whether it was
// accepted and is in use, what it supplied, its copies, View page and Download, and a closed "Technical details" part. UI only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const src = fs.readFileSync('src/EvidenceWorkspace.jsx', 'utf8')
const lib = fs.readFileSync('src/lib/supabase.js', 'utf8')

const ROW = { id: 'ev-1', evidence_type: 'source_snapshot', mime_type: 'text/html', captured_at: '2026-10-18T02:00:00Z', source_label: 'Alpha University', status: 'active', extraction_state: 'extracted', freshness_state: 'current', observation_count: 0, content_hash: 'abc123def4567890', storage_available: true }
const SUMMARY = {
  id: 'ev-1', evidence_type: 'source_snapshot', captured_at: '2026-10-18T02:00:00Z', page_url: 'https://alpha.edu.au/courses/master-of-test',
  source: { label: 'Alpha University', url: 'https://alpha.edu.au', type: 'provider_website' }, fetched_via: 'firecrawl', worker: 'coverage-sweep-worker-v0.40.1',
  course: { id: 'c1', title: 'Master of Test', code: '012345A', provider: 'Alpha University', provider_id: 'u1' },
  accepted: { basis: 'exact_title', in_use: true, page_now: 'https://alpha.edu.au/courses/master-of-test' },
  supplied: { total: 23, items: [{ field: 'Fee', value: 'AUD 45,600 a year 2027', status: 'active' }, { field: 'Intake', value: 'February 2027', status: 'superseded' }, { field: 'English', value: 'IELTS overall 6.5', status: 'active' }] },
  reviews_open: 1, copies: { earlier: 2, later: 0, newest_id: null },
  file: { available: true, size_bytes: 182340, mime_type: 'text/html', content_hash: 'abc123def4567890', storage_path: 'layer2/v2/coverage/u1/c1/page.html' },
  job: { id: 'job-9', type: 'coverage_read', status: 'completed' },
}
const OLD = { ...SUMMARY, id: 'ev-0', accepted: { basis: 'cricos_code', in_use: false }, supplied: { total: 0, items: [] }, reviews_open: 0, copies: { earlier: 0, later: 3, newest_id: 'ev-1' } }

async function mockEvidence(page, calls) {
  await mockAdmin(page)
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    calls.push(b.p_operation)
    if (b.p_operation === 'evidence_page') return route.fulfill({ json: { total: 1, items: [ROW] } })
    return route.fallback()
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_evidence_summary', async route => {
    const id = route.request().postDataJSON().p_id
    calls.push(`summary:${id}`)
    return route.fulfill({ json: id === 'ev-0' ? OLD : SUMMARY })
  })
}

test('source: the panel reads admin_evidence_summary only; the old sections are gone', () => {
  expect(lib).toContain("supabase.rpc('admin_evidence_summary', { p_id: evidenceId })")
  expect(src).toContain('api.evidenceSummary(id)')
  for (const old of ['api.evidenceDetail(', 'api.evidenceEntities(', 'api.evidenceObservations(', 'Private evidence boundary', 'Acquisition provenance', 'Storage controls', 'LineageStrip', 'Claims, review & decisions', 'evidence-lineage'])
    expect(src, old).not.toContain(old)
  expect(src).toContain("e.key==='Escape'&&onClose()")
  expect(src).toContain('<details className="ev-sum-tech"><summary>Technical details</summary>')
})

test.describe('mocked browser', () => {
  test('a course page: course, accepted and in use, what it supplied, technical details closed; fits one screen; Escape closes', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    const calls = []
    await mockEvidence(page, calls)
    await page.goto('/#evidence')
    await page.locator('.evidence-table tbody tr').first().click()
    const d = page.locator('aside.evidence-drawer')
    await expect(d.locator('h2')).toHaveText('Course page')
    await expect(d.locator('.ev-sum-card h3')).toHaveText('Master of Test')
    await expect(d.locator('.ev-sum-card')).toContainText('012345A · Alpha University')
    await expect(d.getByRole('button', { name: 'Open course →' })).toBeVisible()
    await expect(d.locator('.ev-sum-url')).toHaveAttribute('href', 'https://alpha.edu.au/courses/master-of-test')
    await expect(d.locator('.ev-sum-card')).toContainText('through Firecrawl')
    await expect(d.locator('[data-ev-result="accepted"]')).toContainText("Accepted as this course's page (exact title)")
    await expect(d.locator('[data-ev-result="accepted"]')).toContainText('In use now')
    const supplied = d.locator('.ev-sum-supplied')
    await expect(supplied.getByRole('heading', { name: 'What this page supplied' })).toBeVisible()
    await expect(supplied).toContainText('AUD 45,600 a year 2027')
    await expect(supplied.locator('li').filter({ hasText: 'Fee' }).locator('.cf-chip')).toHaveCount(0) // active: no chip
    await expect(supplied.locator('li').filter({ hasText: 'Intake' }).locator('.cf-chip')).toHaveCount(1)
    await expect(supplied).toContainText('and 20 more')
    await expect(d.locator('[data-ev-counts]')).toHaveText('1 open review item · 2 earlier copies')
    await expect(d.getByRole('button', { name: 'View page' })).toBeEnabled()
    await expect(d.getByRole('button', { name: 'Download' })).toBeEnabled()
    const tech = d.locator('details.ev-sum-tech')
    await expect(tech).not.toHaveAttribute('open', '')
    await expect(tech.getByText('layer2/v2/coverage/u1/c1/page.html')).toBeHidden()
    await tech.locator('summary').click()
    await expect(tech.getByText('layer2/v2/coverage/u1/c1/page.html')).toBeVisible()
    await tech.locator('summary').click()
    for (const gone of ['Private evidence boundary', 'Acquisition provenance', 'Storage controls', 'Extracted observations']) await expect(d.getByText(gone)).toHaveCount(0)
    // One screen: the body does not scroll at 1440x900 with technical details closed
    const body = d.locator('.evidence-drawer-body')
    expect(await body.evaluate(e => e.scrollHeight <= e.clientHeight + 1)).toBe(true)
    expect(calls).toContain('summary:ev-1')
    expect(calls.filter(c => ['evidence_detail', 'evidence_entities', 'evidence_observations'].includes(c))).toEqual([])
    await page.keyboard.press('Escape')
    await expect(d).toHaveCount(0)
  })

  test('an older copy that supplied nothing: one short line, replaced, opens the newest copy', async ({ page }) => {
    const calls = []
    await mockEvidence(page, calls)
    await page.goto('/#evidence?evidence_id=ev-0')
    const d = page.locator('aside.evidence-drawer')
    await expect(d.locator('[data-ev-supplied="none"]')).toHaveText('No live value comes from this copy.')
    await expect(d.locator('.ev-sum-supplied')).toHaveCount(0)
    await expect(d.locator('[data-ev-result="accepted"]')).toContainText("Accepted as this course's page (CRICOS code)")
    await expect(d.locator('[data-ev-result="accepted"]')).toContainText('Replaced by a newer copy')
    await expect(d.getByText('In use now')).toHaveCount(0)
    await expect(d.locator('[data-ev-counts]')).toHaveText('3 later copies')
    await d.getByRole('button', { name: 'Open the newest copy →' }).click()
    await expect(d.locator('[data-ev-result="accepted"]')).toContainText('In use now')
    expect(calls).toContain('summary:ev-1')
  })
})
