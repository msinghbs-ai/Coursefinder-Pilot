// Guards: Platform Admin 23 Nov 2026 18:55 AEDT (S1-Build: shared v1.1 UI backend prerequisites, MOCKUP-SPEC-AND-RETIREMENT-MAP v1.1 sections 2 and 5; REQ-115, REQ-116 / REQ-22; Standing Authority Charter US$5.00 a day cap; G2 settings; G3 frozen).
// s997: the Boost queue read returns the budget cap (Dry-Lane banner); saved courses are each user's own (RLS, toggle, is_saved on every list row);
// Study Square partner contacts sit beside the provider contacts the frozen Zoho v2 feed reads, are entered or imported (never scraped), deactivated
// (never deleted), and read back with active and inactive counts. The deployed check reads the three new reads signed in; it changes nothing.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { loginAsUatUser, writeRunEnvironment } from './support/runtime-evidence.mjs'

const MIG = fs.readFileSync('supabase/migrations/20261123203000_cf247_s997_v1_1_backend_prerequisites.sql', 'utf8')

test('s997: the Boost read gains budget_cap only, changed from the guarded definition, with the cap as a G2 setting', () => {
  expect(MIG).toContain("md5(pg_get_functiondef('public.admin_boost_queue_read(jsonb)'::regprocedure)) <> 'e042641accd8b0e1c18abd17d5c9b429'")
  expect(MIG).toContain("'budget_cap', security.boost_budget_cap_v1((select count(*) from q where q.done_at is null)), 'tiers', jsonb_build_object(")
  expect(MIG).toContain("'dry_lane', coalesce(fc.cap = 0, false) and coalesce(p_queued, 0) > 0")
  expect(MIG).toContain("s.toolset_key = 'firecrawl' and s.key = 'daily_budget_total'")
  expect(MIG).toContain("('pipeline', 'budgets.paid_daily_cap_usd', 'Paid spend: platform cap a day (Firecrawl and AI together)'")
  expect(MIG).toContain("'number', to_jsonb(5), 0, 5, 'US$ a day'")
  expect(MIG).toContain("security.pipeline_num_v1('budgets.paid_daily_cap_usd', 5)")
})

test('s997: saved courses are own rows only, toggled through one RPC, and flagged on every course-list row', () => {
  expect(MIG).toContain('create table pipeline.saved_courses (')
  expect(MIG).toContain('primary key (user_id, course_id)')
  expect(MIG).toContain('alter table pipeline.saved_courses enable row level security;')
  for (const p of ['saved_courses_own_select', 'saved_courses_own_insert', 'saved_courses_own_delete']) expect(MIG).toContain(`create policy ${p} on pipeline.saved_courses`)
  expect(MIG).toContain('create or replace function public.saved_course_toggle_v1(p_course_id uuid, p_saved boolean default null)')
  expect(MIG).toContain("security.pipeline_num_v1('saved_courses.max_per_user', 500)")
  expect(MIG).toContain("only an active course can be saved")
  expect(MIG).toContain("md5(pg_get_functiondef('security.course_list_extras_v1(uuid[])'::regprocedure)) <> 'e24c809a98956d9ad0f5c0484a22c4be'")
  expect(MIG).toContain("'is_saved', exists (select 1 from pipeline.saved_courses sc where sc.user_id = auth.uid() and sc.course_id = c.id))")
})

test('s997: partner contacts are a separate table, entered or imported, deactivated never deleted, read with counts', () => {
  expect(MIG).toContain('create table pipeline.partner_contacts (')
  expect(MIG).toContain("source text not null check (source in ('study_square_admin', 'zoho_crm_partner'))")
  expect(MIG).toContain("lifecycle_status text not null default 'active' check (lifecycle_status in ('active', 'inactive'))")
  expect(MIG).toContain('create or replace function public.admin_partner_contact_save_v1(p_action text, p_payload jsonb)')
  expect(MIG).toContain("a reason is required to deactivate a partner contact")
  expect(MIG).toContain('create or replace function public.admin_partner_contacts_import_v1(p_rows jsonb, p_reason text)')
  expect(MIG).toContain("security.pipeline_num_v1('partner_contacts.import_max_rows', 1000)")
  expect(MIG).toContain('create or replace function public.provider_partner_contacts_v1(p_provider_id uuid, p_status text default')
  for (const k of ["'active_count'", "'inactive_count'"]) expect(MIG).toContain(k)
  // the frozen Zoho v2 contact feed reads pipeline.provider_contacts; partner rows never go there
  expect(MIG).not.toMatch(/insert into pipeline\.provider_contact/i)
})

test('s997: additive only, G3 guarded before and after, locks and cron unchanged, anon shut out, nothing dropped or deleted by the change', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('post-check: the number of active cron jobs changed')
  expect(MIG).toContain('post-check: anon can reach a new object')
  for (const t of ['pipeline.saved_courses', 'pipeline.partner_contacts', 'pipeline.partner_contact_events']) expect(MIG).toContain(`comment on table ${t} is`)
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|alter table [^;]* drop |truncate /i)
  expect(MIG).not.toMatch(/create\s+or\s+replace\s+function\s+(public\.)?(website_|zoho_|api\.)/i)
  // the only delete is the user's own unsave inside the toggle RPC
  expect((MIG.match(/delete from /gi) || []).length).toBe(1)
  expect(MIG).toContain('delete from pipeline.saved_courses s where s.user_id = v_uid and s.course_id = p_course_id;')
})

test.describe('s997 v1.1 backend reads signed in @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s997-v1-1-backend-prerequisites', change_control: 'CF-CHG-20260915-247' }) })

  test('budget cap on the Boost read, the saved list and partner contact counts answer', async ({ page }) => {
    let seen = null
    page.on('request', (r) => {
      if (seen || !r.url().includes('/rest/v1/')) return
      const h = r.headers()
      if (h.apikey && /^Bearer /i.test(h.authorization || '') && h.authorization !== `Bearer ${h.apikey}`) seen = { origin: new URL(r.url()).origin, authorization: h.authorization, apikey: h.apikey }
    })
    await loginAsUatUser(page)
    await expect.poll(() => seen, { timeout: 30_000 }).not.toBeNull()
    const rpc = (fn, body) => page.evaluate(async ({ origin, headers, fn, body }) => {
      const r = await fetch(`${origin}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify(body) })
      return { status: r.status, body: await r.json().catch(() => null) }
    }, { origin: seen.origin, headers: { apikey: seen.apikey, authorization: seen.authorization }, fn, body })
    const boost = await rpc('admin_boost_queue_read', { p_args: {} })
    expect(boost.status, JSON.stringify(boost.body)).toBe(200)
    expect(boost.body.budget_cap.source_key).toBe('firecrawl.daily_budget_total')
    expect(typeof boost.body.budget_cap.dry_lane).toBe('boolean')
    expect(boost.body.budget_cap.paid_daily_cap_usd).toBeLessThanOrEqual(5)
    const saved = await rpc('saved_courses_read_v1', {})
    expect(saved.status, JSON.stringify(saved.body)).toBe(200)
    expect(Array.isArray(saved.body.items)).toBe(true)
    const prov = await rpc('admin_read', { p_operation: 'courses_page', p_args: { limit: 1, offset: 0, query: null, sort: 'course', direction: 'asc', lifecycle_status: 'active' } })
    expect(prov.status).toBe(200)
    const row = (prov.body.rows || prov.body.items || [])[0]
    expect(row, JSON.stringify(prov.body).slice(0, 300)).toBeTruthy()
    const pid = row.provider_id || row.provider?.id
    const pc = await rpc('provider_partner_contacts_v1', { p_provider_id: pid, p_status: 'all' })
    expect(pc.status, JSON.stringify(pc.body)).toBe(200)
    expect(Number.isInteger(pc.body.active_count) && Number.isInteger(pc.body.inactive_count)).toBe(true)
  })
})
