// Guards: F-SCH Admin UI (Platform Admin S2-Scholarship directive 13 Nov 2026 §6; Operating Model v1.19 S2-Scholarship 5): state, round, source freshness, course link basis, detail recovery and consumer facts as optional columns, server-side filters and a detail-drawer panel in the existing Scholarships Catalogue (no new screen)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113304500_cf247_sch_catalogue_ops_fields.sql', 'utf8')
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('the admin read adds the operator facts and filters through md5-guarded edits; one course_mappings scan', () => {
  expect(m).toContain("select pg_temp.edit_n('security.admin_scholarships_page(jsonb)', 'c831f9f562ebb81d2bb56d088f50cdfb'")
  for (const k of ['round_state', 'source_read_at', 'named_courses', 'provider_wide_courses', 'derived_courses', 'recovery_status', 'website_v3']) expect(m).toContain(` ${k}`)
  for (const f of ['round_state', 'course_links', 'recovery_status', 'source_stale']) expect(m).toContain(`nullif(p_args->>'${f}','') is null`)
  expect(m).toContain("when p_args->>'status' = 'any' then true")
  expect(m).toContain("count(*) filter (where m.mapping_basis in ('page_named_course', 'explicit_course_scope'))::int named_n")
  expect(m).toContain("security.pipeline_num_v1('sch_detail.source_stale_days', 180)")
  expect(m).not.toMatch(/\blnk as \(/)
})

test('the catalogue: published by default, a State filter for the rest, the new filters and optional columns, the drawer panel', () => {
  expect(ui).toContain("if(type==='scholarship')a.status=filters.schState||'published';")
  for (const k of ["['roundState','round_state']", "['courseLinks','course_links']", "['recoveryStatus','recovery_status']", "['sourceStale','source_stale']"]) expect(ui).toContain(k)
  for (const k of ['sch_round', 'sch_source', 'sch_links', 'sch_recovery', 'sch_consumers']) { expect(ui).toContain(`{key:'${k}'`); expect(ui).toContain(`if(key==='${k}')`) }
  expect(ui).toContain("label=\"Zoho v3: not verified\"")
  expect(ui).toContain('{row&&row.id===data.id?<SchDeliveryPanel r={row}/>:null}')
  expect(ui).toContain("{key:'sch_name',label:'Scholarship',width:260,sortKey:'scholarship'}")
})
