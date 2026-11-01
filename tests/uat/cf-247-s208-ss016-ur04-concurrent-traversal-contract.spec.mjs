// Guards: SS-016 UR-04 acceptance (usability review 1 Nov 2026 §4 UR-04 "Accept"; overnight mandate §4): with more than 200 mixed pending items, a pass page by page reaches every item exactly once while new items arrive and a decision is saved during the pass; nothing is repeated, and items that arrive behind the position are reached on the next pass, oldest first (no starvation). The fixture server pages by the live keyset (kind order, created, kind, ref; public.admin_layer4_inbox from 20261101050000).
import { test, expect } from '@playwright/test'
import { asRole } from './support/role-fixtures.mjs'

const KINDS = {
  course_link: { label: 'Course link', order: 1, choices: [{ key: 'keep', label: 'Keep the page we hold', returns: 'Closed' }] },
  website_needed: { label: 'Website needed', order: 3, choices: [{ key: 'cricos_only', label: 'CRICOS data only', returns: 'Closed' }] },
  nothing_ready: { label: 'Adapter has nothing ready', order: 6, choices: [{ key: 'cricos_only', label: 'CRICOS data only', returns: 'Closed' }] },
}
const ORDER = Object.keys(KINDS)
const t0 = Date.UTC(2026, 9, 1)
const mk = (i, kind, minutes) => ({ kind, ref: `${kind.slice(0, 2)}-${String(i).padStart(4, '0')}`, o: KINDS[kind].order, provider_id: 'p1', provider: 'Uni', subject: `Item ${i}`, why: 'w',
  created_at: new Date(t0 + minutes * 60000).toISOString(), late: false, detail: {} })
const key = (x) => [x.o, x.created_at, x.kind, x.ref]
const cmp = (a, b) => { for (let i = 0; i < 4; i++) { if (a[i] < b[i]) return -1; if (a[i] > b[i]) return 1 } return 0 }

test.describe('mocked browser', () => {
  test('UR-04: 450 mixed items, 40 arrivals and a decision during the pass: every item once, none repeated, late arrivals reached next pass', async ({ page }) => {
    await asRole(page, 6)
    // 450 pending items of three kinds for one university, created a minute apart
    let pending = Array.from({ length: 450 }, (_, i) => mk(i, ORDER[i % 3], i * 3))
    const all = new Map(pending.map((x) => [x.ref, x]))
    const decided = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(), a = b.p_args || {}
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: pending.length, universities: 1, late: 0, by_kind: Object.fromEntries(ORDER.map((k) => [k, { n: pending.filter((x) => x.kind === k).length }])) } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Uni', country: 'AU', by_kind: {} }] } })
      if (b.p_action === 'items') {
        const sorted = pending.filter((x) => x.provider_id === a.provider_id && (!a.kind || x.kind === a.kind)).sort((p, q) => cmp(key(p), key(q)))
        const at = a.after_ref ? [Number(a.after_o), a.after_at, a.after_kind, a.after_ref] : null
        const after = at ? sorted.filter((x) => cmp(key(x), at) > 0) : sorted
        return route.fulfill({ json: { total: sorted.length, before: sorted.length - after.length, items: after.slice(0, a.limit) } })
      }
      if (b.p_action === 'decide') { decided.push(a.ref); pending = pending.filter((x) => x.ref !== a.ref); return route.fulfill({ json: { ok: true, returns: 'Closed', outcome: { class: 'reconciled', decision_id: 'd0000001' }, event_id: 7 } }) }
      return route.fulfill({ json: {} })
    })
    const refsOnScreen = () => page.locator('[data-l4-ref]').evaluateAll((els) => els.map((e) => e.getAttribute('data-l4-ref')))
    const arrive = (from, n, minutes) => { for (let i = 0; i < n; i++) { const x = mk(from + i, ORDER[i % 3], minutes(i)); pending.push(x); all.set(x.ref, x) } }

    await page.goto('/#layer-4-review?provider=p1')
    await expect(page.locator('[data-l4-range]')).toContainText('1–200 of 450')
    const seen = [...(await refsOnScreen())]
    expect(seen).toHaveLength(200)

    // while the reviewer reads page 1: 20 arrivals interleaved with the oldest items and 20 newest ones, of every kind. Whether an arrival is
    // behind or ahead of the position follows the live order (kind order first), so it is worked out from the last item on page 1
    const pos = key(all.get(seen.at(-1)))
    arrive(1000, 20, (i) => 1 + i * 3)
    arrive(2000, 20, (i) => 5000 + i)
    const arrivals = [...all.values()].filter((x) => Number(x.ref.slice(3)) >= 1000)
    const behind = arrivals.filter((x) => cmp(key(x), pos) < 0).map((x) => x.ref), ahead = arrivals.filter((x) => cmp(key(x), pos) > 0).map((x) => x.ref)
    expect(behind.length).toBeGreaterThan(0); expect(ahead.length).toBeGreaterThan(0)
    await page.locator('[data-l4-next]').click()
    // arrivals behind the position are counted before it: the range says where the page is in today's list
    await expect(page.locator('[data-l4-range]')).toContainText(`${200 + behind.length + 1}–${200 + behind.length + 200} of 490`)
    const p2 = await refsOnScreen()
    // a decision saved on page 2 reloads the same position: the decided item leaves, nothing shifts or repeats
    const target = p2[17]
    const card = page.locator(`[data-l4-ref="${target}"]`)
    await card.locator('[data-l4-choice]').first().click()
    await card.getByLabel('Reason').fill('checked on the stored copy')
    await card.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status').filter({ hasText: 'Done.' })).toContainText('Done.')
    await expect(page.locator(`[data-l4-ref="${target}"]`)).toHaveCount(0)
    const p2after = await refsOnScreen()
    expect(p2after.filter((r) => !p2.includes(r))).toHaveLength(1)   // the next item after the page moves up by one
    // page 2 as it now stands (the decided item was reached and settled once; the item that moved up is on screen)
    seen.push(target, ...p2after)
    let pages = 2
    while (await page.locator('[data-l4-next]').isEnabled()) {
      const was = await page.locator('[data-l4-range]').textContent()
      await page.locator('[data-l4-next]').click(); pages++
      await expect(page.locator('[data-l4-range]')).not.toHaveText(was)
      seen.push(...(await refsOnScreen()))
    }
    // the pass: no ref twice; every original item reached; every arrival ahead of the position reached
    expect(new Set(seen).size).toBe(seen.length)
    for (let i = 0; i < 450; i++) expect(seen).toContain(mk(i, ORDER[i % 3], i * 3).ref)
    for (const r of ahead) expect(seen).toContain(r)
    expect(behind.filter((r) => seen.includes(r))).toEqual([])
    // the next pass starts again at the oldest: every arrival left behind is on its first page (no starvation)
    await page.locator('[data-l4-prev]').click()
    while (await page.locator('[data-l4-prev]').isEnabled()) await page.locator('[data-l4-prev]').click()
    await expect(page.locator('[data-l4-range]')).toContainText('1–200 of 489')
    const first = await refsOnScreen()
    for (const r of behind) expect(first, `arrival ${r} behind the position must lead the next pass`).toContain(r)
    expect(first).not.toContain(target)
    expect(decided).toEqual([target])
    test.info().annotations.push({ type: 'UR-04', description: `pages ${pages}; reached ${seen.length} distinct of ${all.size} (of 40 arrivals ${ahead.length} ahead of the position, all reached in the pass; ${behind.length} behind it, all on the next pass's first page); 1 decision during the pass; 0 duplicates` })
  })
})
