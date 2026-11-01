// Guards: SS-016 six-role simulation (Platform Admin overnight mandate 1 Nov 2026 §3; usability review UR-02, UR-17 role walkthroughs): in isolated fixtures, each of Viewer (1), Counsellor (2), Curator (3), Pipeline Operator (4), PIM Admin (5) and Platform Admin (6) sees the screens and actions its rank allows, and a forbidden action is hidden or refused with words that name the next owner. The mocked server refuses where the live function refuses, with its live words (support/role-fixtures.mjs). Fixture evidence only: no real lower-role session is claimed.
import { test, expect } from '@playwright/test'
import { asRole, mockAer, mockAutomations, mockInbox, LIVE } from './support/role-fixtures.mjs'

test('a refusal that names the role it needs keeps those words on screen; one that names no role becomes the general sentence', async () => {
  const { plainError } = await import('../../src/lib/errors.js')
  expect(plainError({ message: LIVE.AER_PA })).toContain('Platform Admin role required: AER items are admitted or rejected by the Platform Admin')
  expect(plainError({ message: LIVE.AER_PA_ONLY })).toBe('Platform Admin role required.')
  expect(plainError({ message: 'curator role required' })).toBe('curator role required.')
  expect(plainError({ message: LIVE.PIM_FLOOR })).toContain('raises it with the PIM Admin')
  expect(plainError({ message: 'permission denied for table course_fees' })).toBe('Your role is not allowed to do this.')
})

const menu = (page) => page.locator('nav[aria-label="Main menu"]')
const handoff = (page) => page.locator('[data-handoff]')

test.describe('mocked browser', () => {
  test('Viewer (1): finds a requirement and its quote; no edit controls; the stored copy and Layer 4 are refused with who to ask', async ({ page }) => {
    await asRole(page, 1)
    const aer = await mockAer(page, 1)
    await page.goto('/#entry-requirements')
    await expect(menu(page)).toContainText('Courses')
    await expect(menu(page)).toContainText('Entry requirements')
    for (const hidden of ['Layer 4 Review', 'Evidence', 'Scheduled jobs', 'Settings', 'Users & roles']) await expect(menu(page)).not.toContainText(hidden)
    await expect(page.getByText('CBSE Year 12').first()).toBeVisible()
    await expect(page.locator('[data-aer-edit-toggle]')).toHaveCount(0)
    await expect(page.locator('[data-aer-add]')).toHaveCount(0)
    await page.getByText('CBSE Year 12').first().click()
    const drawer = page.locator('[data-aer-drawer="matrix"]')
    await expect(drawer.locator('[data-aer-quote]')).toContainText('CBSE Year 12 | 65% | 75%')
    await expect(drawer.locator('[data-aer-lifecycle]')).toHaveCount(0)
    // the restricted stored copy: the link leads to a page that says who may open it, not a bare refusal
    await drawer.getByText('Open the stored copy').click()
    await expect(page.getByText('Not authorised')).toBeVisible()
    await expect(handoff(page)).toContainText('Evidence opens from Curator (rank 3)')
    await expect(handoff(page)).toContainText('Ask a Curator')
    await page.goto('/#layer-4-review')
    await expect(handoff(page)).toContainText('Layer 4 Review opens from Curator (rank 3)')
    expect(aer.some((c) => ['update', 'add', 'lifecycle', 'reread'].includes(c.action))).toBe(false)
  })

  test('Counsellor (2): reads courses, contacts and the guide\'s counsellor tasks; Layer 4 and Evidence are a Curator\'s', async ({ page }) => {
    await asRole(page, 2)
    await page.goto('/#platform-guide')
    await expect(page.locator('[data-guide-role="2"]')).toContainText('Your role: Counsellor')
    await expect(page.locator('[data-guide-role="2"]')).toContainText('report it from the record in Zoho')
    for (const shown of ['Courses', 'Provider contacts', 'Entry requirements', 'Rankings & statistics']) await expect(menu(page)).toContainText(shown)
    for (const hidden of ['Layer 4 Review', 'Evidence', 'Scheduled jobs']) await expect(menu(page)).not.toContainText(hidden)
    // the SOP tabs need a Curator: the address falls back to the Platform guide and says so
    await page.goto('/#platform-guide?tab=operator-sop')
    await expect(page.locator('[data-platform-guide]')).toBeVisible()
    await expect(page.locator('[data-tab-handoff]')).toContainText('Guides › Operator SOP opens from Curator (rank 3)')
    await page.goto('/#evidence')
    await expect(handoff(page)).toContainText('Evidence opens from Curator (rank 3)')
  })

  test('Curator (3): withdraws an active row with a reason; reads AER but cannot decide it; value choices name the Pipeline Operator', async ({ page }) => {
    await asRole(page, 3)
    const aer = await mockAer(page, 3)
    await page.goto('/#entry-requirements')
    await page.getByText('CBSE Year 12').first().click()
    const drawer = page.locator('[data-aer-drawer="matrix"]')
    await drawer.locator('[data-po-action="aer-withdraw"]').click()
    await page.getByLabel('Reason: Withdraw').fill('superseded by the 2028 table')
    await page.locator('[data-po-confirm="aer-withdraw"]').click()
    await expect(drawer).toContainText('Withdrawn. It no longer reaches the website.')
    expect(aer.filter((c) => c.action === 'lifecycle').at(-1).args).toMatchObject({ lifecycle: 'withdraw', reason: 'superseded by the 2028 table', expected_updated_at: '2026-10-27T10:00:00.123456+00:00' })

    const calls = await mockInbox(page, 3)
    await page.goto('/#layer-4-review?kind=aer_review')
    const aerItem = page.locator('[data-l4-item="aer_review"]')
    await expect(aerItem.locator('[data-l4-aer-pa-only]')).toContainText('by the Platform Admin')
    for (const c of ['approve', 'approve_except', 'reject']) await expect(aerItem.locator(`[data-l4-choice="${c}"]`)).toBeDisabled()
    // live: a choice without its own rank needs rank 4 (coalesce(rank, 4)); the card must not offer it to a Curator
    await page.goto('/#layer-4-review?kind=course_link')
    const link = page.locator('[data-l4-item="course_link"]')
    for (const c of ['use', 'enter', 'keep']) await expect(link.locator(`[data-l4-choice="${c}"]`)).toBeDisabled()
    await expect(link.locator('[data-l4-handoff]')).toContainText('Pipeline Operator (rank 4)')
    // the record link still opens: a Curator corrects the course itself
    await expect(page.locator('[data-l4-item="course_link"] [data-l4-open-record]')).toHaveCount(1)
    expect(calls.some((c) => c.p_action === 'decide')).toBe(false)
    // Scheduled jobs are an Operator's
    await expect(menu(page)).not.toContainText('Scheduled jobs')
  })

  test('Pipeline Operator (4): settles a course link; views automations without controls; pause refused with the PIM Admin named; Settings is the Platform Admin\'s', async ({ page }) => {
    await asRole(page, 4)
    const calls = await mockInbox(page, 4)
    await page.goto('/#layer-4-review?kind=course_link')
    const link = page.locator('[data-l4-item="course_link"]')
    await link.locator('[data-l4-choice="keep"]').click()
    await link.getByLabel('Reason').fill('the held page is the course page')
    await link.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status').filter({ hasText: 'Done.' })).toContainText('Done. Applied')
    expect(calls.filter((c) => c.p_action === 'decide')).toHaveLength(1)
    await page.goto('/#layer-4-review?kind=website_needed')
    const site = page.locator('[data-l4-item="website_needed"]')
    await expect(site.locator('[data-l4-choice="archive"]')).toBeDisabled()
    await expect(site.locator('[data-l4-handoff]')).toContainText('PIM Admin (rank 5)')

    const auto = await mockAutomations(page, 4)
    await page.goto('/#scheduled-jobs')
    await expect(page.getByText('You can view automations. Each one names the role that changes it (PIM Admin or Platform Admin)')).toBeVisible()
    await expect(page.locator('tr[data-job="coverage-read"]')).toBeVisible()
    await expect(page.getByRole('button', { name: /Pause|Resume/ })).toHaveCount(0)
    // a pause reaching the server anyway (an old tab, a script) is refused with the live words, and the banner keeps the owner
    await page.evaluate(async () => { const { supabase } = await import('/src/lib/supabase.js'); window.__r = await supabase.rpc('admin_automation_control', { p_job: 'coverage-read', p_action: 'pause', p_args: {} }) })
    expect(await page.evaluate(() => window.__r.error.message)).toBe(LIVE.PIM_FLOOR)
    expect(auto.calls).toHaveLength(1)
    const { plainError } = await import('../../src/lib/errors.js')
    expect(plainError({ message: LIVE.PIM_FLOOR })).toContain('raises it with the PIM Admin')
    await page.goto('/#environment?tab=settings')
    await expect(page.locator('[data-tab-handoff]')).toContainText('Settings › Settings opens from Platform Admin (rank 6)')
  })

  test('PIM Admin (5): pauses and resumes a rank-5 automation; a Platform Admin automation shows its owner; a stale control is refused', async ({ page }) => {
    await asRole(page, 5)
    const auto = await mockAutomations(page, 5, { staleRank: { 'consumer-api-guard': 5 } })
    page.on('dialog', (d) => d.accept())
    await page.goto('/#scheduled-jobs')
    const row = page.locator('tr[data-job="coverage-read"]')
    await row.getByRole('button', { name: 'Pause' }).click()
    await expect(row).toContainText('Paused')
    await row.getByRole('button', { name: 'Resume' }).click()
    await expect(row).toContainText('Running')
    expect(auto.calls.map((c) => `${c.p_job}:${c.p_action}`)).toEqual(['coverage-read:pause', 'coverage-read:resume'])
    // the read was stale (control_rank 5 shown, 6 on the server): the server refuses and nothing changes
    await page.locator('tr[data-job="consumer-api-guard"]').getByRole('button', { name: 'Pause' }).click()
    await expect(page.locator('[data-global-error]')).toContainText('this automation is changed by the Platform Admin')
    expect(auto.jobs.find((j) => j.job === 'consumer-api-guard').active).toBe(true)
    // the builder tab is the PIM Admin's; Settings › Settings and Users are the Platform Admin's
    await page.goto('/#layer-2-discovery?tab=builder')
    await expect(page.locator('[data-tab-handoff]')).toHaveCount(0)
    await page.goto('/#environment?tab=backup')
    await expect(page.locator('[data-tab-handoff]')).toContainText('Settings › Backup & restore opens from Platform Admin (rank 6)')
    await page.goto('/#users-roles')
    await expect(handoff(page)).toContainText('Users & roles opens from Platform Admin (rank 6)')
  })

  test('PIM Admin (5): an automation marked for the Platform Admin names its owner instead of offering controls', async ({ page }) => {
    await asRole(page, 5)
    await mockAutomations(page, 5)
    await page.goto('/#scheduled-jobs')
    const row = page.locator('tr[data-job="consumer-api-guard"]')
    await expect(row).toContainText('Platform Admin only')
    await expect(row.getByRole('button')).toHaveCount(0)
  })

  test('Platform Admin (6): approves an AER item and sees the destination outcome and audit; every page opens with no handoff', async ({ page }) => {
    await asRole(page, 6)
    const calls = await mockInbox(page, 6)
    await page.goto('/#layer-4-review?kind=aer_review')
    const item = page.locator('[data-l4-item="aer_review"]')
    await expect(item.locator('[data-l4-handoff]')).toHaveCount(0)
    await item.locator('[data-l4-choice="approve"]').click()
    await item.getByLabel('Reason').fill('every row is printed on the stored copy')
    await item.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status').filter({ hasText: 'Done.' })).toContainText('Done. Admitted · rows 2 active · decision dec00001 · audit #41001')
    expect(calls.filter((c) => c.p_action === 'decide')[0].p_args).toMatchObject({ kind: 'aer_review', choice: 'approve' })
    for (const addr of ['#platform-health', '#environment?tab=backup', '#environment', '#users-roles', '#environment-migration']) {
      await page.goto('/' + addr)
      await expect(page.locator('[data-tab-handoff]')).toHaveCount(0)
      await expect(page.getByText('Not authorised')).toHaveCount(0)
    }
  })
})
