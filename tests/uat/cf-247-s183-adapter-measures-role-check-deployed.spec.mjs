// Guards: CF-247 decision D6 deployed (Platform Admin 30 Oct 2026 08:45; admin decision paper §11.3): over the live REST API, public.admin_adapter_measures refuses an anonymous caller (42501) and answers the signed-in Platform Admin; read only, acts on nothing
// Curator refusal and the service_role and owner paths are proven by s181 and the live rolled-back dry run (decision §11.3, option b).
import { test, expect } from '@playwright/test'
import { loginAsUatUser, writeRunEnvironment } from './support/runtime-evidence.mjs'

test.describe('CF-247 D6 adapter measures role check @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s183-adapter-measures-role-check', change_control: 'CF-CHG-20260915-247' }) })

  test('direct API calls: anonymous refused, Platform Admin allowed', async ({ page }) => {
    // the signed-in session's REST headers: a bearer that is the user's token, not the publishable key
    let seen = null
    page.on('request', (r) => {
      if (seen || !r.url().includes('/rest/v1/')) return
      const h = r.headers()
      if (h.apikey && /^Bearer /i.test(h.authorization || '') && h.authorization !== `Bearer ${h.apikey}`) seen = { origin: new URL(r.url()).origin, authorization: h.authorization, apikey: h.apikey }
    })
    await loginAsUatUser(page)
    await expect.poll(() => seen, { timeout: 30_000 }).not.toBeNull()

    const call = (headers) => page.evaluate(async ({ origin, headers }) => {
      const r = await fetch(`${origin}/rest/v1/rpc/admin_adapter_measures`, { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify({ p_provider_ids: [] }) })
      return { status: r.status, body: await r.json().catch(() => null) }
    }, { origin: seen.origin, headers })

    // anonymous: the publishable key only, no user
    const anon = await call({ apikey: seen.apikey })
    expect([401, 403], JSON.stringify(anon)).toContain(anon.status)
    expect(anon.body?.code, JSON.stringify(anon)).toBe('42501')

    // the signed-in Platform Admin (the UAT user)
    const admin = await call({ apikey: seen.apikey, authorization: seen.authorization })
    expect(admin.status, JSON.stringify(admin)).toBe(200)
    expect(admin.body).toEqual([])
  })
})
