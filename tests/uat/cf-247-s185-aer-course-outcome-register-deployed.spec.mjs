// Guards: CF-247 AER production closure C1 deployed (Platform Admin mandate 30 Oct 2026 §4): over the live REST API, public.admin_aer_outcomes refuses an anonymous caller (42501) and answers the signed-in user by rank (rank 4 and above answered with a built register whose outcome counts add up to its course count and whose rows page; below 4 refused); read only, acts on nothing
import { test, expect } from '@playwright/test'
import { loginAsUatUser, writeRunEnvironment } from './support/runtime-evidence.mjs'

const OUTCOMES = ['admitted_course', 'admitted_provider', 'awaiting_review', 'no_requirement_published', 'no_course_url', 'identity_unresolved', 'source_unreadable', 'excluded']

test.describe('CF-247 AER course outcome register @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s185-aer-course-outcome-register', change_control: 'CF-CHG-20260915-247' }) })

  test('direct API calls: anonymous refused; the signed-in user answered or refused by rank; counts add up', async ({ page }) => {
    let seen = null
    page.on('request', (r) => {
      if (seen || !r.url().includes('/rest/v1/')) return
      const h = r.headers()
      if (h.apikey && /^Bearer /i.test(h.authorization || '') && h.authorization !== `Bearer ${h.apikey}`) seen = { origin: new URL(r.url()).origin, authorization: h.authorization, apikey: h.apikey }
    })
    await loginAsUatUser(page)
    await expect.poll(() => seen, { timeout: 30_000 }).not.toBeNull()

    const rpc = (fn, body, headers) => page.evaluate(async ({ origin, fn, body, headers }) => {
      const r = await fetch(`${origin}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify(body) })
      return { status: r.status, body: await r.json().catch(() => null) }
    }, { origin: seen.origin, fn, body, headers })
    const user = { apikey: seen.apikey, authorization: seen.authorization }

    const anon = await rpc('admin_aer_outcomes', { p_args: { part: 'summary' } }, { apikey: seen.apikey })
    expect([401, 403], JSON.stringify(anon)).toContain(anon.status)
    expect(anon.body?.code, JSON.stringify(anon)).toBe('42501')

    const ctx = await rpc('admin_read', { p_operation: 'context', p_args: {} }, user)
    expect(ctx.status, JSON.stringify(ctx)).toBe(200)
    const rank = Number(ctx.body?.role_rank)
    expect(Number.isInteger(rank) && rank >= 1, JSON.stringify(ctx)).toBe(true)

    const sum = await rpc('admin_aer_outcomes', { p_args: { part: 'summary' } }, user)
    if (rank < 4) {
      expect(sum.status, JSON.stringify(sum)).toBe(403)
      expect(sum.body?.code).toBe('42501')
      return
    }
    expect(sum.status, JSON.stringify(sum).slice(0, 500)).toBe(200)
    expect(sum.body.build.built, JSON.stringify(sum.body.build)).toBe(true)
    const courses = Number(sum.body.build.courses)
    expect(courses).toBeGreaterThan(0)
    let total = 0
    for (const x of sum.body.by_outcome) { expect(OUTCOMES).toContain(x.outcome); total += Number(x.courses) }
    expect(total).toBe(courses)

    const page1 = await rpc('admin_aer_outcomes', { p_args: { part: 'rows', offset: 0, limit: 50 } }, user)
    expect(page1.status).toBe(200)
    expect(page1.body.total).toBe(courses)
    expect(page1.body.rows.length).toBe(Math.min(50, courses))
    expect(page1.body.columns.slice(0, 7)).toEqual(['course_id', 'course_code', 'course_title', 'provider', 'provider_published', 'country', 'outcome'])
    for (const r of page1.body.rows) { expect(OUTCOMES).toContain(r[6]); expect(String(r[7] || '').length).toBeGreaterThan(0) }
  })
})
