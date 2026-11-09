// Guards: StudySearch F-PDESC / F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00313 family) and S121/G4 (phone tests are @responsive and first assert phone width). Provider description Run & Validate, mocked client; nothing reaches a real backend.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121
const P1 = '11111111-1111-4111-8111-111111111111'

const caps = {
  enabled: true, job_active: true, model: 'anthropic/claude-sonnet-4.5', min_size: 1, max_size: 50, default_size: 10, reason_min_chars: 5, control_rank: 5,
  can_run: true, can_explain: true, can_diagnose: false,
  countries: [{ code: 'AU', label: 'Australia' }, { code: 'NZ', label: 'New Zealand' }, { code: 'CA', label: 'Canada' }],
  provider_types: [{ code: 'university', label: 'University' }],
  modes: [{ id: 'reader', label: 'Reader (official About page)' }],
  providers: [{ provider_id: P1, name: 'Curtin University', country: 'AU', type: 'university' }],
  policy: { ai_usd_max: 1, budget_period: 'day', reserved_usd: 0, remaining_usd: 0.9775 },
}
const provider = {
  provider_id: P1, provider: 'Curtin University', type: 'university', country: 'AU', active_course_count: 412, eligible: true, state: 'admitted',
  stable_key: 'au-curtin-university', registration: 'CRICOS 00301J', eligibility_reason: 'official_site_read',
  current_description: 'Curtin University is a public university in Perth, Western Australia, with campuses in Australia and overseas.',
  proposed_description: 'Curtin University is a public university in Perth, Western Australia.',
  source_url: 'https://www.curtin.edu.au/about/who-we-are/the-longest-url-in-the-world-for-checking-wrapping-of-long-source-addresses-on-a-phone',
  sentences: [{ text: 'Curtin University is a public university in Perth.', quote: 'Curtin University is a public university in Perth, Western Australia.', on_page: true }],
  publication: { catalogue: { status: 'verified' }, website: { status: 'verified' }, zoho: { status: 'verified' } },
}
const saved = {
  cohort_id: 'cohort-20261109-0001-with-a-long-identifier-to-test-wrapping', reason: 'Bounded cohort for phone acceptance', created_at: '2026-11-09T04:00:00Z', requested_by: 'platform.admin',
  providers: [provider], runs: [{ run_id: 'run-0001', state: 'succeeded', outcome: 'admitted', started_at: '2026-11-09T04:10:00Z', finished_at: '2026-11-09T04:11:00Z' }],
  totals: { selected: 1, evidence_read: 1, proposed: 1, validation_failed: 0, layer4_created: 0, admitted: 1, website_verified: 1, zoho_verified: 1 },
  can_run: true,
}

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, { rank = 6, savedCohort = saved, capabilities = caps } = {}) {
  await page.goto('/')
  await page.evaluate(async ({ c, s, r }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: ProviderDescriptionRunValidate } = await import('/src/ProviderDescriptionRunValidate.jsx')
    window.pdCalls = []
    const client = {
      async call(name, args) {
        window.pdCalls.push({ name, args })
        if (name === 'capabilities') return c
        if (name === 'saved') return s || { history: [] }
        if (name === 'preview') return { token: 'tok-1', selected: 1, eligible: 3, as_at: '2026-11-09T04:00:00Z', providers: s?.providers || [] }
        return {}
      },
    }
    document.body.innerHTML = '<div id="pd-root"></div>'
    ReactDOM.createRoot(document.getElementById('pd-root')).render(React.default.createElement(ProviderDescriptionRunValidate, { rank: r, client }))
  }, { c: capabilities, s: savedCohort, r: rank })
  await expect(page.locator('[data-provider-description-run-validate]')).toBeVisible()
  await expect(page.getByRole('group', { name: 'Provider scope' })).toBeVisible()
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Provider description Run & Validate on a phone @responsive', () => {
  test('the scope form, saved cohort and provider evidence fit the phone; long identifiers and URLs wrap; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    await expect(page.getByRole('region', { name: 'Saved provider description cohort' })).toContainText('Cohort:')
    await expect(page.locator(`[data-pdesc-provider="${P1}"]`)).toContainText('Curtin University')
    // the saved cohort already has a run, so a second Run Now cannot be started from the phone
    await expect(page.getByRole('button', { name: 'Run Now' })).toBeDisabled()
    for (const sel of ['.pdesc-run select', '.pdesc-run input', '.pdesc-run textarea', '.pdesc-run .cf-btn', '.pdesc-provider', '.pdesc-saved']) {
      const found = await boxes(page, sel)
      expect(found.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThan(0)
      for (const b of found) {
        expect(b.x, `${sel} "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
        expect(b.right, `${sel} "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
      }
    }
    await page.locator(`[data-pdesc-provider="${P1}"] summary`).first().click()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control an operator taps on the phone is a tap target of at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['.pdesc-run button', '.pdesc-run select', '.pdesc-run input:not([type=hidden])', '.pdesc-run summary']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(15)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('a read-only operator is told why they cannot save a cohort; Preview goes to the server with the chosen scope and reads back its summary', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page, { rank: 3, savedCohort: { history: [] } })
    await expect(page.getByText(/Your role can inspect evidence and refresh saved results/)).toBeVisible()
    await expect(page.getByRole('button', { name: 'Save previewed cohort' })).toBeDisabled()
    const preview = page.getByRole('button', { name: 'Preview providers' })
    await preview.scrollIntoViewIfNeeded()
    await preview.click()
    await expect.poll(() => page.evaluate(() => window.pdCalls.filter((c) => c.name === 'preview').pop()?.args?.country)).toBe('AU')
    await expect(page.locator('[data-pdesc-preview-summary]')).toContainText('1 selected')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
