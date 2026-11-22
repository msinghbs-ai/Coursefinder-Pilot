// Guards: REQ-105 and Platform Admin batch of 22 Nov 2026 22:01 AEDT (Part 1: filtered and sorted Courses lists on the set-based state path; Part 2: the Counsellor and Viewer counselling filter bar) and its 22:57 addendum (Settings › API usage in one compact table)
// s977 (S2-Build): measured live 23 Nov 2026, Australia + New South Wales by International fee took 2.6 to 7.3 s (the state tested once per course
// of the country, and a generic cached plan); after the change 0.26 s for the list and 0.35 s through admin_read, across eight calls, in a
// rolled-back rehearsal, with the same rows, order and totals on eight lists. Counsellors and Viewers see seven counselling filters; Operators
// and Platform Admins keep every filter. API usage shows each key once in one table; legacy keys and traffic detail fold.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123000000_cf247_s977_courses_filtered_fast.sql', 'utf8')
const MAIN = fs.readFileSync('src/mature-main.jsx', 'utf8')
const UI = fs.readFileSync('src/ApiUsagePanel.jsx', 'utf8')
const REF = fs.readFileSync('src/guide/filterReference.js', 'utf8')

test('s977 migration: md5-guarded in-place edits, the set-based state path, the counselling filters, parity, G3 and guardrails', () => {
  for (const h of ["'a0f64b1a4cfd4965ce24000466246d72'", "'0df468929bc1f30b769496a0d7be109c'", "'48eb54ebba0864615507586bebda0455'", "'5635f8ff45f967ffe8e2b9737883f060'"]) expect(MIG).toContain(h)
  expect(MIG).toContain('with sub_ids as materialized (')
  expect(MIG).toContain("and (nullif(trim(coalesce(p_args->>'subdivision_code','')),'') is null or c.id in (select s.course_id from sub_ids s))")
  expect(MIG).toContain(" SET plan_cache_mode TO 'force_custom_plan'")
  for (const a of ["p_args->>'fee_min'", "p_args->>'fee_max'", "p_args->>'intake_month'", "p_args->>'intake_year'", "p_args->>'english_test'", "p_args->>'english_score'"]) expect(MIG).toContain(a)
  expect(MIG).toContain("and nullif(p_args->>'english_test','') is null")          // the counselling filters take the bounded path
  expect(MIG).toContain("elsif v_kind='english_test' then")
  expect(MIG).toContain('create index if not exists course_fees_intl_current_idx on catalogue.course_fees')
  expect(MIG).toContain("alter function public.website_v3_course_search_core(jsonb, integer, integer, text) set plan_cache_mode = 'force_custom_plan';")
  expect(MIG).toContain("raise exception 'parity: % answers different rows (total % / %)'")
  expect(MIG).toContain("raise exception 'post-check: the consumer API moved: %'")
  expect(MIG).toContain("raise exception 'post-check: the manual locks changed'")
  expect(MIG).toContain("raise exception 'post-check: the number of active cron jobs changed'")
  expect(MIG).not.toMatch(/create or replace function public\.website_v2/i)              // G3: no v2 consumer function is changed
  expect(MIG).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
})

test('s977 Courses: Counsellors and Viewers get the counselling bar; the server arguments; every label is in the Filter & Badge Reference', () => {
  expect(MAIN).toContain("if(Number(rank)<=2)return <CounselFilters filters={filters}")
  for (const l of ['Destination country', 'University / provider', 'Field of study', 'Intake month', 'Intake year', 'Fee order', 'English test']) expect(MAIN).toContain(`label="${l}"`)
  expect(MAIN).toContain('Clear / Reset</button>')
  expect(MAIN).toContain("export function counselArgs(filters={}){const a={};for(const[k,arg]of[['feeMin','fee_min'],['feeMax','fee_max'],['intakeMonth','intake_month'],['intakeYear','intake_year']])"); expect(MAIN).toContain("...(type==='course'?counselArgs(filters):{})")
  expect(MAIN).toContain('a.english_test=filters.englishTest')
  expect(MAIN).toContain('intakeYears(lk)')                                                      // rolling years from the lookups, no year written
  expect(MAIN).toContain("onSortTo?.('intl_fee',v)")
  for (const l of ['Destination country', 'University / provider', 'Fee from', 'Fee up to', 'Fee order', 'English test', 'Student score', 'Intake month', 'Intake year']) expect(REF).toContain(`e('Courses', '${l}'`)
  for (const g of ['PRISMS', 'QILT', 'THE', 'QS', 'Publication', 'Empty reason', 'Zoho / Website feed matched', 'Contacts']) expect(REF).toContain(`e('Glossary', '${g}'`)
  expect(fs.readFileSync('src/DetailSummary.jsx', 'utf8')).toContain('data-provider-courses-link')
  expect(fs.readFileSync('src/ProviderContactsWorkspace.jsx', 'utf8')).toContain('Clear / Reset</Btn>')
})

test('s977 API usage: one table, each metric once, legacy keys folded, nothing scrolls sideways', () => {
  expect(UI).toContain('className="cf-api-summary"')
  for (const h of ['Consumer &amp; version', 'Key &amp; status', 'Calls (7 d / 30 d)', 'Error %', 'p95', 'Last used', 'Action']) expect(UI).toContain(`<th>${h}</th>`)
  expect(UI).toContain('<details className="cf-api-legacy" data-api-legacy><summary>Legacy {legacyNames} keys ({fmtNumber(legacyKeys)})</summary>')
  expect(UI).not.toContain('cf-metric-grid')
  expect(UI).not.toContain('<Metric ')
  const css = fs.readFileSync('src/settings.css', 'utf8')
  expect(css).toContain('.cf-api-summary{width:100%;min-width:0;table-layout:fixed')
  expect(css).toContain('.cf-api-summary td::before{content:attr(data-label)')
})
