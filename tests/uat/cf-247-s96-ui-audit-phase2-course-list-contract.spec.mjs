// CF-247 UI audit Phase 2 (Platform Admin 24 Oct 2026 11:27): the Courses list shows the fee with its basis and the campus city/state, both sortable.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024007000_cf247_ui_audit_phase2_course_list.sql', 'utf8')
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('migration: basis joins the list row; intl_fee and city sort; md5-guarded; nothing dropped; the website API untouched', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate|delete\s+from)\b/im)
  expect(m).toContain("select pg_temp.edit_n('security.admin_course_page_fast_base(jsonb)', 'a828eb5404a7999c81c2336b09b5f366', array[")
  expect(m).toContain("case when v_sort='intl_fee' and v_dir='asc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active'")
  expect(m).toContain("case when v_sort='city' and v_dir='asc' then (select min(lower(ca.city)) from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id where cc.course_id=numbered.id")
  expect(m).toContain("ifee.fee_year intl_fee_year,ifee.basis intl_fee_basis,gcity.city_names,")
  expect(m).not.toMatch(/website_v2|website_edge|api\./)
})

test('screen: International fee and City columns sort; the fee prints amount, year and basis; empty is a dash', () => {
  expect(ui).toContain("{key:'city_names',label:'City',width:150,sortKey:'city'}")
  expect(ui).toContain("{key:'intl_fee_amount',label:'International fee',width:190,sortKey:'intl_fee'}")
  expect(ui).toContain("{r.intl_fee_basis?<small className=\"m-fee-basis\"> · {feeBasisLabel(r.intl_fee_basis)}</small>:null}</span>:'—'")
  expect(ui).toContain("const FEE_BASIS={annual:'per year'")
  expect(ui).toContain("if(key==='city_names')return v||'—'")
})
