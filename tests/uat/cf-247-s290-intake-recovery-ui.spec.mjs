// Guards: Platform Admin final intake recovery mandate 5 Nov 2026 12:44 §10 and §16: Intake Run & Validate › Process results shows what the recovery admitted and published by university, source type, year and precision, every skipped or failed class with its reason and next look, the calendar refresh credits and yield, the reader and the jobs, from saved results only, on desktop and phone.
import { test, expect } from '@playwright/test'

const recovery = {
  measured_at: '2026-11-05T05:00:00Z', window_since: '2026-10-29T05:00:00Z',
  admitted: [{ university: 'UNSW Sydney', source_type: 'approved calendar', rule: 'calendar-v3', year: 2027, precision: 'day', admitted: 151, with_start_date: 151, with_deadline: 0, published: 150, publication_failed: 1, provider_not_published: 0, not_checked: 0 }],
  classes: [{ university: 'UNSW Sydney', class: 'course_identity_unresolved', deterministic: false, rows: 31, reason: "page not proved to be the course's own (E16 refuse)", next_revisit_at: '2026-11-19T00:26:00Z', revisit_trigger: 'the course page is proved (Course Link) or the revisit date' },
            { university: 'The University of Melbourne', class: 'stale_calendar_edition', deterministic: true, rows: 220, reason: "the calendar prints no start of the named period in the intake's own year", next_revisit_at: null, revisit_trigger: 'a newer calendar edition is stored (calendar refresh or provider facts)' },
            { university: 'UNSW Sydney', class: 'complete', rows: 151 }],
  refresh: { budget: 40, credits_counted: 4, credits_used: 2, requests: [{ university: 'The University of Melbourne', url: 'https://students.unimelb.edu.au/your-course/manage-your-course/key-dates', requested_at: '2026-11-05T04:13:00Z', status: 'new_edition_stored', credits_used: 2, yield: 'next_year_starts', next_year_starts: 4, reason: 'no 2027 start in the stored copy read by calendar-v2.1' }] },
  reader: [{ reader: 'calendar-v2.1', state: 'read_by_ai', documents: 12 }, { reader: 'calendar-v2.1', state: 'no_dates', documents: 480 }],
  jobs: [{ job: 'calendar-reread', schedule: '13 * * * *', last_run: '2026-11-05T04:13:00Z', last_status: 'succeeded' }],
}
async function mount(page) {
  await page.goto('/')
  await page.evaluate(async ({ recovery }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: ProcessResults } = await import('/src/ProcessResults.jsx')
    window.calls = []
    const client = { async read(view, args) { window.calls.push({ view, args }); if (view === 'recovery') return recovery; return null } }
    document.body.innerHTML = '<div id="pr-root"></div>'
    ReactDOM.createRoot(document.getElementById('pr-root')).render(React.default.createElement(ProcessResults, { client, rank: 3 }))
  }, { recovery })
  await expect(page.getByTestId('intake-recovery')).toBeVisible()
}

test('recovery: admitted and published by university, year and precision; classes with reason and next look; refresh credits and yield', async ({ page }) => {
  await mount(page)
  const r = page.getByTestId('intake-recovery')
  await expect(r.getByRole('row', { name: /UNSW Sydney approved calendar \(calendar-v3\) 2027 day 151 151 0 150 1/ })).toBeVisible()
  await expect(r.getByText('Stale calendar edition · waits for a change')).toBeVisible()
  await expect(r.getByText('a newer calendar edition is stored (calendar refresh or provider facts)')).toBeVisible()
  await expect(r.getByText('Course identity unresolved', { exact: true })).toBeVisible()
  await expect(r.getByRole('cell', { name: 'Complete' })).toHaveCount(0)
  await expect(r.getByText('Firecrawl credits counted 4 of 40 (used 2).')).toBeVisible()
  await expect(r.getByText(/new edition stored · yield next year starts \(4 next-year starts\)/)).toBeVisible()
  await expect(r.getByText('calendar-v2.1 · no dates · 480 documents')).toBeVisible()
  expect(await page.evaluate(() => window.calls.map(c => c.view))).toEqual(['latest', 'recovery'])
})

test('phone: the recovery tables scroll inside the panel, never the page @responsive', async ({ page }) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await mount(page)
  await expect(page.getByText('Firecrawl credits counted 4 of 40 (used 2).')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})
