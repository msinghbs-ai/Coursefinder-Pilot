import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = (f) => fs.readFileSync(f, 'utf8')
const mig = () => read('supabase/migrations/20260929171000_cf247_admin_university_group_filter.sql')

test('admin university group migration is checksum-guarded and anchor-checked', () => {
  const s = mig()
  const guards = {
    'public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean)': '6ff62cea57316381b0bd325b14ca9f74',
    'security.admin_providers_page(integer,integer,text,text,text,text,text,text,text)': 'ba36984a18ac8cef171bfa145021865a',
    'security.admin_course_page_fast(jsonb)': 'bebe5d0052f67ae4e54e631c9c6c5196',
    'security.admin_course_page_fast_base(jsonb)': '0d15eecf6399220f49b10cb9498458c5',
    'security.admin_course_page_unfiltered_fast(jsonb)': '22fc87ea9a658132727cbf5297e4c010',
    'security.admin_catalogue_page(text,jsonb)': '4c4de487258a12b0792ac5261c8f165e',
    'security.admin_catalogue_filter_page(jsonb)': '10ed9613c23426205bacd4db06f1b785',
    'security.admin_provider_detail(uuid)': '59ce87e80cd8d3a84b1304be7844bc21',
  }
  for (const [sig, md5] of Object.entries(guards)) {
    expect(s).toContain(`(select md5(prosrc) from pg_proc where oid='${sig}'::regprocedure)<>'${md5}' then`)
  }
  // anchors must match exactly once
  expect(s).toContain("create or replace function pg_temp.cf_patch(v text, a text, b text, label text)")
  expect(s).toContain("raise exception 'anchor not found exactly once: %',label")
  // guards run before any replacement
  expect(s.indexOf("admin_provider_detail changed since review")).toBeLessThan(s.indexOf('drop function public.ui_courses_decision_page'))
})

test('admin university group migration: filters, options and additive display fields', () => {
  const s = mig()
  expect(s).toContain('create or replace function security.university_group_provider_ids(p_group text)')
  expect(s).toContain("replace(ic.code,'au_','')=regexp_replace(lower(btrim(coalesce(p_group,''))),'^au_','')")
  expect(s).toContain("revoke all on function security.university_group_provider_ids(text) from public;")
  // trailing defaulted parameters keep existing callers working; privileges are restored and checked
  expect(s).toContain("p_has_link boolean DEFAULT NULL::boolean, p_university_group text DEFAULT NULL::text)")
  expect(s).toContain("p_direction text DEFAULT 'asc'::text, p_university_group text DEFAULT NULL::text)")
  expect(s).toContain("raise exception 'ui_courses_decision_page privileges differ from the replaced function'")
  expect(s).toContain("raise exception 'admin_providers_page privileges differ from the replaced function'")
  // course list: filter leaves the unfiltered shortcut, fast path filters, legacy sort passes through
  expect(s).toContain("    and nullif(p_args->>'university_group','') is null\n")
  expect(s).toContain("and (v_group is null or c.provider_id in (select security.university_group_provider_ids(v_group)))")
  expect(s).toContain('v_sort,v_dir,v_has_state,v_has_link,v_group')
  // provider list
  expect(s).toContain("or p.id in (select security.university_group_provider_ids(p_university_group)))")
  expect(s).toContain("coalesce(nullif(p_args->>'sort',''),'provider'),v_dir,nullif(p_args->>'university_group',''));")
  // filter options
  expect(s).toContain("elsif v_kind='university_group' then")
  expect(s).toContain("'meta',provider_count||case when provider_count=1 then ' university' else ' universities' end")
  expect(s).toContain("'count',course_count")
  // additive display
  expect(s).toContain("'university_groups',security.provider_university_groups(p_provider_id),")
  expect(s).toContain('security.provider_university_groups(pg.provider_id) university_groups')
  expect(s).toContain("jsonb_build_object('university_groups',security.provider_university_groups(o.id))")
})

test('admin console wires the University group filter and provider detail display', () => {
  const ui = read('src/mature-main.jsx')
  const lib = read('src/lib/supabase.js')
  const css = read('src/mature.css')
  expect(lib).toContain('university_group: args.universityGroup || args.university_group || null,')
  expect(ui.match(/<PagedFilterSelect kind="university_group" label="University group" value=\{filters\.universityGroup\|\|''\}/g)?.length).toBe(2)
  expect(ui).toContain("onChange={(v,l)=>patch('universityGroup',v,l)}")
  expect(ui).toContain("if(filters.universityGroup&&['course','provider'].includes(type))a.university_group=filters.universityGroup;")
  expect(ui).toContain("universityGroup:'University group'")
  expect(ui).toContain("{value:'go8',label:'Group of Eight'}")
  expect(ui).toContain('universityGroup:UNIVERSITY_GROUP_OPTIONS')
  expect(ui).toContain('<small>University group</small><strong><UniversityGroups value={data.university_groups}/></strong>')
  expect(ui).toContain("{key:'university_groups',label:'Group',width:110}")
  expect(ui).toContain('className="m-status status-info"')
  // University group sits next to Provider and stays visible when advanced filters are collapsed
  const bar = ui.slice(ui.indexOf('m-course-filters'))
  expect(bar.indexOf('kind="provider"')).toBeLessThan(bar.indexOf('kind="university_group"'))
  expect(bar.indexOf('kind="university_group"')).toBeLessThan(bar.indexOf('kind="level"'))
  expect(css).toContain('.m-course-filters:not(.expanded)>.m-filter-select:nth-child(n+6){display:none}')
})
