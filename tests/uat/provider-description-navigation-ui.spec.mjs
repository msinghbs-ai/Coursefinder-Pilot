// Guards: Provider Description autonomy mandate §6: direct links open the existing Layer 4 decision after a later-page seek, including phone navigation. Transport fixtures test navigation only, never admission.
import { test, expect } from '@playwright/test'

const provider = '10000000-0000-4000-8000-000000000001'
const first = '90000000-0000-4000-8000-000000009000'
const second = '90000000-0000-4000-8000-000000009001'
const captured = '2026-11-04T12:34:56.123456+00:00'

async function navigate(page) {
  const requests = []
  await page.goto('/')
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => {
    const body = route.request().postDataJSON(), args = body.p_args || {}
    const name = new URL(route.request().url()).pathname.split('/').pop()
    let result = {}
    if (name === 'admin_layer4_inbox') {
      requests.push(body)
      if (body.p_action === 'summary') result = { total: 602, universities: 1, target_days: 7, late: 0, rank: 6,
        paging: { items: 25, universities: 25, detail_parallel: 3 },
        kinds: { provider_description: { order: 37, label: 'University description', choices: [] } },
        by_kind: { provider_description: { n: 602 } } }
      if (body.p_action === 'universities') result = { total: 1, items: [{ provider_id: provider, name: 'Navigation University', country: 'AU', courses: 1000, n: 602, by_kind: { provider_description: 602 } }] }
      if (body.p_action === 'items') {
        // A first-page response deliberately cannot contain either linked item.
        // The SQL companion verifies this cursor against the real review table.
        const ref = args.after_ref === '90000000-0000-4000-8000-000000008fff' ? first : args.after_ref === first ? second : '10000000-0000-4000-8000-000000000002'
        result = { total: 602, before: ref === first ? 600 : ref === second ? 601 : 0, more: ref !== second,
          items: [{ kind: 'provider_description', ref, provider_id: provider, provider: 'Navigation University', created_at: captured, o: 37,
            subject: 'Linked provider decision', why: 'Navigation transport fixture; no admission is performed.', detail: { proposed: { description: 'The linked existing review card.' } } }] }
      }
    }
    await route.fulfill({ json: result })
  })
  await page.evaluate(async ({ provider, first, captured }) => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const ReactDOM = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { default: Inbox } = await import('/src/Layer4Inbox.jsx')
    sessionStorage.removeItem('l4i-pos'); sessionStorage.removeItem('l4i-sel')
    document.body.innerHTML = '<main id="navigation-root" style="max-width:1200px;margin:auto;padding:12px"></main>'
    const root = ReactDOM.createRoot(document.getElementById('navigation-root'))
    window.navigateExistingDecision = ref => root.render(React.createElement(Inbox, { routeParams: new URLSearchParams({ provider, kind: 'provider_description', ref, review_at: captured }) }))
    window.navigateExistingDecision(first)
  }, { provider, first, captured })
  await expect(page.locator(`[data-l4-ref="${first}"]`)).toBeVisible()
  await expect(page.locator('[data-l4-range]')).toHaveText('601–601 of 602, oldest first')
  await page.evaluate(second => window.navigateExistingDecision(second), second)
  await expect(page.locator(`[data-l4-ref="${second}"]`)).toBeVisible()
  await expect(page.locator(`[data-l4-ref="${first}"]`)).toHaveCount(0)
  const itemCalls = requests.filter(x => x.p_action === 'items')
  expect(itemCalls).toHaveLength(2)
  expect(itemCalls[0].p_args).toMatchObject({ provider_id: provider, kind: 'provider_description', limit: 25, after_o: 37, after_kind: 'provider_description', after_at: captured, after_ref: '90000000-0000-4000-8000-000000008fff' })
  expect(itemCalls[1].p_args).toMatchObject({ after_ref: first, after_at: captured })
  expect(requests.some(x => x.p_action === 'decide')).toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
}

test('navigation only: seek a later-page existing card and change the linked ref without remounting', async ({ page }) => { await navigate(page) })
test('navigation only: a later-page existing decision is usable on phone @responsive', async ({ page }) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await navigate(page)
})
