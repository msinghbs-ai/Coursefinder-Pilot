// CF-247 (S75) v2.15.294. Platform Admin, 19 Oct 2026 22:13 (captures of the Evidence list for one course and its panel): "evidence still
// duplicated"; "tried opening view page and error Preview_not_allowed". Each row says what it is (copy n of m, in use, older copy whose values
// are in use, provider facts page, register file); View page opens the saved page here, unpacked, in a sandboxed frame.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261019100000_cf247_evidence_copy_roles.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/admin-evidence-access/index.ts', 'utf8')
const src = fs.readFileSync('src/EvidenceWorkspace.jsx', 'utf8')
const lib = fs.readFileSync('src/lib/supabase.js', 'utf8')

test('copy roles: staff only, read-only, nothing dropped, consumer API untouched', () => {
  expect(mig).toContain('CREATE OR REPLACE FUNCTION public.admin_evidence_copy_roles(p_ids uuid[])')
  expect(mig).toContain("if security.current_role_rank() < 3 then raise exception")
  expect(mig).toContain('revoke execute on function public.admin_evidence_copy_roles(uuid[]) from public, anon;')
  expect(mig).toMatch(/^-- Replaces: nothing$/m)
  expect(mig).toMatch(/^-- Retires: nothing$/m)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate|update|insert into (?!pipeline\.component_register))/im)
  expect(mig).not.toMatch(/public\.(website_|zoho_edge_|svc_website)|\bapi\./i)
  expect(mig).toContain("when r.in_use then 'in_use' when r.values_live then 'older_values_live' else 'older' end")
  expect(lib).toContain("supabase.rpc('admin_evidence_copy_roles', { p_ids: ids })")
})

test('evidence access: saved web pages and gzip files are unpacked and returned as text; other types as before', () => {
  expect(fn).toContain('stream.pipeThrough(new DecompressionStream("gzip"))')
  expect(fn).toContain('const textMimes = new Set(["text/html", "application/xhtml+xml", "text/markdown", "text/csv", "text/plain", "application/json"]);')
  expect(fn).toContain('// fixed: response-size safety')
  expect(fn).toContain('if (Number(context?.role_rank || 0) < 3) return reply(403, { error: "curator_role_required" });')
  expect(fn).toContain('if (mode === "preview" && !previewMimes.has(mime)) return reply(415, { error: "preview_not_allowed", download_allowed: true });')
  // the viewer: every sandbox restriction on, and a content policy that blocks scripts
  expect(src).toContain('sandbox="" referrerPolicy="no-referrer" srcDoc={doc}')
  expect(src).toContain(`const VIEW_POLICY="default-src 'none'; img-src https: data:; style-src https: 'unsafe-inline'; font-src https: data:"`)
  expect(src).not.toMatch(/sandbox="[^"]*allow-scripts/)
})

const ROWS = [
  { id: 'ev-new', evidence_type: 'source_snapshot', mime_type: 'text/html', captured_at: '2026-10-05T10:51:00Z', source_label: 'Alpha University course pages', storage_available: true },
  { id: 'ev-facts', evidence_type: 'source_snapshot', mime_type: 'text/markdown', captured_at: '2026-10-04T20:50:00Z', source_label: 'Alpha University course pages', storage_available: true },
  { id: 'ev-old', evidence_type: 'source_snapshot', mime_type: 'text/html', captured_at: '2026-10-02T22:17:00Z', source_label: 'Alpha University course pages', storage_available: true },
  { id: 'ev-reg', evidence_type: 'regulatory_snapshot', mime_type: 'application/json', captured_at: '2026-08-17T09:30:00Z', source_label: 'Provincial catalogue', storage_available: true },
]
const ROLES = {
  'ev-new': { kind: 'course_page', role: 'in_use', copy: 2, copies: 2 },
  'ev-old': { kind: 'course_page', role: 'older_values_live', copy: 1, copies: 2 },
  'ev-facts': { kind: 'provider_facts', role: null, copy: 0, copies: 0 },
  'ev-reg': { kind: 'register_file', role: null, copy: 0, copies: 0 },
}
const OLD = {
  id: 'ev-old', evidence_type: 'source_snapshot', captured_at: '2026-10-02T22:17:00Z', page_url: 'https://alpha.edu.au/courses/bba',
  course: { id: 'c1', title: 'Bachelor of Business', code: 'BBA', provider: 'Alpha University' },
  accepted: { basis: 'field_award', in_use: false }, supplied: { total: 1, items: [{ field: 'Fee', value: 'AUD 24,963 a year 2026', status: 'active' }] },
  reviews_open: 0, copies: { earlier: 0, later: 1, newest_id: 'ev-new' },
  file: { available: true, size_bytes: 16252, mime_type: 'text/html', storage_path: 'layer2/AU/coverage/u1/c1/abc.html.gz' },
}

test.describe('mocked browser', () => {
  test('rows say which copy is which; the older copy with live values is not called replaced; View page opens the page here', async ({ page }) => {
    await mockAdmin(page)
    const access = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      const b = route.request().postDataJSON() || {}
      if (b.p_operation === 'evidence_page') return route.fulfill({ json: { total: 4, items: ROWS } })
      return route.fallback()
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_evidence_copy_roles', route => route.fulfill({ json: ROLES }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_evidence_summary', route => route.fulfill({ json: OLD }))
    await page.route('https://example.supabase.co/functions/v1/admin-evidence-access', async route => {
      const b = route.request().postDataJSON(); access.push(b.mode)
      return route.fulfill({ json: { evidence_id: 'ev-old', mode: b.mode, mime_type: 'text/html', kind: 'html', file_name: 'abc.html', content: '<!doctype html><html><body><h1>Bachelor of Business</h1><script>parent.document.title="hacked"</script></body></html>', size_bytes: 120, truncated: false } })
    })
    await page.goto('/#evidence')
    const rows = page.locator('.evidence-table tbody tr')
    await expect(rows.nth(0).locator('.ev-copy-role')).toHaveText('Course page in use · copy 2 of 2')
    await expect(rows.nth(1).locator('.ev-copy-role')).toHaveText("Provider's facts page (not this course's page)")
    await expect(rows.nth(2).locator('.ev-copy-role')).toHaveText('Older copy · its values are in use · copy 1 of 2')
    await expect(rows.nth(3).locator('.ev-copy-role')).toHaveText('Register or catalogue file')

    await rows.nth(2).click()
    const d = page.locator('aside.evidence-drawer')
    await expect(d.locator('[data-ev-result="accepted"]')).toContainText('Older copy · its values are in use')
    await expect(d.locator('[data-ev-result="accepted"]')).not.toContainText('Replaced by a newer copy')
    await expect(d.locator('[data-ev-values-here]')).toBeVisible()

    const title = await page.title()
    await d.getByRole('button', { name: 'View page' }).click()
    const viewer = page.getByRole('dialog', { name: 'Saved page' })
    await expect(viewer).toBeVisible()
    const frame = viewer.locator('iframe.ev-viewer-frame')
    await expect(frame).toHaveAttribute('sandbox', '')
    await expect(page.frameLocator('iframe.ev-viewer-frame').locator('h1')).toHaveText('Bachelor of Business')
    expect(await page.title()).toBe(title) // the saved page's script did not run
    await page.keyboard.press('Escape')
    await expect(viewer).toHaveCount(0)
    await expect(d).toBeVisible() // Escape closed the viewer only
    expect(access).toEqual(['preview'])
  })
})
