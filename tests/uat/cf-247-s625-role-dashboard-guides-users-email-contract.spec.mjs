// Guards: Platform Admin 18 Nov 2026 10:31 and 10:33 (S1-RM-Design, UI/UX modernisation): the Dashboard is drawn for the signed-in role (Viewer and Counsellor start with Search the catalogue and see no pipeline or Inbox counts; a Curator sees Waiting for you without the operator rows; a Platform Admin also sees Waiting for your approval), every role has Continue where you left off and its own guide under Guides › Role guides (generated to docs/role-guides/ from one source, pages taken from the menu); Create user is a guided flow with the role's permissions shown, inline validation and a confirmation; the email body is edited as formatted text in a frame that runs no script, and the delivery route and each button's scope are stated.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { mockAdmin } from './support/admin-mock.mjs'
import { ROLE_GUIDES, guideForRank, pagesFor } from '../../src/guide/roleGuides.js'
import { canOpen } from '../../src/nav-map.js'
import { emailProblem, passwordChecks } from '../../src/CreateUserWizard.jsx'
import { cleanEmailHtml, linkTarget } from '../../src/RichEmailEditor.jsx'

const read = (p) => fs.readFileSync(p, 'utf8')

test('role guides: one per role, pages from the menu, the generated documents match the source', () => {
  expect(ROLE_GUIDES.map((g) => g.rank)).toEqual([1, 2, 3, 4, 5, 6])
  for (const g of ROLE_GUIDES) {
    for (const p of pagesFor(g.rank)) expect(canOpen(p.key, g.rank), `${g.id} ${p.key}`).toBe(true)
    expect(g.can.length && g.cannot.length).toBeTruthy()
  }
  expect(pagesFor(1).map((p) => p.key)).not.toContain('layer4')
  expect(pagesFor(3).map((p) => p.key)).toContain('layer4')
  expect(pagesFor(3).map((p) => p.key)).not.toContain('users')
  expect(guideForRank(2).id).toBe('counsellor')
  execFileSync('node', ['scripts/export-role-guides.mjs', '--check'], { stdio: 'pipe' })
  expect(read('src/nav-map.js')).toContain("{ key: 'role-guides', label: 'Role guides', min: 1 },")
})

test('create user: email, password and role checks are the screen\'s; the edge function is unchanged', () => {
  expect(emailProblem('', [])).toMatch(/Enter/)
  expect(emailProblem('alex@', [])).toMatch(/not a complete email/)
  expect(emailProblem('Alex@Example.edu.au', ['alex@example.edu.au'])).toMatch(/already exists/)
  expect(emailProblem('alex@example.edu.au', [])).toBe('')
  expect(passwordChecks('short1').every(([, ok]) => ok)).toBe(false)
  expect(passwordChecks('longenoughpass1').every(([, ok]) => ok)).toBe(true)
  expect(read('src/access-roles-entry.jsx')).toContain('<CreateUserWizard roles={roles} existing={users.map(u=>u.email)}')
})

test('email editor: pasted script, handlers and javascript links are removed; links are https or a link variable', () => {
  expect(cleanEmailHtml('<p onclick="x()">Hi<script>alert(1)</script></p><a href="javascript:alert(1)">x</a><iframe src="https://e"></iframe>')).toBe('<p>Hi</p><a href="#">x</a>')
  expect(linkTarget('{{link}}')).toBe('{{link}}')
  expect(linkTarget('https://studysearch.example/guide')).toBe('https://studysearch.example/guide')
  expect(linkTarget('http://plain.example')).toBe('')
  expect(linkTarget('javascript:alert(1)')).toBe('')
  const screen = read('src/AuthEmailTemplates.jsx')
  for (const k of ['data-aet-route=', 'data-aet-route-sender', 'data-aet-delivery-scope', 'data-aet-template-scope', "'Save Provider Settings'", "'Save Template'", "'Send This Template as a Test'"]) expect(screen).toContain(k)
})

test.describe('mocked browser', () => {
  test('Viewer: role line, Search the catalogue and Continue where you left off; no Inbox, no pipeline rows', async ({ page }) => {
    await mockAdmin(page, { rank: 1 })
    await page.goto('/#dashboard')
    await expect(page.locator('[data-db-role="viewer"]')).toContainText('Viewer · rank 1')
    await expect(page.locator('[data-db-search]')).toBeVisible()
    await expect(page.locator('[data-db-recent-empty]')).toBeVisible()
    await expect(page.locator('[data-waiting]')).toHaveCount(0)
    await expect(page.locator('[data-db-approvals]')).toHaveCount(0)
    await expect(page.locator('[data-dashboard-progress]')).toHaveCount(0)
    await page.locator('[data-db-search-q]').fill('Master of Nursing')
    await page.locator('[data-db-search-go]').click()
    await expect(page).toHaveURL(/#courses/)
    await expect(page.locator('.m-searchbox input')).toHaveValue('Master of Nursing')
    await expect.poll(() => page.evaluate(() => Object.keys(localStorage).filter((k) => k.startsWith('cf-recent:v1:')).map((k) => localStorage.getItem(k)).join(''))).toContain('Master of Nursing')
    // the search and the page are on the list when the Dashboard opens again, and Resume puts the search back
    await page.goto('/#dashboard')
    await expect(page.locator('[data-db-recent-item="search"]').first()).toContainText('Master of Nursing')
    await page.evaluate(() => { for (const k of Object.keys(localStorage)) if (k.includes(':course')) { const v = JSON.parse(localStorage.getItem(k)); v.query = ''; localStorage.setItem(k, JSON.stringify(v)) } })
    await page.locator('[data-db-recent-item="search"] [data-db-recent-resume]').first().click()
    await expect(page.locator('.m-searchbox input')).toHaveValue('Master of Nursing')
  })

  test('Curator: Waiting for you without the operator rows; the role guide opens from the Dashboard', async ({ page }) => {
    await mockAdmin(page, { rank: 3, role: 'curator' })
    await page.goto('/#dashboard')
    await expect(page.locator('[data-db-role="curator"]')).toBeVisible()
    await expect(page.locator('[data-waiting]')).toBeVisible()
    await expect(page.locator('[data-queue="failed_jobs"], [data-queue="failed_automations"]')).toHaveCount(0)
    await expect(page.locator('[data-db-search]')).toHaveCount(0)
    await page.locator('[data-db-role-guide]').click()
    await expect(page.locator('[data-role-guides]')).toBeVisible()
    await expect(page.locator('[data-role-guide-pick="curator"]')).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator('[data-role-guide-pages]')).toContainText('Layer 4 Review')
    await expect(page.locator('[data-role-guide-pages]')).not.toContainText('Users & roles')
  })

  test('Platform Admin: Waiting for your approval lists an edition ready to publish and the email route', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_destination_overview', (r) => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ editions_list: [{ edition_id: 'e1', country_code: 'AU', domain: 'city_profiles', edition_label: 'ABS Regional population 2024-25', status: 'draft', terms_status: 'approved', rows: 102, rows_approved: 102 }] }) }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_email_delivery_read', (r) => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ delivery: { email_provider: 'supabase', key_saved: false, from_email: '', sender_name: 'StudySearch' } }) }))
    await page.goto('/#dashboard')
    const a = page.locator('[data-db-approvals]')
    await expect(a.locator('[data-db-approval="ed:e1"]')).toContainText('ABS Regional population 2024-25')
    await expect(a.locator('[data-db-approval="ed:e1"]')).toContainText('102 of 102 rows approved')
    await expect(a.locator('[data-db-approval="mail"]')).toContainText('Supabase Built-in')
    await expect(page.locator('[data-waiting]')).toBeVisible()
  })

  test('Create user: four steps, inline email check, the role\'s permissions, a confirmation', async ({ page }) => {
    await mockAdmin(page)
    const sent = []
    await page.route('https://example.supabase.co/functions/v1/admin-user-management', async (r) => {
      const b = r.request().postDataJSON() || {}
      if (b.action === 'create') { sent.push(b); return r.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true }) }) }
      return r.fulfill({ contentType: 'application/json', body: JSON.stringify({ users: [{ id: 'u1', email: 'taken@example.edu.au', roles: [], email_confirmed_at: '2026-11-01' }],
        roles: [{ code: 'viewer', name: 'Viewer', rank: 1, description: 'Read' }, { code: 'curator', name: 'Curator', rank: 3, description: 'Curate' }, { code: 'platform_admin', name: 'Platform Admin', rank: 6, description: 'All' }], events: [] }) })
    })
    await page.goto('/#users')
    await page.getByRole('button', { name: 'Create user' }).click()
    const m = page.locator('.cuw')
    await m.locator('[data-cuw-email]').fill('taken@example.edu.au')
    await m.locator('[data-cuw-next]').click()
    await expect(m).toContainText('already exists')
    await expect(m).toHaveAttribute('data-cuw-step', 'person')
    await m.locator('[data-cuw-email]').fill('alex.nguyen@example.edu.au')
    await m.locator('[data-cuw-name]').fill('Alex Nguyen')
    await m.locator('[data-cuw-next]').click()
    await m.locator('[data-cuw-role="curator"]').check()
    await expect(m.locator('[data-cuw-perms="curator"]')).toContainText('Cannot')
    await m.locator('[data-cuw-next]').click()
    await expect(m.locator('[data-cuw-invite-help]')).toBeVisible()
    await m.locator('[data-cuw-next]').click()
    await expect(m.locator('[data-cuw-review]')).toContainText('alex.nguyen@example.edu.au')
    await m.locator('[data-cuw-create]').click()
    await expect(page.locator('[data-cuw-done="invite"]')).toContainText('Invitation sent')
    expect(sent).toHaveLength(1)
    expect(sent[0]).toMatchObject({ action: 'create', email: 'alex.nguyen@example.edu.au', mode: 'invite', roles: ['curator'], full_name: 'Alex Nguyen' })
  })
})
