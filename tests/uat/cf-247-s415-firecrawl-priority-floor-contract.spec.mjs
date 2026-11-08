// Guards: Platform Admin 8 Nov 2026 Firecrawl priority order (AER entry pages first), G2 (the floor and the re-sized shares are settings), G3 (no consumer API object touched), "a passing check never switches anything on"
// CF-247 Firecrawl priority floor (migration 20261108060000) and the 100,000-credit plan re-sizing (20261108061000). Source contract over the migrations and the PostgreSQL fixture
// (tests/fixtures/firecrawl-priority-floor, run on a scratch server by run.sh: its result is reported with the branch). Models cf-247-s411-aer-qut-shared-page-contract.spec.mjs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const F = fs.readFileSync('supabase/migrations/20261108060000_cf247_firecrawl_priority_floor.sql', 'utf8')
const P = fs.readFileSync('supabase/migrations/20261108061000_cf247_firecrawl_plan_100k_shares.sql', 'utf8')
const FX = 'tests/fixtures/firecrawl-priority-floor'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const plan = ['a', 'b', 'c', 'd', 'e'].map((x) => fs.readFileSync(`${FX}/plan100k-${x}.sql`, 'utf8')).join('\n')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const LIVE = { budget: 'e979d2e3d7319d845a5149e40abe6987', spend: 'a9217c5af8e0da8ee18b03bcab9eaeef', hold: '99ec517b8b51b0d1305b739e7f1562fb', month: '8c1419332ff503abd69539ccbad1121d' }

test('the three edits are made once each, from the live md5, with a recorded after md5 and an exact-once check; a second run says already applied', () => {
  for (const m of [LIVE.budget, LIVE.spend, LIVE.hold]) expect(F).toContain(`'${m}'`)
  expect(F).toMatch(/security\.fc_budget_left_v1\(text\)\s+e979d2e3d7319d845a5149e40abe6987 -> [0-9a-f]{32}/)
  expect(F).toMatch(/public\.svc_fc_spend\(numeric,text,uuid,text\)\s+a9217c5af8e0da8ee18b03bcab9eaeef -> [0-9a-f]{32}/)
  expect(F).toMatch(/security\.lane_paid_hold_v1\(text\)\s+99ec517b8b51b0d1305b739e7f1562fb -> [0-9a-f]{32}/)
  expect(F).toContain('must apply exactly % time(s)')
  expect(F).toContain('already applied')
  expect(F).toContain("raise exception 'live % differs from the definition this change edits")
  expect(F).toMatch(/^-- Replaces: security\.fc_budget_left_v1, public\.svc_fc_spend and security\.lane_paid_hold_v1/m)
  expect(F).toMatch(/^-- Retires: nothing$/m)
  expect(run).toContain('applied twice; the second run reported already applied three times and changed nothing')
  expect(run).toContain('differs from live')
  // the md5s the migration records are the ones the scratch copy of the live definitions gives (run.sh checks it)
  expect(run).toContain('the migration does not record the applied md5')
})

test('the floor is one governed setting: label, help, range 0 to 100000, unit credits, used_by, reason; 0 switches it off; the default is 1500', () => {
  expect(F).toContain("('firecrawl', 'priority_floor_course_search', 'Credits kept back from course page search'")
  expect(F).toMatch(/'number', '1500'::jsonb, 0, 100000, 'credits'/)
  expect(F).toContain("'security.fc_budget_left_v1 (course search group); public.svc_fc_spend (refusal reason priority_floor); security.lane_paid_hold_v1 (link_search lane); public.svc_course_link_search_next'")
  expect(F).toContain('0 = off')
  expect(F).toContain("fc_setting_num_v1('priority_floor_course_search', 0);  -- fixed: a missing setting means the floor is off")
  expect(F).toContain('on conflict (toolset_key, key) do nothing')
})

test('only the course search group is held; the answer is the room above the floor, so the picker and every spend stay above it; every other path is unchanged', () => {
  expect(F).toContain("if v_grp = 'course_search' then")
  expect(F).toContain('if v_room is not null then return case when v_room < 1 then 0 else least(v_left, v_room) end; end if;')
  expect(F).toContain('return v_left;')
  expect(F).toContain("coalesce(security.fc_priority_room_v1(), p_units) < p_units then 'priority_floor'")
  expect(F).toContain("'budget_held: Firecrawl balance kept for higher-priority work (priority floor '")
  // the estimate copies the monthly rule term for term; the monthly rule itself is not edited
  const live = fs.readFileSync(`${FX}/live/security.fc_month_refusal_v1.sql`, 'utf8')
  const pieces = [
    "o.observed_at > now() - interval '2 hours'",
    'from pipeline.coverage_vendor_usage u where u.acquisition_provider_id = p.id and u.at > v_at',
    'from pipeline.layer2_provider_attempts a where a.acquisition_provider_id = p.id and a.started_at > v_at',
    "coalesce(nullif(p.request_template->>'fixed_credit_units', '')::numeric, 1)",
  ]
  for (const piece of pieces) { expect(live, piece).toContain(piece); expect(F, piece).toContain(piece) }
  expect(F).not.toMatch(/create or replace function security\.fc_month_refusal_v1/i)
  expect(F).toContain("md5(pg_get_functiondef('security.fc_month_refusal_v1(numeric)'::regprocedure)) <> '" + LIVE.month + "'")
  expect(fs.readFileSync(`${FX}/live/security.fc_budget_left_v1.sql`, 'utf8')).not.toContain('priority_floor')
})

test('nothing else moves: no consumer API object, billing config, reserve, share, job, schedule, switch, drop or delete in the floor migration', () => {
  const c = code(F)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings|create (or replace )?(view|function) (public|api)\./i)
  expect(c).not.toMatch(/update pipeline\.|jsonb_set|cron\.|alter table|insert into pipeline\.layer2|set_config/i)
  expect(c.match(/insert into pipeline\.platform_toolset_settings/gi)).toHaveLength(1)  // only the new setting is inserted (on conflict do nothing)
  expect(c).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(c).not.toMatch(/firecrawl\.dev|http_post|net\.http|openrouter/i)
  expect(F).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(F).toContain("select 'firecrawl', 'priority_floor'")
  expect(F).toContain("'switches_on', false")
  expect(F).toContain('revoke all on function security.fc_vendor_estimate_v1() from public, anon, authenticated')
})

test('the fixture proves the cases: floor holds below, resumes above by itself, other groups unaffected, no fresh balance and floor 0 unchanged, reason recorded, central_map still spends', () => {
  for (const name of [
    'S3 the helper and fc_month_refusal_v1 agree', 'S5 a 2-credit search is refused', 'S5 the refusal is recorded as priority_floor', 'S6 a central_map spend (entry-requirement page finding) is allowed',
    'S6 shares left at 962 credits', 'S7 a 1-credit spend that lands exactly on the floor is allowed', 'S8 released', 'S8 no setting, switch or event was changed to release it',
    'S10 floor 0', 'S10 no fresh balance: unchanged', 'S10 setting row missing', 'S10 daily budget off', 'S10 the monthly reserve still comes first', 'S11 on-demand spend', 'S12 firecrawl:course_search is waiting',
    'S13 ', 'S4 a balance read 121 minutes ago is not',
  ]) expect(fixtures, name).toContain(name)
  expect(fixtures).toContain('fx_live.fc_budget_left_v1')  // the oracle: the live function itself
  expect(run).toContain('fx_live')
})

test('the fixture runs on a scratch server only, mirrors live constraints, checks the live md5s first, and applies each migration twice', () => {
  expect(run).toContain("DB=${FCF_DB:-g_fc_priority_floor}")
  expect(run).toContain('refusing a Supabase project database')
  expect(run).toContain('refused: scratch database name must begin g_')
  expect(run).toContain('is not the live text')
  expect(run).toContain('migration 20261108061000 applied twice; the second run reported already applied seven times')
  const stubs = fs.readFileSync(`${FX}/stubs.sql`, 'utf8')
  for (const c of ['label text not null', 'help text not null default', "section text not null default 'Notices'", 'change_control_ref text not null', 'acquisition_provider_id uuid not null', 'units numeric not null', 'purpose text not null']) expect(stubs, c).toContain(c)
  expect(code(run + fixtures + plan)).not.toMatch(/openrouter|api\.firecrawl|api\.anthropic|curl /i)
})

test('the 100,000-credit plan re-sizing: guarded, per value, audited, and nothing else moves', () => {
  expect(P).toContain("v_bc->>'monthly_vendor_units_limit' = '500000' and v_bc->>'plan_tier' = 'growth_500k'")
  expect(P).toContain("'{plan_tier}', '\"standard_100k\"'")
  expect(P).toContain('Standard plan, 100,000 credits a month ($99 a month), billing period 8 Nov to 8 Dec 2026')
  for (const [k, o, n] of [['daily_budget_total', 25000, 4000], ['daily_share_central', 2500, 1000], ['daily_share_reads', 5000, 1200], ['daily_share_scholarships', 3500, 800], ['daily_share_course_search', 13000, 800], ['daily_share_other', 1000, 200]])
    expect(P, k).toContain(`('${k}', ${o}, ${n})`)
  expect(4000).toBe(1000 + 1200 + 800 + 800 + 200)
  expect(P).toContain('nothing changed')
  expect(P).toContain('already applied')
  expect(P).toContain("'plan_limit'")
  expect(P).toContain("'daily_shares'")
  expect(P).toMatch(/^-- Replaces: nothing$/m)
  expect(P).toMatch(/^-- Retires: nothing$/m)
  const c = code(P)
  expect(c).not.toMatch(/subscription_cost_usd|monetary_cost_basis|unit_cost_usd|usd_per_1k_credits|ops_cost|priority_floor|cron\.|alter table|set_config/i)
  // the only billing_config keys written are the three; the reserve and safety percent are named only in the audit event's unchanged list
  expect([...c.matchAll(/'\{([a-z_]+)\}'/g)].map((m) => m[1]).sort()).toEqual(['monthly_vendor_units_limit', 'plan_note', 'plan_tier'])
  expect(c).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings/i)
  for (const t of ['P1 plan record: every other key untouched', 'P2 a second run changed nothing', 'P3 a value that is no longer the old one is left alone', 'P4 shares left at 100000 credits']) expect(plan, t).toContain(t)
})
