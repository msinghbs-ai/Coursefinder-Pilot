// Guards: Atlas brief 26 Nov 2026 13:07 AEDT (s1216, the four fields S1-API-Frontend-Delivery recorded for the s1214 reads): public.portal_course_detail_v1 adds provider_website, entry_matrix (the provider's active country-by-country entry rows for the course, its level family or provider-wide, capped by portal.entry_matrix_max_rows) and entry_matrix_total; public.portal_aer_list_v1 items add city, state_code, duration_value, duration_unit and annual_tuition_fee; additive keys only, same names, arguments and privileges.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261129100000_cf247_s1216_portal_detail_fields.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body = (name) => code.slice(code.indexOf(`create or replace function ${name}(`), code.indexOf('end $function$;', code.indexOf(`create or replace function ${name}(`)))

test('s1216: housekeeping header, guards and the s1214 bodies it replaces', () => {
  expect(sql).toMatch(/^-- Replaces: portal\.course_detail_v1 and portal\.aer_list_v1 s1214 bodies/m)
  expect(sql).toMatch(/^-- Retires: nothing\.$/m)
  expect(code).toContain("<> '598c749fa25bc54934aa673399cda5fe'")
  expect(code).toContain("<> '764a2dec6fec651d6f08bdff315741f0'")
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain('if (select count(*) from cron.job where active) <> (select cron_before from s1216_guard)')
  expect(code).toContain('if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1216_guard)')
  expect(code).not.toMatch(/\bdrop\s+(table|function|view)\b/i)
  expect(code).not.toMatch(/create or replace function public\./)
})

test('s1216: course detail adds the provider website and the capped entry matrix', () => {
  const d = body('portal.course_detail_v1')
  expect(d).toContain("'provider_website', nullif(btrim(r.provider_website_url), ''),")
  expect(d).toContain("'entry_matrix', v_matrix,")
  expect(d).toContain("'entry_matrix_total', v_matrix_total,")
  expect(d).toContain("from catalogue.provider_entry_matrix m left join ref.countries co on co.id = m.country_id")
  expect(d).toContain("where m.provider_id = r.prov_id and m.status = 'active' and coalesce(m.audience, 'all') in ('international', 'all')")
  expect(d).toContain('or (m.course_id is null and (m.study_level_id is null or m.study_level_id = r.study_level_id or m.study_level_id = r.level_parent_id or ml.parent_id = r.study_level_id)))) x;')
  expect(d).toContain("security.portal_setting_v1('entry_matrix_max_rows')")
  expect(d).toContain('filter (where x.rn <= v_matrix_max)')
  expect(code).toContain("('portal', 'entry_matrix_max_rows', 'Course details: most entry matrix rows',")
})

test('s1216: entry requirements rows add city, length and annual tuition', () => {
  const a = body('portal.aer_list_v1')
  expect(a).toContain("'city', coalesce(cam.city, p.primary_city), 'state_code', coalesce(cam.state_code, ps.code),")
  expect(a).toContain("'duration_value', c.duration_value, 'duration_unit', c.duration_unit,")
  expect(a).toContain("'annual_tuition_fee', case when d.provider_annual_tuition_amount is not null then jsonb_build_object('amount', d.provider_annual_tuition_amount, 'currency', d.provider_annual_tuition_currency) end,")
  expect(a).toContain('where cc.course_id = c.id order by cc.is_primary desc nulls last, ca.city limit 1) cam on true;')
})
