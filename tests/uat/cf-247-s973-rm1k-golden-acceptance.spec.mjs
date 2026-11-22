// Guards: RM1K / IR-002 (Platform Admin consolidated batch, 22 Nov 2026 14:22 AEDT): Admin and Website API v3 agree on the Australia golden records, section by section
// s973: the golden fixture names ten page sections and the records that carry them; public.admin_golden_acceptance_v1 reads each record
// through Admin and through Website API v3 and says whether they agree; it only reads, and only a Pipeline Operator or above may call it.
// The deployed check runs it signed in after every deploy and requires all ten sections present and agreeing.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { loginAsUatUser, writeRunEnvironment } from './support/runtime-evidence.mjs'

const FIX = JSON.parse(fs.readFileSync('tests/fixtures/rm1k/australia-golden.json', 'utf8'))
const MIG = fs.readFileSync('supabase/migrations/20261122170000_cf247_s973_rm1k_golden_acceptance.sql', 'utf8')
const SECTIONS = ['course_detail', 'entry_requirements', 'english_requirements', 'tuition_fees', 'scholarships', 'campuses', 'accreditations', 'study_rules', 'career_outcomes', 'rankings']

test('fixture: ten sections in page order, each with its golden record; the records are stable keys and ids', () => {
  expect(FIX.suite).toBe('rm1k_australia_golden_v1')
  expect(FIX.sections.map((s) => s.section)).toEqual(SECTIONS)
  for (const s of FIX.sections) expect(s.golden.length, s.section).toBeGreaterThan(5)
  expect(FIX.records.course).toMatch(/^course:cricos:[0-9a-z]+:[0-9a-z]+$/)
  expect(FIX.records.study_rule_id).toMatch(/^[0-9a-f-]{36}$/)
  expect(FIX.records.career_outcome_id).toMatch(/^[0-9a-f-]{36}$/)
})

test('function: read-only, Pipeline Operator and above, every section read from Admin and from Website v3', () => {
  const fn = MIG.slice(MIG.indexOf('create or replace function public.admin_golden_acceptance_v1(p_records jsonb)'), MIG.indexOf('end $f$;'))
  expect(fn).toContain('security definer')
  expect(fn).toContain("set search_path = ''")
  expect(fn).toContain('stable')
  expect(fn).toContain("if v_rank < 4 then raise exception 'INVALID_INPUT: golden acceptance needs the Pipeline Operator role or above'")
  expect(fn).toContain("public.admin_read('course_detail', jsonb_build_object('id', v_cid))")
  expect(fn).toContain("public.website_v3_course(v_course)->'item'")
  expect(fn).toContain("public.website_v3_destination(jsonb_build_object('country_code', 'au', 'section', 'study_rules'), 1, 100)")
  expect(fn).toContain("public.website_v3_destination(jsonb_build_object('country_code', 'au', 'section', 'career_outcomes'), 1, 100)")
  for (const s of SECTIONS) expect(fn, s).toContain(`'section', '${s}'`)
  expect(fn).not.toMatch(/\b(insert into|update [a-z_]+\.|delete from|truncate)\b/i)
  expect(MIG).toContain('revoke all on function public.admin_golden_acceptance_v1(jsonb) from public, anon;')
  expect(MIG).toContain('grant execute on function public.admin_golden_acceptance_v1(jsonb) to authenticated, service_role;')
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect(MIG).toContain('security.consumer_api_check_v1()')
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|alter table [^;]* drop |delete from |truncate /i)
})

test.describe('RM1K golden acceptance @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s973-rm1k-golden-acceptance', change_control: 'CF-CHG-20260915-247' }) })

  test('Admin and Website API v3 agree on every golden section', async ({ page }) => {
    let seen = null
    page.on('request', (r) => {
      if (seen || !r.url().includes('/rest/v1/')) return
      const h = r.headers()
      if (h.apikey && /^Bearer /i.test(h.authorization || '') && h.authorization !== `Bearer ${h.apikey}`) seen = { origin: new URL(r.url()).origin, authorization: h.authorization, apikey: h.apikey }
    })
    await loginAsUatUser(page)
    await expect.poll(() => seen, { timeout: 30_000 }).not.toBeNull()
    const res = await page.evaluate(async ({ origin, headers, records }) => {
      const r = await fetch(`${origin}/rest/v1/rpc/admin_golden_acceptance_v1`, { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify({ p_records: records }) })
      return { status: r.status, body: await r.json().catch(() => null) }
    }, { origin: seen.origin, headers: { apikey: seen.apikey, authorization: seen.authorization }, records: FIX.records })
    expect(res.status, JSON.stringify(res.body)).toBe(200)
    expect(res.body.sections.map((s) => s.section)).toEqual(SECTIONS)
    for (const s of res.body.sections) {
      expect(s.present, `${s.section} is not served: ${JSON.stringify(s)}`).toBe(true)
      expect(s.match, `${s.section}: Admin and Website v3 differ: ${JSON.stringify(s)}`).toBe(true)
    }
    expect(res.body.passed).toBe(10)
  })
})
