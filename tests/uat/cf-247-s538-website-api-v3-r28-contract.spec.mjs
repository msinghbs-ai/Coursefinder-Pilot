// Guards: Decision 277 (Platform Admin 12 Nov 2026 21:00): Website API v3 is a separate copy beside the frozen v2; R28 intakes[].start_date_status is built in v3 only; v2 is untouched.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const v2 = fs.readFileSync('supabase/functions/website-api-v2/index.ts', 'utf8')
const v3 = fs.readFileSync('supabase/functions/website-api-v3/index.ts', 'utf8')
const mig = fs.readFileSync('supabase/migrations/20261113180000_cf247_website_api_v3_r28.sql', 'utf8')
const STATUSES = ['known', 'no_official_calendar', 'month_only', 'not_on_course_page', 'course_page_not_verified', 'next_year_calendar_pending',
  'not_yet_read', 'own_calendar', 'conflicting_evidence', 'held_for_review', 'rolling']

test('v3 is v2 with every action routed to website_v3_*; same key, rate limit and log', () => {
  expect(v3).toContain('const API_VERSION = "website-v3";')
  expect(v3).toContain('case "search": fn = "website_v3_course_search";')
  expect(v3).toContain('fn = "website_v3_course"; args = ec ? { p_identifier: c, p_edu_country: ec } : { p_identifier: c };')
  expect(v3).toContain('fn = "website_v3_sync";')
  // every action calls a website_v3_* function (WP-0.1); none calls a website_v2_* function directly
  for (const f of ['reference', 'providers', 'rankings', 'scholarships', 'provider', 'scholarship']) {
    expect(v3, f).toContain(`"website_v3_${f}"`)
    expect(mig, f).toContain(`public.website_v2_${f}(`)
  }
  expect(v3).not.toMatch(/fn = "website_v2_/)
  for (const f of ['website_api_v2_auth', 'website_api_v2_rate', 'website_api_v2_log']) expect(v3).toContain(`svc.rpc("${f}"`)
  expect(v3).toContain('p_action: action ? `v3:${action}` : action')
  // the body below the header differs from v2 only in the routed lines
  const body = (s) => s.slice(s.indexOf('import "jsr:'))
  const diff = body(v3).split('\n').filter((l, i) => l !== body(v2).split('\n')[i])
  expect(diff.length).toBeLessThanOrEqual(12)
  expect(v2).toContain('const API_VERSION = "website-v2";')
})

test('R28: a closed list of start_date_status values, worked out from the planner decision; read only', () => {
  const fn = mig.slice(mig.indexOf('create or replace function security.intake_start_date_status_v1'), mig.indexOf('comment on function security.intake_start_date_status_v1'))
  for (const s of STATUSES) expect(fn, s).toContain(`'${s}'`)
  const said = [...fn.matchAll(/then '([a-z_]+)'|else '([a-z_]+)'/g)].map((m) => m[1] || m[2])
  expect(said.every((s) => STATUSES.includes(s))).toBe(true)
  expect(fn).toContain('stable security definer set search_path = \'\'')
  expect(mig).toContain("case when nullif(e->>'start_date', '') is not null then 'known'")
})

test('v3 wrappers call the frozen v2 functions and change only intakes[]; nothing in v2 or the consumer tables is touched', () => {
  expect(mig).toContain('public.website_v2_course(p_identifier)')
  expect(mig).toContain('public.website_v2_course(p_identifier, p_edu_country)')
  expect(mig).toContain('public.website_v2_course_search(p_filters, p_page, p_page_size, p_sort)')
  expect(mig).toContain('public.website_v2_sync(p_cursor, p_full, p_entities, p_page_size)')
  expect(mig).not.toMatch(/create\s+or\s+replace\s+function\s+(public\.)?(website_v2_|website_edge_|website_api_v2_|zoho_)/i)
  expect(mig).not.toMatch(/create\s+or\s+replace\s+function\s+api\./i)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate|alter\s+table)\b/im)
  expect(mig).not.toContain('Consumer API change approved')
  for (const f of ['website_v3_course(text)', 'website_v3_course(text, text)', 'website_v3_course_search(jsonb, integer, integer, text)', 'website_v3_sync(text, boolean, text[], integer)'])
    expect(mig, f).toContain(`grant execute on function public.${f} to service_role;`)
  expect(mig).toMatch(/^-- Replaces: nothing/m)
  expect(mig).toMatch(/^-- Retires: nothing/m)
  expect(JSON.parse(fs.readFileSync('tests/uat/consumer-api-baseline.json', 'utf8')).edge_files['supabase/functions/website-api-v3/index.ts']).toBeUndefined()
})
