// Guards: the two picks the worker calls under its 8 s limit check lazily in pick order inside a time budget (Platform Admin 19 Nov 2026 08:18, addendum IQ-00029; S657 narrowing stays; G3 untouched)
// CF-247 S666. Migration 20261119100000_cf247_s666_lazy_pick_time_budget. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const sql = fs.readFileSync(migrationPath('20261119100000_cf247_s666_lazy_pick_time_budget.sql'), 'utf8')
const fnBody = (name) => sql.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`))[1]
const discovery = fnBody('svc_coverage_discovery_next')
const search = fnBody('svc_course_link_search_next')

test('both functions are replaced only from the definitions read live (md5 pre-check) and keep their security attributes', () => {
  expect(sql).toContain("md5(pg_get_functiondef('public.svc_coverage_discovery_next(integer)'::regprocedure)) <> '13d8b126bbe2a2d76a11540e72a4e134'")
  expect(sql).toContain("md5(pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure)) <> 'b9bb31d5c9aa4053b1afaebeab63d36b'")
  expect(sql).toMatch(/svc_coverage_discovery_next\(p_limit integer\)\s+RETURNS jsonb\s+LANGUAGE plpgsql\s+SECURITY DEFINER\s+SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'/)
  expect(sql).toMatch(/svc_course_link_search_next\(p_limit integer\)\s+RETURNS jsonb\s+LANGUAGE plpgsql\s+SECURITY DEFINER\s+SET search_path TO ''/)
  expect(sql).toContain("has_function_privilege('service_role', 'public.svc_coverage_discovery_next(integer)', 'execute')")
})

test('discovery: the focus check runs in pick order, not in the where clause, inside the time budget', () => {
  const where = discovery.slice(discovery.indexOf('for v_r in'), discovery.indexOf('loop\n'))
  expect(where).not.toContain('enrich_focus_v1')
  expect(where).toContain("order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc")
  expect(discovery).toContain("exit when clock_timestamp() - v_t0 > interval '5 seconds';  -- fixed:")
  expect(discovery).toContain('if security.enrich_focus_v1(v_r.provider_id) then v_ids := v_ids || v_r.provider_id; end if;')
  expect(discovery).toContain('where d.provider_id = any (v_ids)')
  expect(discovery).toContain('for update skip locked')
})

test('course search: the stop gate, site list and provider-level checks run in pick order inside the time budget; the order is unchanged', () => {
  const query = search.slice(search.indexOf('for v_r in'), search.indexOf('  loop\n'))
  for (const slow of ['search_stop_gate_v1', 'site_list_match_done_v1', 'enrich_focus_v1', 'site_few_course_pages_v1', 'site_not_checked_v1', 'third_party_host_v1', 'fc_search_stopped'])
    expect(query, slow).not.toContain(slow)
  expect(query).toContain("order by (s.requested_at is null), s.requested_at, pv.prio desc, pv.tier, (s.stage <> 'cricos'), coalesce(pp.rank, 100000),")
  expect(search).toContain("exit when clock_timestamp() - v_t0 > interval '5 seconds';  -- fixed:")
  expect(search).toContain('if security.search_stop_gate_v1(v_r.provider_id, v_r.course_id, v_stopped) is not null then continue; end if;')
  expect(search).toContain('elsif not security.site_list_match_done_v1(v_r.course_id, v_r.provider_id) then')
  expect(search).toContain('if v_stopped and not v_person then continue; end if;')
  expect(search).toContain("security.fc_search_stopped_for_v1(v_r.provider_id)")
  expect(search).not.toContain('fc_search_stopped_v1()')
})

test('the picked rows are still locked with skip locked and leased as before; the daily share, cap and on-demand passes are kept', () => {
  expect(search).toContain('where s.state = \'queued\' and s.course_id = any (v_ids)\n       for update of s skip locked')
  expect(search).toContain("update pipeline.course_link_search s set state = 'sent', sent_at = now(), req_id = null,")
  for (const kept of ["security.fc_budget_left_v1('course_link_search')", "security.pipeline_num_v1('search.daily_picked_cap', 100)", "r.state = 'open' and r.expires_at > now()", 'for v_pass in 1 .. 2 loop'])
    expect(search, kept).toContain(kept)
})

test('no new table, job or setting; nothing dropped; no number of operational value beyond the marked time budget; G3 checked', () => {
  const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  expect(code).not.toMatch(/create table|cron\.schedule|insert into pipeline\.platform_toolset_settings/i)
  expect(code.replace(/\$function\$[\s\S]*?\$function\$/g, '')).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  for (const body of [discovery, search]) for (const l of body.split('\n').filter((x) => /interval '5 seconds'/.test(x))) expect(l).toContain('-- fixed:')
  expect(sql).toContain('<> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48')
})
