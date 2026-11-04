// Guards: Platform Admin decision 5 Nov 2026 (intake recovery and process accountability) §6, §8: Layer 2/3 Operations › Process results shows saved results only, the reasons and next actions, the next revisit, set-aside calendars and evidence for validation, with Measure now for Operators.
import { test, expect } from '@playwright/test'

const uni = {
  provider_id: '22657140-1cb0-4fa7-91df-90518ea8b35b', university: 'UNSW Sydney', active_courses: 667, courses_with_intakes: 467, intake_rows: 1310, course_pages_stored: 463,
  calendars_approved: 3, calendars_valid: 2, calendars_set_aside: [{ url: 'https://www.unswglobal.unsw.edu.au/study/key-dates', scope: 'excluded_by_address', reason: 'the address names another campus, college, exchange or pathway calendar' }],
  calendar_latest_year: 2028, calendar_freshest: '2026-11-05T01:00:00Z', future_periods: 5, future_dated_starts: 3, future_deadlines: 1,
  held: { month: 1310, year: 626, start_date: 41, application_deadline: 7 }, in_website_source: { year: 626, start_date: 41, application_deadline: 7 },
  outcomes: { complete: 7, evidence_ambiguous: 79, course_identity_unresolved: 147 },
  reasons: [{ next_action: 'course_identity_unresolved', reason: "page not proved to be the course's own (E16 refuse)", rows: 123 }, { next_action: 'evidence_ambiguous', reason: 'several study periods start in this month (month only)', rows: 79 }],
  never_examined: 448, last_attempt: '2026-11-05T00:26:00Z', next_revisit: '2026-11-19T00:26:00Z', waiting_for_change_only: 79, admitted_7_days: { year: 0, start_date: 41, application_deadline: 7 },
  calendar_reread: { dated_by_parser: 1, read_by_ai: 2 }, reader_findings_open: 1, ai_cost_usd_7_days: 0.0123, firecrawl_credits: 0,
}
const latest = { id: 7, measured_at: '2026-11-05T01:53:00Z', measured_by: 'job process-results', summary: { process: 'intake-dates', universities: [uni],
  jobs: { enabled: true, batch: 200, month_unique_match: 1, revisit_days: 14, intake_dates_apply: { schedule: '26 * * * *', last_run: { at: '2026-11-05T01:26:00Z', status: 'succeeded' }, last_success: '2026-11-05T01:26:00Z' }, calendar_reread: { schedule: '13 * * * *', last_run: { at: '2026-11-05T01:13:00Z', status: 'succeeded' } } },
  totals: { active_courses: 667, course_pages_stored: 463, calendars_valid: 2, future_periods: 5, intake_rows: 1310, held_year: 626, held_start_date: 41, held_application_deadline: 7, website_start_date: 41, never_examined: 448 } } }
const detail = {
  calendars: [{ proposal_id: 'p1', url: 'https://www.unsw.edu.au/student/managing-your-studies/key-dates/academic-calendar', used: true, parser: 'ai:gpt-4.1-mini:calendar-v2', decided_at: '2026-11-05T01:00:00Z', evidence_id: 'e1',
    starts: [{ period: 'term 1', date: '2027-02-15', year: 2027, month: 2, quote: 'Term 1 2027 | 15 February – 4 May' }], deadlines: [{ period: 'term 1', date: '2026-12-01', applies_to: 'international', quote: '1 December 2026 | International applications close' }] }],
  reread: [], findings: [{ code: 'next_year_missing', detail: 'no teaching start after 2027', example: 'Term 3 2027', times: 1 }], flags: [],
  recent: [{ run_at: '2026-11-05T01:26:00Z', course_title: 'Bachelor of Actuarial Studies', course_url: 'https://www.unsw.edu.au/study/undergraduate/bachelor-of-actuarial-studies', outcome: 'filled', reason: null, next_action: 'complete', rule: 'calendar-v3',
    before: { year: 2027, start_date: null }, after: { year: 2027, start_date: '2027-02-15' }, page_quote: 'Term 1, Term 2, Term 3', start_quote: 'Term 1 2027 | 15 February – 4 May', calendar_url: 'https://www.unsw.edu.au/student/managing-your-studies/key-dates/academic-calendar', bounded: false }],
}
async function mount(page, rank = 6) {
  await page.goto('/')
  await page.evaluate(async ({ rank, latest, detail }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: ProcessResults } = await import('/src/ProcessResults.jsx')
    window.calls = []
    const client = { async read(view, args) { window.calls.push({ view, args }); if (view === 'latest') return latest; if (view === 'university') return detail; if (view === 'measure') return { id: 8 }; if (view === 'history') return [{ id: 7, measured_at: latest.measured_at, totals: latest.summary.totals }]; return null } }
    document.body.innerHTML = '<div id="pr-root"></div>'
    ReactDOM.createRoot(document.getElementById('pr-root')).render(React.default.createElement(ProcessResults, { client, rank }))
  }, { rank, latest, detail })
  await expect(page.getByRole('heading', { name: 'Process results' })).toBeVisible()
}

test('saved results: what it did, how many, what was missed and why, the next revisit and set-aside calendars', async ({ page }) => {
  await mount(page)
  await expect(page.getByText('job process-results', { exact: false })).toBeVisible()
  await expect(page.getByText(/UNSW Sydney.*start dates 41 of 1,310 intake rows/)).toBeVisible()
  await page.getByText(/UNSW Sydney.*start dates/).click()
  await expect(page.getByText('Course identity unresolved')).toBeVisible()
  await expect(page.getByText("page not proved to be the course's own (E16 refuse) — 123 rows")).toBeVisible()
  await expect(page.getByText('several study periods start in this month (month only) — 79 rows')).toBeVisible()
  await expect(page.getByRole('link', { name: 'https://www.unswglobal.unsw.edu.au/study/key-dates' })).toBeVisible()
  await expect(page.getByText(/next timed revisit/)).toBeVisible()
  expect(await page.evaluate(() => window.calls.map(c => c.view))).toEqual(['latest'])
})

test('validation from the screen: calendars with quotes, reader findings and recent decisions with before, after and evidence', async ({ page }) => {
  await mount(page)
  await page.getByText(/UNSW Sydney.*start dates/).click()
  await page.getByRole('button', { name: 'Show calendars and recent decisions' }).click()
  await expect(page.getByText('Term 1 2027 | 15 February – 4 May').first()).toBeVisible()
  await expect(page.getByText('1 December 2026 | International applications close')).toBeVisible()
  await expect(page.getByText(/next year missing: no teaching start after 2027/)).toBeVisible()
  await expect(page.getByText('Bachelor of Actuarial Studies')).toBeVisible()
  await expect(page.getByText('{"year":2027,"start_date":"2027-02-15"}')).toBeVisible()
  expect(await page.evaluate(() => window.calls.at(-1))).toEqual({ view: 'university', args: { provider_id: '22657140-1cb0-4fa7-91df-90518ea8b35b' } })
})

test('Measure now is for Operators and above; a read-only role sees saved results only', async ({ page }) => {
  await mount(page, 3)
  await expect(page.getByRole('button', { name: 'Measure now' })).toHaveCount(0)
  await mount(page, 4)
  await page.getByRole('button', { name: 'Measure now' }).click()
  await expect.poll(() => page.evaluate(() => window.calls.map(c => c.view))).toEqual(['latest', 'measure', 'latest'])
})

test('the browser bridge calls only the role-checked saved-results function', async ({ page }) => {
  await page.goto('/')
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => { calls.push({ url: route.request().url(), body: route.request().postDataJSON() }); await route.fulfill({ json: null }) })
  await page.evaluate(async () => { const { processResultsApi } = await import('/src/process-results-api.js'); await processResultsApi.read('latest', { process: 'intake-dates' }) })
  expect(calls).toEqual([{ url: 'https://example.supabase.co/rest/v1/rpc/admin_process_results_v1', body: { p_view: 'latest', p_args: { process: 'intake-dates' } } }])
})

test("phone: process results and a university's evidence without page overflow @responsive", async ({ page }) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await mount(page)
  await page.getByText(/UNSW Sydney.*start dates/).click()
  await page.getByRole('button', { name: 'Show calendars and recent decisions' }).click()
  await expect(page.getByText('Bachelor of Actuarial Studies')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})
