// Guards: Platform Admin 18 Nov 2026 19:20 (Layer 4 grouped bulk-decision view): Layer 4 › Inbox › Grid › Clusters groups waiting items by kind, university, refusal reason and normalised quote, read from the Inbox's own pages; a cluster is inspected, or settled with one choice, one reason and a typed confirmation, each item decided through the Inbox's own decision at its own rank; the AER audit sample, entry requirements, identity, campus postcodes and human-input requests are inspect only. No server change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { inboxSummary } from './support/admin-fixtures.mjs'
import { NEVER_SETTLE, normText, quoteOf, clusterItems, settleChoices, confirmPhrase } from '../../src/lib/layer4-clusters.js'

test('normalising: case, spacing, numbers and links do not split a cluster; different words do', () => {
  expect(normText('Who it is FOR is not proven:  2 pages, https://x.edu/a?b=1')).toBe(normText('who it is for is not proven: 17 pages, http://y.edu/c'))
  expect(normText('Full-time study')).not.toBe(normText('Part-time study'))
})

test('the quote is found wherever the kind keeps it', () => {
  expect(quoteOf({ detail: { value_quote: 'Up to $5,000' } })).toBe('Up to $5,000')
  expect(quoteOf({ detail: { evidence: { quote: 'Study full time' } } })).toBe('Study full time')
  expect(quoteOf({ detail: { refused: [{ quote: '' }, { quote: 'Bachelor of Arts' }] } })).toBe('Bachelor of Arts')
  expect(quoteOf({ detail: {} }, { sections: [{ key: 'page' }, { key: 'quote', title: 'The quote', body: { Quote: 'Two years full time' } }] })).toBe('Two years full time')
  expect(quoteOf({ detail: {} })).toBe('')
})

test('clusters are kind, university, reason and quote; singles are left out; the largest comes first', () => {
  const it = (ref, p, why, q) => ({ kind: 'held_scholarship', ref, provider_id: p, provider: p, why, detail: { value_quote: q } })
  const c = clusterItems([it('1', 'A', 'value not proven by 2 quotes', 'Up to $5,000'), it('2', 'A', 'value not proven by 3 quotes', 'up to $7,500'), it('3', 'A', 'value not proven by 1 quotes', 'Up to $10,000'),
    it('4', 'B', 'value not proven by 2 quotes', 'Up to $5,000'), it('5', 'A', 'who it is for is not proven', 'Up to $5,000'), it('6', 'B', 'value not proven', 'Up to $5,000')])
  expect(c.map((x) => [x.provider, x.items.length])).toEqual([['A', 3]])
})

test('settling: never for the kinds decided one at a time; never a choice needing a value, a link or a higher role', () => {
  const k = { choices: [{ key: 'publish', label: 'Publish', rank: 4 }, { key: 'withdraw', label: 'Withdraw', rank: 6 }, { key: 'enter', input: 'url' }, { key: 'open', link: '#x' }] }
  expect(settleChoices('held_scholarship', k, 4).map((c) => c.key)).toEqual(['publish'])
  expect(settleChoices('held_scholarship', k, 6).map((c) => c.key)).toEqual(['publish', 'withdraw'])
  for (const kind of ['aer_review', 'campus_locality', 'intervention', 'provider_departure']) { expect(NEVER_SETTLE).toContain(kind); expect(settleChoices(kind, k, 6)).toEqual([]) }
  expect(confirmPhrase('publish', 3)).toBe('PUBLISH 3')
})

test('source: the screen reads and decides only through the Inbox (no bulk server call, no new function)', () => {
  const s = fs.readFileSync('src/Layer4Clusters.jsx', 'utf8')
  expect(s.match(/supabase\.rpc\('([a-z_0-9]+)'/g)).toEqual(["supabase.rpc('admin_layer4_inbox'"])
  for (const a of ["rpc('items'", "rpc('detail'", "rpc('decide'"]) expect(s).toContain(a)
  expect(fs.readFileSync('src/Layer4Grid.jsx', 'utf8')).toContain('data-l4g-view="clusters"')
})

test.describe('mocked browser', () => {
  test('Grid › Clusters: inspect a cluster and settle it item by item with a typed confirmation', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const decided = []
    const items = ['1', '2', '3'].map((ref) => ({ kind: 'held_scholarship', ref, o: 2, created_at: `2026-11-1${ref}T00:00:00Z`, provider_id: 'p1', provider: 'Example University',
      subject: `Scholarship ${ref}`, why: `who it is for is not proven by a quote on the page (${ref} checks)`, detail: { audience_quote: 'Open to all  students' } }))
      .concat([{ kind: 'held_scholarship', ref: '9', o: 2, created_at: '2026-11-19T00:00:00Z', provider_id: 'p2', provider: 'Other University', subject: 'Lonely', why: 'value not proven', detail: {} }])
    const summary = { ...inboxSummary, kinds: { ...inboxSummary.kinds, held_scholarship: { label: 'Held scholarship', order: 2, choices: [{ key: 'publish', label: 'Publish', rank: 4 }, { key: 'withdraw', label: 'Withdraw', rank: 4 }, { key: 'fix', label: 'Correct the value', input: 'text', rank: 4 }] } } }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', (r) => {
      const b = r.request().postDataJSON() || {}
      if (b.p_action === 'summary') return r.fulfill({ json: summary })
      if (b.p_action === 'items' && b.p_args?.kind === 'held_scholarship') return r.fulfill({ json: { total: 4, more: false, items } })
      if (b.p_action === 'decide') { decided.push(b.p_args); return r.fulfill({ json: { ok: true } }) }
      return r.fallback()
    })
    await page.goto('/#layer-4-review?view=grid')
    await page.locator('[data-l4g-view="clusters"]').click()
    const c = page.locator('[data-l4c]')
    await c.locator('[data-l4c-kind]').selectOption('held_scholarship')
    await expect(c.locator('[data-l4c-scanned]')).toContainText('4 of 4 waiting items read; 1 cluster of two or more')
    await expect(c.locator('[data-l4c-cluster]')).toHaveCount(1)
    await c.locator('[data-l4c-open]').click()
    await expect(c.locator('[data-l4c-items] li')).toHaveCount(3)
    await expect(c.locator('[data-l4c-choice] option')).toHaveText(['Publish', 'Withdraw']) // a choice needing a value is never offered
    await c.locator('[data-l4c-pick]').check()
    await c.locator('[data-l4c-choice]').selectOption('withdraw')
    await c.locator('[data-l4c-reason]').fill('Audience not stated on the page')
    await expect(c.locator('[data-l4c-settle]')).toBeDisabled()
    await c.locator('[data-l4c-confirm-input]').fill('WITHDRAW 3')
    await c.locator('[data-l4c-settle]').click()
    await expect(c.locator('[data-l4c-note]')).toContainText('3 decided')
    expect(decided.map((d) => [d.kind, d.ref, d.choice, d.reason])).toEqual(['1', '2', '3'].map((ref) => ['held_scholarship', ref, 'withdraw', 'Audience not stated on the page']))
  })

  test('the AER kind is inspect only', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', (r) => {
      const b = r.request().postDataJSON() || {}
      if (b.p_action === 'summary') return r.fulfill({ json: { ...inboxSummary, kinds: { ...inboxSummary.kinds, aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [{ key: 'approve', label: 'Approve', rank: 3 }] } } } })
      if (b.p_action === 'items') return r.fulfill({ json: { total: 0, more: false, items: [] } })
      return r.fallback()
    })
    await page.goto('/#layer-4-review?view=grid')
    await page.locator('[data-l4g-view="clusters"]').click()
    await page.locator('[data-l4c-kind]').selectOption('aer_review')
    await expect(page.locator('[data-l4c-inspect-only]')).toContainText('inspect only')
    await expect(page.locator('[data-l4c-choice]')).toHaveCount(0)
  })
})
