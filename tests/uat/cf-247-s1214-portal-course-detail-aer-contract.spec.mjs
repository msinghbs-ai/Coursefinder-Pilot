// Guards: Atlas brief 26 Nov 2026 12:02 AEDT for S1-API-Frontend-Delivery (s1214): read-only portal reads behind public wrappers, Viewer rank and above, anon refused: public.portal_course_detail_v1 (one published-provider course in full; outside the portal scope answers not found) and public.portal_aer_list_v1 (pages of published-provider courses with active academic and English entry requirements; filters q, country, source_country, level, provider_id, has; page size portal.aer_page_size); no consumer API object changed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261129080000_cf247_s1214_portal_course_detail_and_aer.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body = (name) => code.slice(code.indexOf(`create or replace function ${name}(`), code.indexOf('end $function$;', code.indexOf(`create or replace function ${name}(`)))

test('s1214: housekeeping header and guards', () => {
  expect(sql).toMatch(/^-- Replaces: nothing \(new reads\)\.$/m)
  expect(sql).toMatch(/^-- Retires: nothing\.$/m)
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain('if (select count(*) from cron.job where active) <> (select cron_before from s1214_guard)')
  expect(code).toContain('if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1214_guard)')
  expect(code).not.toMatch(/\b(drop|alter)\s+(table|view)\b/i)
  expect(code).not.toMatch(/\b(insert into|update|delete from)\s+(catalogue|search|ref)\./i)
})

test('s1214: public wrappers check Viewer rank; only authenticated may execute; inner reads are granted to no one', () => {
  for (const f of ['public.portal_course_detail_v1', 'public.portal_aer_list_v1']) expect(body(f)).toContain('perform security.portal_rank_v1(1);')
  expect(code).toContain('revoke all on function public.portal_course_detail_v1(uuid), public.portal_aer_list_v1(jsonb) from public, anon;')
  expect(code).toContain('grant execute on function public.portal_course_detail_v1(uuid), public.portal_aer_list_v1(jsonb) to authenticated;')
  expect(code).toContain('portal.course_detail_v1(uuid), portal.aer_list_v1(jsonb) from public, anon, authenticated;')
})

test('s1214: course detail is scoped to the portal search and carries every section the screen shows', () => {
  const scope = body('portal.course_in_scope_v1')
  expect(scope).toContain('from search.course_documents d join catalogue.courses c on c.id = d.course_id')
  expect(scope).toContain("c.lifecycle_status = 'active'")
  const d = body('portal.course_detail_v1')
  expect(d).toContain("raise exception 'course not found' using errcode = 'P0002';")
  for (const k of ['description', 'campuses', 'annual_tuition', 'fees', 'intakes', 'entry_requirements', 'english_requirements', 'career_outcomes', 'official_url', 'last_checked']) expect(d).toContain(`'${k}', `)
  expect(d).toContain("where f.course_id = r.id and f.status = 'active'")
  expect(d).toContain("where i.course_id = r.id and i.status = 'active' and (i.start_date is null or i.start_date >= v_today)")
  expect(d).toContain("m.category in ('employment', 'salary') and o.source_cohort_code = v_cohort")
  expect(body('portal.course_entry_json_v1')).toContain("where e.course_id = p_course_id and e.status = 'active'")
  expect(body('portal.course_english_json_v1')).toContain("where r.course_id = p_course_id and r.status = 'active'")
})

test('s1214: the entry requirements list is filtered, paged by a G2 setting, and malformed fields are ignored', () => {
  const a = body('portal.aer_list_v1')
  expect(a).toContain("security.portal_setting_v1('aer_page_size')")
  expect(code).toContain("('portal', 'aer_page_size', 'Entry requirements: courses a page',")
  expect(a).toContain("then upper(btrim(p_args->>'country')) end;")
  expect(a).toContain("then upper(btrim(p_args->>'source_country')) end;")
  expect(a).toContain("in ('academic', 'english', 'both') then lower(p_args->>'has') else 'any' end;")
  expect(a).toContain('v_like := case when v_q is not null then security.portal_like_v1(v_q) end;')
  expect(a).toContain("or co.iso_alpha2 = v_src or e.country_id is null)) ac,")
  expect(a).toContain('limit v_size offset (v_page - 1) * v_size) s')
  expect(code).toContain("y := portal.aer_list_v1(jsonb_build_object('country', 'AU', 'has', 'both', 'page', 1));")
})
