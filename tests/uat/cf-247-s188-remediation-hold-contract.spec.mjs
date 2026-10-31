// Guards: StudySearch SS-007 (Platform Admin 31 Oct 2026 11:53 conditional approval and 12:38 Executive Execution Mandate §2; admin 2026-10-31-studysearch-transformation.md §17, §18): a binding remediation hold kept in one indexed table and enforced through the existing binding guard, the one stop gate, AI match preparation and the link-search send path, so a re-roled course is not re-searched, re-bound, read or AI-matched; the re-role is Platform Admin only, per provider, count-guarded, reversible, keeps evidence and provenance, deletes nothing; no hold is created by the migration
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031030000_cf247_ss007_remediation_hold.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')
const fn = (name) => {
  const i = m.indexOf(`create or replace function ${name}(`)
  expect(i, name).toBeGreaterThan(-1)
  return m.slice(i, m.indexOf('$function$;', i))
}

test('md5-guarded edits of exactly the four existing controls, before and after values pinned', () => {
  for (const [sig, before, after] of [
    ['security.coverage_page_refused_host_guard()', 'efd59e2a453ab113c4ac49e0413bcce3', '33351b506da59359656ee196218d7882'],
    ['security.search_stop_gate_v1(uuid,uuid,boolean,boolean)', '6e08df75e43bc95a3f15c5f2763c182d', 'd7679a059ed611cdc4553b70459f549f'],
    ['security.coverage_ai_match_prepare_v1(integer,integer)', 'ab2dd5dc2e897b20c9de8bbc84bd26eb', '23d433d2d730fc8d58ffb555a686ca44'],
    ['security.course_link_search_tick_v1(integer)', '13b0771da8ae1831ff1291bfac82faa6', 'ffc9fb647925f689678a035cdd64b3e1'],
  ]) expect(m).toContain(`select pg_temp.edit_once('${sig}', '${before}', '${after}', array[`)
  expect(code(m).match(/select pg_temp\.edit_once\(/g)).toHaveLength(4)
  expect(m).toMatch(/^-- Replaces: security\.coverage_page_refused_host_guard, security\.search_stop_gate_v1, security\.coverage_ai_match_prepare_v1, security\.course_link_search_tick_v1/m)
  expect(m).toContain('-- Retires: nothing')
})

test('one hold: one table, one open hold per course (partial unique index), one check; table purpose stated, closed to app roles', () => {
  expect(m).toContain('create table if not exists pipeline.course_remediation_holds (')
  expect(m).toContain('create unique index if not exists course_remediation_holds_open on pipeline.course_remediation_holds (course_id) where lifted_at is null;')
  expect(m).toMatch(/comment on table pipeline\.course_remediation_holds is '[^']+/)
  expect(m).toContain('alter table pipeline.course_remediation_holds enable row level security;')
  expect(m).toContain('revoke all on pipeline.course_remediation_holds from public, anon, authenticated;')
  expect(fn('security.course_held_v1')).toContain('where h.course_id = p_course and h.lifted_at is null')
})

test('every lane respects the hold through an existing control', () => {
  // binding guard trigger: no lane can bind a held course again; a person's manual lock still wins
  expect(m).toMatch(/if tg_op = 'UPDATE' and new\.status in \('bound', 'ambiguous'\) and security\.course_held_v1\(new\.course_id\)\s+and not exists \(select 1 from pipeline\.manual_locks k[^)]*\) then\s+return old;/)
  // the one stop gate used by every worker-sent course search
  expect(m).toMatch(/if p_course is not null and security\.course_held_v1\(p_course\) then\s+return 'remediation_hold';\s+end if;\s+-- SP-1/)
  // AI match preparation, in both places the no-page hold is checked
  expect(m).toContain("and not security.no_page_hold_v1(co.id) and not security.course_held_v1(co.id)  -- SS-007: remediation hold; SP-1$n$]], array[2]);")
  // the tick's direct send path
  expect(m).toContain("where s.state = 'queued' and not security.course_held_v1(s.course_id) and not exists")
  // and the post-check refuses an AI-match function missing either check
  expect(m).toContain("raise exception 'SS-007 post-check: AI match preparation does not check the hold in both places'")
})

test('the re-role: Platform Admin only, one provider, batch limit from a setting, every binding re-checked live, exact count guard before any change', () => {
  const f = fn('security.binding_remediation_apply_v1')
  expect(f).toContain("if current_user <> 'postgres' then raise exception 'binding remediation is run by the Platform Admin only'")
  expect(f).toContain("security.pipeline_num_v1('remediation.max_batch_courses', 50)")
  for (const why of ["'no binding'", "'another provider'", "'the bound page changed since review'", "'manual binding'", "'locked by hand'", "'course not active'", "'already held'"]) expect(f).toContain(why)
  expect(f).toMatch(/v_pg\.status <> 'bound' then v_why := 'not bound/)
  const guard = f.indexOf("raise exception 'count guard:")
  expect(guard).toBeGreaterThan(-1)
  expect(guard).toBeLessThan(f.indexOf('insert into pipeline.course_remediation_holds'))
  expect(f).toContain("raise exception 'count guard after change:")
  expect(m).toContain("('pipeline', 'remediation.max_batch_courses', 'Binding remediation: most courses in one batch',")
  expect(m).toContain("to_jsonb(50), 1, 200, 'courses', 794, 'Platform upkeep', 'security.binding_remediation_apply_v1',")
  expect(m).toContain('revoke all on function security.binding_remediation_apply_v1(uuid, jsonb, int, text, text) from public, anon, authenticated, service_role;')
})

test('the re-role keeps evidence and provenance, uses existing status values only, records a full before state and deletes nothing', () => {
  const f = fn('security.binding_remediation_apply_v1')
  for (const k of ["'page', to_jsonb(v_pg)", "'course_url'", "'fill'", "'official_links'", "'rejected_before'"]) expect(f).toContain(k)
  expect(f).toContain("update pipeline.coverage_course_pages set status = 'mismatch', next_read_at = null, leased_until = null")
  expect(f).not.toMatch(/evidence_id\s*=\s*null|identity_basis\s*=\s*null|read_status\s*=/)
  expect(f).toContain("update catalogue.course_links l set status = 'unverified', is_primary = false")
  expect(f).toContain("and (l.url = v_url or l.url in (select jsonb_array_elements_text(v_it->'also_links')))")
  expect(f).toContain("insert into pipeline.page_rejections(course_id, url, provider_id, evidence_id, source, reason, signals)")
  expect(f).toContain("insert into search.refresh_requests(requested_by)")
  expect(f).not.toMatch(/\b(delete|truncate|drop)\b/i)
  expect(f).not.toMatch(/catalogue\.courses c? ?set|update catalogue\.courses/)   // courses.course_url is left to job course-url-fill (guard 3)
})

test('rollback: restore puts the binding and links back and removes only the rejection it added; release keeps the rejection', () => {
  const f = fn('security.binding_remediation_lift_v1')
  expect(f).toContain("if current_user <> 'postgres' then raise exception")
  expect(f).toContain("p_mode not in ('restore', 'release')")
  expect(f).toContain("update catalogue.course_links l set status = 'active'")
  expect(f).toContain("delete from pipeline.page_rejections r where r.course_id = p_course and r.url = v_h.url and r.source = 'binding_remediation' and r.signals->>'hold_id' = v_h.id::text;")
  expect(f).toContain("if not coalesce((v_h.before->>'rejected_before')::boolean, false) then")
  expect(m).toContain('revoke all on function security.binding_remediation_lift_v1(uuid, text, text) from public, anon, authenticated, service_role;')
})

test('nothing else changes: no hold is created, no job or schedule, no time-out, no consumer API object', () => {
  const c = code(m)
  const top = c.replace(/\$([a-z]*)\$[\s\S]*?\$\1\$/g, '')
  expect(top).not.toMatch(/^\s*(update|delete)\b/im)
  expect([...top.matchAll(/^\s*insert into ([a-z_.]+)/gim)].map((x) => x[1])).toEqual(['pipeline.platform_toolset_settings', 'pipeline.component_register'])
  expect(c).not.toMatch(/statement_timeout|cron\.(schedule|alter_job|unschedule)/)
  expect(c).not.toMatch(/\b(drop|truncate)\b/i)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\.|consumer_api_rebaseline_v1/)
  expect(m).toContain("raise exception 'SS-007 post-check: no hold may exist when this ships'")
  expect(c).not.toMatch(/binding_remediation_apply_v1\(\s*'/)   // the migration never runs a re-role
})
