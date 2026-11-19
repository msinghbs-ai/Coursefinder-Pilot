// Guards: reliability and throughput unblock (Platform Admin 19 Nov 2026 08:17, IQ-00609, IQ-00594/IQ-00588, IQ-00606, IQ-00348, stalled planner slots): the coverage build is provider-chunked and well under 10 s, the admission evidence snapshot and writer lock never block a runner, a stored page is claimed once, the evidence index stops at its limit, and stalled automatic plans give their room back.
// CF-247 S720. supabase/migrations/20261119104500_cf247_reliability_unblock_bounded_paths.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119104500_cf247_reliability_unblock_bounded_paths.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('each edited function is md5-guarded against the live definition it replaces', () => {
  expect(M).toContain("'security.course_coverage_build_v1()'::regprocedure, '704dd0cfaa33a19c61383028fa6e1af8'")
  expect(M).toContain("'95c063d16fa95b0f06221cb74e11fd44'")
  expect(M).toContain("'security.enrich_plan_auto_v1()'::regprocedure, 'f0c95d0bbef3ccac550585185c9784c9'")
  expect(M).toContain("if md5(v_src) <> p_md5 then raise exception")
  expect(M).toContain("must apply exactly once")
})

test('every size, budget and time is a setting with a label, range, unit and used_by (G2)', () => {
  for (const k of ['batch.course_coverage_courses', 'admit.consumer_snapshot_page_size', 'admit.consumer_snapshot_budget_ms', 'plans.auto_stall_hours']) {
    expect(M).toContain(`('pipeline', '${k}', `)
  }
  expect(M).toContain("'number', to_jsonb(800), 100, 40000, 'courses', 101, 'Job sizes', 'security.course_coverage_build_v1'")
  expect(M).toContain("security.pipeline_num_v1('batch.course_coverage_courses', 800)")
  expect(M).toContain("security.pipeline_num_v1('plans.auto_stall_hours', 2)")
})

test('coverage build (IQ-00609): the oldest providers up to the batch, every read restricted to the chunk, rows replaced by provider', () => {
  expect(M).toContain('where z.rn = 1 or z.run_n <= v_batch;')
  expect(M).toContain("where co.lifecycle_status='active' and co.provider_id = any(v_chunk);")
  expect(M).toContain('analyze _c;')
  expect(M).toContain('cross join lateral (select distinct on (e.field) e.field, e.state from pipeline.field_enrich_items e where e.course_id = c.course_id')
  expect(M).toContain('from _c cc join pipeline.course_field_absence a on a.course_id = cc.course_id')
  expect(M).toContain('create index on _l4 (course_id, attribute); create index on _l3 (course_id, attribute);')
  expect(M).toContain('delete from pipeline.course_attribute_coverage where provider_id = any(v_chunk || v_gone)')
  expect(M).toContain('$o$  truncate pipeline.course_attribute_coverage;$o$,')  // the truncate is an edit anchor, replaced by the delete
  expect(M).toContain("set schedule = '1-59/3 * * * *', expected_ms = 6000,")
})

test('coverage build: the daily counts move by the run\'s change, start a day from the latest earlier day, and the Australian counts follow', () => {
  expect(M).toContain("select country_code, attribute, state, tier, -n n from _dold")
  expect(M).toContain('do update set courses = pipeline.course_coverage_daily_by_country.courses + excluded.courses')
  expect(M).toContain('where snapshot_date = (select max(snapshot_date) from pipeline.course_coverage_daily_by_country where snapshot_date < current_date);')
  expect(M).toContain("where snapshot_date = current_date and country_code = 'AU' and courses <> 0;")
})

test('coverage build: the chunk\'s AER rules are the three rules of security.aer_covered_courses_v1 (post-check compares them)', () => {
  expect(M).toContain("m.matrix_kind = 'provider_minimum'")
  expect(M).toContain("r.kind = 'override' and r.audience in ('international', 'all')")
  expect(M).toContain('select count(*) into v_a from security.aer_covered_courses_v1() x')
})

test('admission (IQ-00594/IQ-00588): bounded snapshot pages and budget; the writer lock is tried, never waited for', () => {
  expect(M).toContain("admit.consumer_snapshot_budget_ms")
  expect(M).toContain('pg_try_advisory_xact_lock')
  expect(M).toContain('insert into search.refresh_requests')
})

test('page text (IQ-00606) claims each stored page once; evidence index (IQ-00348) walks ranked providers and stops at the limit', () => {
  expect(M).toMatch(/distinct on \(evidence_id\)/)
  expect(M).toContain('svc_evidence_link_index_next_v1')
  expect(M).toMatch(/cross join lateral/)
})

test('planner: stalled automatic plans are released skip-locked, with their own outcome code, before the room is counted', () => {
  expect(M).toContain("insert into pipeline.ops_outcome_codes (code, title, counts_as_movement)")
  expect(M).toContain("values ('released_stalled', ")
  expect(M).toContain('for update of r skip locked)')
  expect(M).toContain("join pipeline.admin_jobs j on j.id = case when s->'ref'->>'id' ~ '^[0-9a-fA-F-]{36}$' then (s->'ref'->>'id')::uuid end")
  expect(M.indexOf("outcome = 'released_stalled'")).toBeLessThan(M.lastIndexOf("select count(*) into v_open from pipeline.enrich_plan_runs"))
})

test('no new table or function; nothing dropped; the consumer API is checked, not changed (G3 75/48)', () => {
  expect(code).not.toMatch(/create table (?!_)|create (or replace )?function (public|security|pipeline|destination|search|api)\./i)
  expect(code).not.toMatch(/^\s*(drop |truncate )/im)
  expect(code).not.toMatch(/^\s*delete from (?!pipeline\.course_attribute_coverage|pipeline\.course_coverage_daily)/im)
  expect(M).toContain('security.consumer_api_check_v1()')
  expect(M).toMatch(/^-- Replaces: |Replaces: /m)
  expect(M).toMatch(/Retires: /m)
})

// 19 Nov 2026 11:15 (20261119111500): the dispatcher's 14-day longest run (112 s, the full rebuild) kept the chunked build deferred behind
// group A's every-minute targets; the build runs first in its due ticks instead. The dispatcher itself is not changed.
const P = fs.readFileSync('supabase/migrations/20261119111500_cf247_coverage_build_first_in_tick.sql', 'utf8')

test('the chunked coverage build is first in its due ticks; the dispatcher is unchanged and nothing new is created', () => {
  expect(P).toContain("set priority = 5, updated_at = now(),")
  expect(P).toContain("where target_code = 'course-coverage-build' and priority = 50 and schedule = '1-59/3 * * * *';")
  expect(P).toContain("raise exception 'another group A target already runs before priority 5'")
  const pc = P.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(pc).not.toMatch(/create (table|or replace|function|procedure)|rollup_tick_v1/i)
  expect(pc).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(P).toMatch(/^-- Replaces: /m)
  expect(P).toMatch(/^-- Retires: /m)
})

// 19 Nov 2026 11:42 critical alert (20261119114500): the evidence-link-index feed read as one set with an anti-join, inside 4 s.
const L = fs.readFileSync('supabase/migrations/20261119114500_cf247_evidence_link_feed_setwise.sql', 'utf8')

test('evidence-link-index feed (IQ-00348): ids from the queue index and one anti-join, rows read by id, 4 s query limit, 6 s deploy check', () => {
  expect(L).toContain("<> 'ff9d9bc6d96f61f076871ab4d9e33ce0'")
  expect(L).toContain("create or replace function public.svc_evidence_link_index_next_v1(p_limit integer default 60)")
  expect(L).toContain("set statement_timeout to '4s'  -- fixed:")
  expect(L).toContain('and not exists (select 1 from pipeline.evidence_link_index_state st')
  expect(L).toContain('with cand as materialized (')
  expect(L).toContain('from top c cross join lateral (select x.* from pipeline.evidence_artifacts x where x.id = c.id) a')
  expect(L).toContain("raise exception 'svc_evidence_link_index_next_v1 took % s (limit 6 s)'")
  const lc = L.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(lc).not.toMatch(/create table|create (or replace )?function (security|pipeline|api|search|destination)\./i)
  expect((lc.match(/create or replace function/gi) || []).length).toBe(1)
  expect(lc).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(L).toMatch(/^-- Replaces: /m)
  expect(L).toMatch(/^-- Retires: /m)
})

// 19 Nov 2026 11:55 (20261119115000): 800 courses took 11.7 to 16.0 s live; 400 every 2 minutes.
const B = fs.readFileSync('supabase/migrations/20261119115000_cf247_coverage_chunk_400.sql', 'utf8')

test('the coverage chunk is 400 courses every 2 minutes, set in the setting with a reason (G2), nothing new created', () => {
  expect(B).toContain("set value = to_jsonb(400), updated_at = now(),")
  expect(B).toContain("where toolset_key = 'pipeline' and key = 'batch.course_coverage_courses' and value = to_jsonb(800);")
  expect(B).toContain("set schedule = '0-58/2 * * * *', expected_ms = 7000,")
  const bc = B.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(bc).not.toMatch(/create (table|or replace|function)|^\s*(drop|delete|truncate)\b/im)
  expect(B).toMatch(/^-- Replaces: /m)
  expect(B).toMatch(/^-- Retires: /m)
})

// 19 Nov 2026 12:55 (20261119125500): the four issues verified as cleared close through security.integration_issue_close_v1; IQ-00606 stays open.
const V = fs.readFileSync('supabase/migrations/20261119125500_cf247_close_verified_reliability_issues.sql', 'utf8')

test('verified issues close only through integration_issue_close_v1 with passed evidence and a time; page_text stays open', () => {
  expect(V).toContain("perform security.integration_issue_close_v1(r.id,")
  expect(V).toContain("jsonb_build_object('outcome', 'passed', 'evidence', r.evidence, 'checked_at', '2026-11-19T12:55:00+11:00',")
  for (const ref of ['IQ-00609', 'IQ-00594', 'IQ-00588', 'IQ-00348']) expect(V).toContain(`('${ref}', '`)
  expect(V).toContain("raise exception 'IQ-00606 must stay open'")
  const vc = V.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(vc).not.toMatch(/create (table|or replace|function)|^\s*(drop|delete|truncate|update)\b/im)
  expect(V).toMatch(/^-- Replaces: /m)
})
