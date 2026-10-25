// CF-247 hotfix v2.15.351 (consolidated mandate 25 Oct 2026, Part A): the course list shows International fee and City on every sort.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261025001000_cf247_list_columns_on_every_sort.sql', 'utf8')
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('the Completeness / Tuition Only branch adds the same columns as the normal path, from the same rows', () => {
  expect(m).toMatch(/pg_temp\.edit_n\('security\.admin_course_page_search_state\(jsonb\)', '[0-9a-f]{32}'/)
  expect(m).toContain("'intl_fee_amount', ifee.amount, 'intl_fee_currency', ifee.currency_code::text, 'intl_fee_year', ifee.fee_year, 'intl_fee_basis', ifee.basis")
  expect(m).toContain("'city_names', gcity.city_names")
  expect(m).toContain("cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1")
  expect(m).toContain("string_agg(distinct ca.city, ', ') city_names from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id")
  expect(m).toMatch(/-- Replaces: .*\n-- Retires: nothing/)
})

test('the list columns stay as they are (structure frozen) and sort', () => {
  expect(ui).toContain("{key:'intl_fee_amount',label:'International fee',width:190,sortKey:'intl_fee'}")
  expect(ui).toContain("{key:'city_names',label:'City',width:150,sortKey:'city'}")
})
