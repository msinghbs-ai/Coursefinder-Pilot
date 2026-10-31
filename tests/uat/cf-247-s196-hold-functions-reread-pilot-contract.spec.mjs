// Guards: StudySearch decisions D16 and D13 (Platform Admin mandate 31 Oct 2026 21:54; admin 2026-10-31-studysearch-transformation.md §32): the three scholarship-hold functions become PL/pgSQL with the same logic, signature and security (md5-guarded, shared callees untouched); the re-read pilot gives exhausted course pages at most one extra direct read (no Firecrawl, no AI), at most 25 a day, 30 days after the last attempt, skipping held courses and restricted providers, records outcomes and stops itself on Firecrawl use or Layer 4 growth; the worker honours direct_only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031110000_cf247_ss014_d16_d13.sql', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('D16: md5-guarded replacement with PL/pgSQL; same security; shared functions untouched; nothing dropped; consumer API untouched', () => {
  expect(m).toContain("not in ('60a8580612898506658ba7498a7b23a6', 'f8d6fb4bf9196dfa596b8274819670a6')")
  for (const f of ['fc_sch_held_v1(p_provider_id uuid, p_discovery boolean) returns boolean', 'fc_sch_eligible_v1(p_provider_id uuid) returns boolean', 'fc_sch_cap_since_v1(p_provider_id uuid) returns timestamptz'])
    expect(m).toContain(`create or replace function security.${f}\nlanguage plpgsql stable security definer set search_path to '' as $function$`)
  expect(code(m)).not.toMatch(/create or replace function security\.(coverage_country|fc_courses_v1|fc_setting_num_v1)\b/)
  expect(m).toContain("raise exception 'D16 post-check: a replaced function has an unexpected definition'")
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

test('D13: bounded pilot: 25 a day at most, 30 days at least, once per page, holds and restrictions respected, self-stopping', () => {
  expect(m).toMatch(/'reread\.pilot_daily_max', [^\n]*\n[^\n]*\n\s*to_jsonb\(25\), 0, 25, 'pages'/)
  expect(m).toMatch(/'reread\.pilot_min_days', [^\n]*\n[^\n]*\n\s*to_jsonb\(30\), 30, 365, 'days'/)
  expect(m).toContain("v_max int := least(security.pipeline_num_v1('reread.pilot_daily_max', 25), 25)::int;")
  expect(m).toContain("v_days int := greatest(security.pipeline_num_v1('reread.pilot_min_days', 30), 30)::int;")
  expect(m).toContain('course_id uuid primary key,')
  expect(m).toContain("and (p.read_status is null or p.read_status in ('fetch_failed', 'blocked'))")
  expect(m).toContain('and not security.course_held_v1(p.course_id)')
  expect(m).toContain("f.reason_code in ('site_unreachable', 'pages_refuse_reading', 'manual_hold')")
  expect(m).toContain("if exists (select 1 from pipeline.page_reread_pilot r where r.outcome_fetched_via = 'firecrawl' or coalesce(r.layer4_items, 0) > 0) then")
  expect(m).toContain('set read_attempts = greatest(p.read_attempts, 3)')
  expect(m).toContain("'direct_only',exists (select 1 from pipeline.page_reread_pilot rr where rr.course_id=u.course_id and rr.outcome_at is null)")
  expect(m).toContain("select cron.schedule('reread-pilot', '41 18 * * *', $$select security.page_reread_pilot_run_v1()$$);")
  expect(m).toContain("comment on table pipeline.page_reread_pilot is 'StudySearch decision D13")
})

test('worker v0.55.0: a direct_only page is never read through Firecrawl (fallback and international view)', () => {
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(5[5-9]|[6-9]\d)\.\d+";/)
  expect(w).toContain('const fcTrusted = it.direct_only !== true && (FC_TRUSTED_BASIS.includes(it.basis || "") || it.manual === true || it.render_ok === true);')
  expect(w).toContain('direct_only?: boolean')
})
