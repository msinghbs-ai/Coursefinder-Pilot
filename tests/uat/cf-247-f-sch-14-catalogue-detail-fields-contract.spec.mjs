// Guards: F-SCH Scholarship Catalogue detail columns and filters (Platform Admin 12 Nov 2026 20:44: "hold on to API release but continue with data fill and make the column and filter available in ui to see results"); admin read only, the consumer API stays untouched (G3) and the pinned base columns stay as they are
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113130000_cf247_sch_catalogue_detail_fields.sql', 'utf8')
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('the admin read gains the detail fields, filters and sorts through md5-guarded edits only', () => {
  expect(m).toContain("select pg_temp.edit_n('security.admin_scholarships_page(jsonb)', 'a27526afafe6d7fbc501224024e0f26f'")
  expect(m).toContain('left join scholarship.award_details ad on ad.scholarship_id = s.id')
  for (const f of ['award_type', 'application_method', 'nationality_status', 'has_description', 'has_benefits', 'has_sponsor', 'has_close_date', 'detail_read'])
    expect(m).toContain(`nullif(p_args->>'${f}','') is null`)
  expect(m).toContain("'benefits_label'")
  expect(m).toContain("then 'under_review'")
})

test('the catalogue shows the detail columns on request and filters on them, keeping the base columns', () => {
  expect(ui).toContain("{key:'sch_name',label:'Scholarship',width:260,sortKey:'scholarship'}")
  expect(ui).toContain(".concat(type==='scholarship'&&schDetail&&!completenessMode?SCH_DETAIL_COLS:[])")
  expect(ui).toContain('data-sch-detail-cols')
  expect(ui).toContain("{['course','scholarship'].includes(type)&&<button className={`m-filter-toggle")
  for (const k of ['sch_award_type', 'sch_sponsor', 'sch_benefits', 'sch_method', 'sch_duration', 'sch_nat_status', 'sch_detail']) {
    expect(ui).toContain(`{key:'${k}'`)
    expect(ui).toContain(`if(key==='${k}')`)
  }
  expect(ui).toContain("['awardType','award_type'],['nationalityStatus','nationality_status'],['applicationMethod','application_method']")
  expect(ui).toContain("if(type==='scholarship'){for(const[k,arg]of SCH_DETAIL_ARGS)")
  expect(ui).toContain("opt('not_held','Not held yet')")
})
