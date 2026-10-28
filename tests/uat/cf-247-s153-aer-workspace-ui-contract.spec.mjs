// Guards: CF-247 AER operations workspace UI (Platform Admin mandate 29 Oct 2026 08:06; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W1-W3, W16): Catalogue › Entry requirements with four views, the summary pills, combined filters, the Columns menu, the shared table and drawer, Edit in list with a session reason and the row as read, stale and validation refusals shown, lifecycle with reasons, a Layer 4 link instead of editing a proposed row, bounded source re-read, and the resolution inspector; the drawer sections are read-only shortcuts; no direct table access
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const ui = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')
const nav = fs.readFileSync('src/nav-map.js', 'utf8')
const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
const drawer = fs.readFileSync('src/EntryRequirements.jsx', 'utf8')

test('one menu destination with four views, beside Scholarships; one editing implementation; every write through admin_aer', () => {
  expect(nav).toContain("entry: { label: 'Entry requirements', slug: 'entry-requirements', icon: 'entry'")
  for (const t of ["{ key: 'matrix', label: 'Provider entry matrix', min: 1 }", "{ key: 'course', label: 'Course entry requirements', min: 1 }", "{ key: 'sources', label: 'Sources, reads and holds', min: 1 }", "{ key: 'resolve', label: 'Resolution inspection', min: 1 }"]) expect(nav).toContain(t)
  expect(nav).toContain("pages: ['courses', 'providers', 'contacts', 'scholarships', 'entry', 'rankings', 'reference']")
  expect(main).toContain("case'entry':return <AerWorkspace tab={tab} rank={rank} onError={onError} navigate={navigate} routeParams={routeParams}/>")
  expect(ui).toContain("supabase.rpc('admin_aer',{p_action:action,p_args:args})")
  expect(ui).not.toMatch(/supabase\.from\(/)
  expect(ui).toContain("import{DataTable,FilterSelect}from'./DataTable'")
  // the drawer sections stay read-only and lead into the workspace
  expect(drawer).toContain("href={hrefFor('entry','',{provider:providerId})} data-entry-workspace-link>Open in Entry requirements</a>")
  expect(drawer).toContain("href={hrefFor('entry','course',{course:courseId})} data-entry-workspace-link>Open in Entry requirements</a>")
  expect(drawer).not.toMatch(/admin_aer|'update'|'lifecycle'/)
  // pills carry words, never colour alone
  expect(ui).toContain("export const ROW_PILL={active:['success','Active'],proposed:['info','Waiting in Layer 4'],unverified:['danger','Quarantined'],inactive:['neutral','Withdrawn'],superseded:['neutral','Superseded']}")
  expect(ui).toContain("export const HOLD_PILL={read:['success','Read'],reading:['info','Reading'],held:['warning','Held'],fetch_failed:['danger','Fetch failed'],none:['neutral','Not read']}")
})

test('the deployed acceptance runs on deploy: targeted for workspace changes and in the acceptance tier; live edits held by the live-acting switch', () => {
  const wf = fs.readFileSync('.github/workflows/deployed-uat.yml', 'utf8')
  expect(wf).toContain("grep -Eq '(^src/(AerWorkspace\\.jsx|aer-workspace\\.css|DataTable\\.jsx)$|^supabase/migrations/.*_cf247_aer_workspace|^tests/uat/cf-247-s154-aer-workspace-deployed\\.spec\\.mjs$)'; then\n            targeted=(tests/uat/cf-247-s154-aer-workspace-deployed.spec.mjs)")
  expect(wf).toContain('            tests/uat/cf-247-s154-aer-workspace-deployed.spec.mjs\n          )\n          case')
  const dep = fs.readFileSync('tests/uat/cf-247-s154-aer-workspace-deployed.spec.mjs', 'utf8')
  expect(dep).toContain("test.describe('CF-247 AER operations workspace @deployed'")
  expect(dep).toContain("test('a governed edit of a live active row, its history and version, then put back @live-acting'")
})

const row = (o = {}) => ({ kind: 'matrix', id: 'm1', provider_id: 'p-rmit', provider_name: 'RMIT University (RMIT)', country: 'IN', country_name: 'India', level_label: 'Bachelor degrees', level_code: 'BA',
  level_name: 'Bachelor', matrix_kind: 'band_ladder', qualification: 'CBSE Year 12', band: '65%', min_grade: '75%', min_value: null, scale: 'percentage', conditions: { best_n: 4, subject_minimums: [], alternatives: [] },
  audience: 'international', edition: '2027', intake_year: null, as_at: '2026-10-26', status: 'active', status_reason: null, quote: 'CBSE Year 12 | 65% | 75%', source_url: 'https://www.rmit.edu.au/india',
  evidence_id: 'ev1', version: 3, manual: false, run_id: 'r1', review_item_id: 'li1', review_status: 'approved', created_at: '2026-10-26T10:00:00Z', updated_at: '2026-10-27T10:00:00.123456+00:00', ...o })

async function mockAer(page, { rank = 6 } = {}) {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { rank })
  const calls = []; page.aerCalls = calls
  let current = row()
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer', async route => {
    const b = route.request().postDataJSON() || {}, a = b.p_args || {}
    calls.push({ action: b.p_action, args: a })
    const j = json => route.fulfill({ json })
    if (b.p_action === 'summary') return j({ matrix: { active: 343, proposed: 776, unverified: 20, inactive: 4, superseded: 171 }, course: { proposed: 3 }, sources: { total: 102, held: 15, fetch_failed: 3, reading: 2, read: 84 }, courses_with_active: 0, courses_waiting: 1, can_edit: true, can_reread: rank >= 6 })
    if (b.p_action === 'options') return j({ providers: [{ id: 'p-rmit', name: 'RMIT University (RMIT)' }, { id: 'p-uts', name: 'University of Technology Sydney (UTS)' }], countries: [{ code: 'IN', name: 'India' }, { code: 'NP', name: 'Nepal' }], all_countries: [{ code: 'IN', name: 'India' }, { code: 'NP', name: 'Nepal' }],
      levels: [{ code: 'BA', name: 'Bachelor' }], level_labels: ['Bachelor degrees'], bands: ['65%', '70%'], editions: ['2027'], intake_years: [2027], matrix_kinds: ['provider_minimum', 'band_ladder'], requirement_kinds: ['minimum_grade', 'override'], scales: ['percentage', 'points', 'none'], audiences: ['international', 'domestic', 'all'], statuses: ['active', 'proposed', 'unverified', 'inactive', 'superseded'] })
    if (b.p_action === 'matrix_list') return j({ total: 2, offset: a.offset || 0, page_size: 50, rows: [current, row({ id: 'm2', status: 'proposed', qualification: 'ISC Year 12', review_status: 'pending', updated_at: '2026-10-28T10:00:00+00:00' })] })
    if (b.p_action === 'row') return j({ ...current, evidence: { id: 'ev1', source_url: current.source_url, captured_at: '2026-10-26T09:00:00Z', mime: 'text/html', stored: true, content_hash: 'abc123' }, run: { id: 'r1', state: 'done', model: 'gpt-4.1-mini', worker: 'coverage-sweep-worker-v0.48.8', basis: 'table-rows-v1', cost_usd: 0.004 },
      history: [{ at: '2026-10-29T08:00:00Z', field: 'edition', action: 'edit', before: '2026', after: '2027', reason: 'corrected from the 2027 table', actor: 'curator@example.test' }], can_edit: current.status === 'active', can_restore: current.status === 'inactive' })
    if (b.p_action === 'update') {
      if (a.expected_updated_at !== current.updated_at) return route.fulfill({ status: 400, json: { code: '40001', message: 'this row was changed by someone else since you opened it; reload and try again' } })
      if (a.changes?.band && !current.quote.includes(a.changes.band)) return route.fulfill({ status: 400, json: { code: '22023', message: `the band "${a.changes.band}" is not printed in the row's quote` } })
      current = { ...current, ...Object.fromEntries(Object.entries(a.changes || {}).map(([k, v]) => [k, v])), version: current.version + 1, updated_at: '2026-10-29T09:00:00.000001+00:00' }
      return j({ ok: true, row: current, changed: 1 })
    }
    if (b.p_action === 'lifecycle') { current = { ...current, status: a.lifecycle === 'withdraw' ? 'inactive' : a.lifecycle === 'quarantine' ? 'unverified' : 'active', updated_at: '2026-10-29T09:30:00+00:00' }; return j({ ok: true, row: current, changed: 1 }) }
    if (b.p_action === 'course_list') return j({ total: 1, rows: [{ kind: 'course', id: 'c1', course_id: 'k1', course_title: 'Bachelor of Engineering (Honours)', course_code: '0100714', provider_id: 'p-rmit', provider_name: 'RMIT University (RMIT)', requirement_kind: 'minimum_grade', audience: 'domestic', description: '2026 ATAR 73.00', min_grade: '73', status: 'proposed', quote: '2026 ATAR 73.00', source_url: 'https://www.rmit.edu.au/bh126', as_at: '2026-10-28', updated_at: '2026-10-28T11:00:00+00:00' }] })
    if (b.p_action === 'sources_list') return j({ total: 2, can_reread: rank >= 6, ai_allowed: true, rows: [
      { id: 's1', provider_id: 'p-uts', provider_name: 'University of Technology Sydney (UTS)', url: 'https://www.uts.edu.au/entry', type: 'Web page', status: 'read', read_via: 'direct', in_scope: true, hold_state: 'read', evidence_id: 'ev2', captured_at: '2026-10-28T10:00:00Z', content_hash: 'deadbeef', last_success: '2026-10-28T10:05:00Z', next_refresh: '2026-11-27T10:00:00Z', run: { id: 'r2', state: 'done', attempts: 1, rows: 40, not_kept: 5, cost_usd: 0.021, review_item_id: 'li2', review_status: 'pending', dropped: { quote_not_on_page: 2 } } },
      { id: 's2', provider_id: 'p-uoa', provider_name: 'University of Auckland', url: 'https://www.auckland.ac.nz/a-i.pdf', type: 'PDF', status: 'read', read_via: 'direct', in_scope: true, hold_state: 'held', run: { id: 'r3', state: 'failed', attempts: 1, error: 'held_unparsed: PDF page 2: "for secondary qualifications" crosses a column edge' } }] })
    if (b.p_action === 'reread') return j({ ok: true, runs: 1 })
    if (b.p_action === 'course_search') return j([{ id: 'k1', title: 'Bachelor of Engineering (Honours)', code: '0100714', provider: 'RMIT University (RMIT)', provider_id: 'p-rmit' }])
    if (b.p_action === 'resolve') return j({ course: { id: 'k1', title: 'Bachelor of Engineering (Honours)', code: '0100714', provider: 'RMIT University (RMIT)', level: 'BH' },
      resolution: { country: 'IN', step: 5, rule: 'contact_provider', outcome: 'contact_provider', rows: [], note: 'The provider publishes a band table for this country, but the course page prints no band to enter it with.' },
      steps: [{ step: 1, rule: 'course_override', active_rows: 0 }, { step: 2, rule: 'course_country_row', active_rows: 0 }, { step: 3, rule: 'band_ladder', band: null, active_rows: 0, band_table_rows: 18 }, { step: 4, rule: 'provider_minimum', active_rows: 0 }, { step: 5, rule: 'contact_provider', active_rows: 0 }],
      not_used: { proposed_matrix: 0, unverified_matrix: 0, proposed_course: 3, levels: ['BA', 'BH'] } })
    return j({})
  })
  return calls
}

test.describe('mocked browser', () => {
  test('Provider entry matrix: summary pills, combined filters, columns, drawer with history, edit in list, refusals shown, withdraw', async ({ page }) => {
    const errors = []; page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|favicon/.test(m.text())) errors.push(m.text()) })
    const calls = await mockAer(page)
    await page.goto('/#entry-requirements')
    await expect(page.getByRole('tab', { name: 'Provider entry matrix' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator('[data-aer-tile="active"]')).toContainText('343')
    await expect(page.locator('[data-aer-tile="proposed"]')).toContainText('Waiting in Layer 4')
    await expect(page.locator('[data-aer-tile="quarantined"]')).toContainText('20')
    await expect(page.locator('[data-aer-tile="held"]')).toContainText('18')
    // combined filters: provider + country + band, sent together and shown as chips; clear resets
    const bar = page.locator('[data-aer-filters="matrix"]')
    await bar.getByRole('button', { name: /Provider/ }).click(); await page.getByRole('button', { name: 'RMIT University (RMIT)' }).click()
    await bar.getByRole('button', { name: /Country/ }).click(); await page.locator('.m-filter-popover').getByRole('button', { name: /India/ }).click()
    await bar.getByRole('button', { name: /Band/ }).click(); await page.locator('.m-filter-popover').getByRole('button', { name: '65%' }).click()
    await expect.poll(() => calls.filter(c => c.action === 'matrix_list').at(-1)?.args).toMatchObject({ provider_id: 'p-rmit', country: 'IN', band: '65%', status: 'active', page_size: 50 })
    await expect(page.locator('[data-aer-chips]')).toContainText('Country: India')
    // sorting goes to the server
    await page.locator('table[data-table="aer-matrix"] th button', { hasText: 'Qualification' }).click()
    await expect.poll(() => calls.filter(c => c.action === 'matrix_list').at(-1)?.args?.sort).toBe('qualification')
    // columns: hide Quote, the table no longer shows it
    await page.locator('[data-aer-columns] summary').click(); await page.locator('[data-aer-col="quote"]').uncheck()
    await expect(page.locator('table[data-table="aer-matrix"] thead')).not.toContainText('Quote')
    await page.locator('[data-aer-columns] summary').click()
    // pills read as words; a proposed row links to Layer 4
    await expect(page.locator('[data-aer-pill="active"]').first()).toContainText('Active')
    await expect(page.locator('[data-aer-pill="proposed"]').first()).toContainText('Waiting in Layer 4')
    // the drawer: full quote, stored copy, reading run, history with before and after
    await page.getByText('CBSE Year 12').first().click()
    const d = page.locator('[data-aer-drawer="matrix"]')
    await expect(d.locator('[data-aer-quote]')).toContainText('CBSE Year 12 | 65% | 75%')
    await expect(d).toContainText('Open the stored copy')
    await expect(d.locator('[data-aer-history]')).toContainText('corrected from the 2027 table')
    await expect(d.locator('[data-aer-l4]')).toBeVisible()
    await d.getByRole('button', { name: 'Close detail' }).click()
    // Edit in list: no save without a session reason; then a save carries the reason and the row as read
    await page.locator('[data-aer-edit-toggle]').click()
    const edit = page.locator('[data-aer-edit="matrix"]')
    await edit.locator('[data-edit-row="m1"] [data-aer-cell="edition"]').click()
    await edit.getByLabel(/Edition for/).fill('2028'); await edit.getByLabel(/Edition for/).press('Enter')
    await expect(edit.locator('[data-aer-row-error]')).toContainText('Give a reason')
    await edit.locator('[data-aer-reason]').fill('corrected from the provider 2028 table')
    await edit.getByLabel(/Edition for/).press('Enter')
    await expect.poll(() => calls.filter(c => c.action === 'update').at(-1)?.args).toMatchObject({ kind: 'matrix', id: 'm1', reason: 'corrected from the provider 2028 table', expected_updated_at: '2026-10-27T10:00:00.123456+00:00', changes: { edition: '2028' } })
    await expect(edit.locator('[data-edit-row="m1"] [data-aer-cell="edition"]')).toContainText('2028')
    // a band not printed in the quote is refused and the refusal is shown under the row
    await edit.locator('[data-edit-row="m1"] [data-aer-cell="band"]').click()
    await edit.getByLabel(/Band for/).fill('99%'); await edit.getByLabel(/Band for/).press('Enter')
    await expect(edit.locator('[data-aer-row-error]')).toContainText('not printed in the row')
    await edit.getByLabel(/Band for/).press('Escape')
    // the proposed row is not editable in the list
    await expect(edit.locator('[data-edit-row="m2"] [data-aer-cell]')).toHaveCount(0)
    await page.locator('[data-aer-edit-toggle]').click()
    // withdraw with a reason from the drawer
    await page.getByText('CBSE Year 12').first().click()
    await page.locator('[data-po-action="aer-withdraw"]').click()
    await page.getByLabel('Reason: Withdraw').fill('superseded by the 2028 table')
    await page.locator('[data-po-confirm="aer-withdraw"]').click()
    await expect.poll(() => calls.filter(c => c.action === 'lifecycle').at(-1)?.args).toMatchObject({ lifecycle: 'withdraw', reason: 'superseded by the 2028 table', id: 'm1' })
    await expect(page.locator('[data-aer-drawer="matrix"]')).toContainText('Withdrawn. It no longer reaches the website.')
    expect(calls.every(c => c.action !== 'matrix_list' || Number(c.args.page_size) <= 100)).toBe(true)
    expect(errors).toEqual([])
  })

  test('Course requirements, sources and resolution inspection; re-read bounded and never past a terminal hold', async ({ page }) => {
    const calls = await mockAer(page)
    await page.goto('/#entry-requirements?tab=course')
    await expect(page.locator('[data-aer-view="course"]')).toContainText('Bachelor of Engineering (Honours)')
    await expect(page.locator('[data-aer-pill="proposed"]').first()).toContainText('Waiting in Layer 4')
    await page.getByLabel('Course title or code').fill('0100714')
    await expect.poll(() => calls.filter(c => c.action === 'course_list').at(-1)?.args?.course).toBe('0100714')
    await page.goto('/#entry-requirements?tab=sources')
    await expect(page.locator('[data-aer-hold="held"]')).toContainText('Held')
    await expect(page.locator('[data-aer-view="sources"]')).toContainText('Held as unreadable')
    await page.locator('[data-po-action="aer-reread"]').first().click()
    await page.getByLabel('Reason: Read again').fill('read again after the reader change')
    await page.locator('[data-po-confirm="aer-reread"]').click()
    await expect.poll(() => calls.filter(c => c.action === 'reread').at(-1)?.args).toMatchObject({ source_id: 's1', reason: 'read again after the reader change' })
    await expect(page.locator('[data-po-action="aer-reread"]')).toHaveCount(1)  // one source, one button; the held PDF has none
    await page.goto('/#entry-requirements?tab=resolve')
    await page.locator('[data-aer-resolve-course]').fill('0100714')
    await page.getByRole('button', { name: /Bachelor of Engineering \(Honours\)/ }).click()
    await page.getByRole('button', { name: /Country of prior education/ }).click(); await page.locator('.m-filter-popover').getByRole('button', { name: /India/ }).click()
    await expect(page.locator('[data-aer-outcome="contact_provider"]')).toContainText('Contact the provider')
    await expect(page.locator('[data-aer-step="3"]')).toContainText('the course prints no band')
    await expect(page.locator('[data-aer-step="5"]')).toContainText('Used')
    await expect(page.locator('[data-aer-not-used]')).toContainText('3 course rows waiting')
  })

  test('a Viewer reads the workspace but has no edit, add, lifecycle or re-read controls', async ({ page }) => {
    await mockAer(page, { rank: 1 })
    await page.goto('/#entry-requirements')
    await expect(page.locator('[data-aer-tile="active"]')).toContainText('343')
    await expect(page.locator('[data-aer-edit-toggle]')).toHaveCount(0)
    await expect(page.locator('[data-aer-add]')).toHaveCount(0)
    await page.getByText('CBSE Year 12').first().click()
    await expect(page.locator('[data-aer-lifecycle]')).toHaveCount(0)
    await page.goto('/#entry-requirements?tab=sources')
    await expect(page.locator('[data-po-action="aer-reread"]')).toHaveCount(0)
  })

  test('phone width: the workspace fits, the table scrolls in its own frame @responsive', async ({ page }) => {
    expect(page.viewportSize().width).toBeLessThan(500)
    await mockAer(page)
    await page.goto('/#entry-requirements')
    await expect(page.locator('[data-aer-tile="active"]')).toBeVisible()
    const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    expect(over).toBeLessThanOrEqual(1)
    await expect(page.locator('[data-aer-view="matrix"] .m-table-wrap')).toBeVisible()
  })
})
