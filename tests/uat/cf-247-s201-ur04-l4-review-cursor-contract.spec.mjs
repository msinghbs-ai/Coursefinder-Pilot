// Guards: StudySearch usability remediation UR-04 (Platform Admin mandate 1 Nov 2026 11:48, Tranche B; admin record §36): Layer 4 › Review reaches every item of a kind with more than 200, oldest first, page by page from a stable position (kind order, created, kind, ref) that a decision or new arrival cannot shift, never by raising the 200 cap, and resumes the position after a destination screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261101050000_cf247_ur04_l4_review_cursor.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('migration: md5-guarded; stable order with a unique tie-breaker; keyset position; cap unchanged; nothing dropped', () => {
  expect(m).toContain("select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', 'ff6e116bf052c972a59b7a71bdb1fbf4', '48a52717d398c14de6920f18667068a0', array[")
  expect(m).toContain("'detail', z.detail, 'o', z.o) order by z.o, z.created_at, z.kind, z.ref)")
  expect(m).toContain("or (x.o, x.created_at, x.kind, x.ref) > ((p_args->>'after_o')::int, (p_args->>'after_at')::timestamptz, p_args->>'after_kind', p_args->>'after_ref')")
  expect(m).toContain("order by o, created_at, kind, ref limit v_lim offset v_off) z), '[]'::jsonb),")
  expect(m).toContain("'before', (select count(*) from x where p_args ? 'after_ref'")
  expect(code(m)).not.toMatch(/least\(greatest\(coalesce\(\(p_args->>'limit'\)::int, 50\), 1\), (?!200)/)
  expect(m).toMatch(/^-- Replaces: public\.admin_layer4_inbox/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test.describe('mocked browser', () => {
  test('By kind with 450 items: Next continues after the last item, Previous returns, and the position survives leaving the screen', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const kinds = { nothing_ready: { label: 'Adapter has nothing ready', order: 8, choices: [{ key: 'keep', label: 'Keep waiting', returns: 'Stays waiting' }] } }
    const all = Array.from({ length: 450 }, (_, i) => ({ kind: 'nothing_ready', ref: `r${String(i).padStart(4, '0')}`, o: 8, provider_id: 'p1', provider: 'Uni', subject: `Item ${i}`, why: 'w',
      created_at: new Date(Date.UTC(2026, 9, 1) + i * 60000).toISOString(), late: false, detail: {} }))
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 450, universities: 1, late: 0, by_kind: { nothing_ready: { n: 450 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 0, items: [] } })
      if (b.p_action === 'items') {
        const a = b.p_args
        const after = a.after_ref ? all.findIndex((x) => x.ref === a.after_ref) + 1 : 0
        return route.fulfill({ json: { total: all.length, before: a.after_ref ? after : 0, items: all.slice(after, after + a.limit) } })
      }
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review?view=kind&kind=nothing_ready')
    await expect(page.locator('[data-l4-range]')).toContainText('1–200 of 450')
    await page.locator('[data-l4-next]').click()
    await expect(page.locator('[data-l4-range]')).toContainText('201–400 of 450')
    expect(calls.filter((c) => c.p_action === 'items').at(-1).p_args).toMatchObject({ kind: 'nothing_ready', limit: 200, after_ref: 'r0199', after_kind: 'nothing_ready', after_o: 8 })
    await page.locator('[data-l4-next]').click()
    await expect(page.locator('[data-l4-range]')).toContainText('401–450 of 450')
    await expect(page.locator('[data-l4-next]')).toBeDisabled()
    await page.goto('/#catalogue')
    await page.goto('/#layer-4-review?view=kind&kind=nothing_ready')
    await expect(page.locator('[data-l4-range]')).toContainText('401–450 of 450')
    await page.locator('[data-l4-prev]').click()
    await expect(page.locator('[data-l4-range]')).toContainText('201–400 of 450')
    await page.locator('[data-l4-prev]').click()
    await expect(page.locator('[data-l4-range]')).toContainText('1–200 of 450')
    await expect(page.locator('[data-l4-prev]')).toBeDisabled()
  })
})
