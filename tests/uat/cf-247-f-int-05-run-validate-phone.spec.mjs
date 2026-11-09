// Guards: StudySearch F-INT.05 (Feature Acceptance Contract, 8 Nov 2026: intake Run & Validate tested on a phone with approved operator roles; IQ-00313) and S121/G4 (phone tests are @responsive and first assert phone width). Course intake Run & Validate with a restored saved cohort, mocked client; nothing reaches a real backend. The test does not click Run Now.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121
const COHORT = '11111111-1111-4111-8111-111111111111'
const LONG_URL = 'https://www.example.edu.au/study/courses/undergraduate/bachelor-of-commerce-with-a-very-long-path-to-check-that-an-official-address-wraps-on-a-phone'

const caps = {
  contract: 'intake-run-validate-v1', can_run: true, control_rank: 6, min_size: 1, max_size: 20, default_size: 20,
  scopes: [{ id: 'au-top', label: 'Top Australian universities (approved scope)' }, { id: 'all', label: 'All eligible universities' }],
  universities: [{ id: 'u1', name: 'Deakin University', active_courses: 412 }],
  recent: [{ cohort_id: COHORT, created_at: '2026-11-09T04:00:00Z', reason: 'Bounded cohort for phone acceptance of the intake screen' }],
}
const course = (n, provider) => ({
  course_id: `course-${n}`, course_title: `Bachelor of Commerce and Information Systems (Honours) ${n}`, provider_name: provider, pattern: 'semester', fills: ['year', 'start_date'],
  eligibility_reason: 'Official page shows a 2027 start', course_url: LONG_URL,
  at_selection: [{ intake_id: `i-${n}`, before: { year: null }, planned: { year: 2027 }, page_url: LONG_URL, calendar_url: LONG_URL, page_quote: 'Semester 1 begins in February 2027 on the Burwood campus' }],
  added: [{ intake_id: `i-${n}`, before: { year: null }, after: { year: 2027 } }],
  now: [{ year: 2027 }], website_intakes: [{ year: 2027 }], zoho_intakes: { error: 'Unsupported read-back' }, published: 1,
})
const report = {
  cohort_id: COHORT, as_at: '2026-11-09T04:05:00Z', verdict: 'Admitted 2 of 2.', next_action: 'Verify again after the next publication.',
  totals: { selected: 2, admitted: 2, published: 2, not_as_planned: 0, vendor_calls: 0 },
  saved_request: { scope: 'au-top', size: 2, reason: 'Bounded cohort for phone acceptance of the intake screen', request_key: 'key-1' },
  runs: [{ run_id: 'run-0001-with-a-long-identifier-to-test-wrapping-on-a-phone', state: 'done', processed: 2, admitted: 2, skipped: 0, failed: 0, started_at: '2026-11-09T04:01:00Z', finished_at: '2026-11-09T04:02:00Z' }],
  courses: [course(1, 'Deakin University'), course(2, 'The University of Western Australia')],
}

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, { rank = 6, capabilities = caps } = {}) {
  await page.goto('/')
  await page.evaluate(async ({ c, r, rep }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: Intake } = await import('/src/IntakeRunValidate.jsx')
    window.intakeCalls = []
    const client = {
      async read(view, args) {
        window.intakeCalls.push({ method: 'read', view, args })
        if (view === 'capabilities') return c
        if (view === 'verify') return rep
        if (view === 'preview') return { token: 'p1', courses: rep.courses, eligible_courses: 37, rule: 'Most gaps first', as_at: '2026-11-09T04:00:00Z', expires_at: '2026-11-09T04:10:00Z' }
        return {}
      },
      async prepare(args) { window.intakeCalls.push({ method: 'prepare', args }); return {} },
      async run(...args) { window.intakeCalls.push({ method: 'run', args }); return {} },
    }
    document.body.innerHTML = '<div id="intake-phone-root"></div>'
    ReactDOM.createRoot(document.getElementById('intake-phone-root')).render(React.default.createElement(Intake, { client, rank: r }))
  }, { c: capabilities, r: rank, rep: report })
  await expect(page.getByRole('heading', { name: 'Course intake Run & Validate' })).toBeVisible()
  await expect(page.locator('.intake-course').first()).toBeVisible()
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Course intake Run & Validate on a phone @responsive', () => {
  test('a restored cohort, its stages, evidence and agreement table fit the phone; long addresses wrap; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    await expect(page.locator('[data-stage="validated"]')).toBeVisible()
    for (const sel of ['.intake-run select', '.intake-run input', '.intake-run textarea', '.intake-run button', '.intake-run .cf-link', '.intake-evidence', '.intake-course', '.intake-stages li', '.intake-metrics']) {
      const found = await boxes(page, sel)
      expect(found.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThan(0)
      for (const b of found) {
        expect(b.x, `${sel} "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
        expect(b.right, `${sel} "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
      }
    }
    // the agreement table scrolls inside its own frame, never the page
    const frame = await page.locator('.intake-table-scroll').evaluate((el) => ({ client: el.clientWidth, scroll: el.scrollWidth, overflowX: getComputedStyle(el).overflowX }))
    expect(frame.overflowX, 'the agreement table has its own scroll frame').toBe('auto')
    expect(frame.client, 'the frame fits the phone').toBeLessThanOrEqual(w)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await page.locator('.intake-course details summary').first().click()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control an operator taps on the phone is a tap target of at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['.intake-run button', '.intake-run select', '.intake-run input:not([type=hidden])', '.intake-run textarea', '.intake-run summary', '.intake-run .cf-link']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(15)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('a read-only operator cannot start a run; the saved cohort is still readable and nothing is started', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page, { rank: 3 })
    await expect(page.getByText('Read only: your role or the job controls do not permit Run Now.')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Run Now' })).toBeDisabled()
    await expect(page.getByRole('button', { name: 'Fix previewed cohort' })).toBeDisabled()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    const started = await page.evaluate(() => window.intakeCalls.filter((c) => c.method === 'run' || c.method === 'prepare').length)
    expect(started, 'no run or cohort was started').toBe(0)
  })
})
