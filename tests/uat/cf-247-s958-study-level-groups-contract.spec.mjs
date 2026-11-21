// Guards: CF-247 s958 (Platform Admin 21 Nov 2026 21:15, Lane 1 item 2; India team review of 20 Nov 2026, REQ-100; Dynamic Database-Driven Lookups): the Study level filters show every level in one list under its group (Pathway, Vocational, Undergraduate, Postgraduate, Other), the groups held in ref.study_level_groups, with no codes and no second page, on Courses and Entry requirements
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261122070000_cf247_s958_study_level_groups.sql', 'utf8')
const src = f => fs.readFileSync(`src/${f}`, 'utf8')

test('the groups are data: a commented table filled once, a level with no row reads as Other', () => {
  expect(MIG).toContain('create table if not exists ref.study_level_groups (')
  expect(MIG).toContain('comment on table ref.study_level_groups is')
  for (const g of ["'pathway', 'Pathway', 10", "'vocational', 'Vocational', 20", "'undergraduate', 'Undergraduate', 30", "'postgraduate', 'Postgraduate', 40", "'other', 'Other', 90"]) expect(MIG).toContain(g)
  expect(MIG).toContain('on conflict (level_code) do nothing;')
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
})

test('the server reads: the level filter pages up to 100 with its group; the entry options carry the group; md5-guarded', () => {
  expect(MIG).toContain("select pg_temp.edit_re('security.admin_catalogue_filter_page(jsonb)', '244538bdc97f9e889de2f4fa8fdec716'")
  expect(MIG).toContain("case when lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''))='level' then 100 else 10 end")
  expect(MIG).toContain("'group',meta,'group_order',group_order")
  expect(MIG).toContain("select pg_temp.edit_re('public.admin_aer(text,jsonb)', '8aba9ae6ad9b8f21fd1996ae9d93aa82'")
  expect(MIG).toContain("'group', coalesce(g0.group_name, 'Other')")
  const body = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(body).not.toMatch(/\$n\$[^$]*--/)
  expect(body).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b|cron\.schedule\(/i)
})

test('the screens: Courses shows group headings and one page; Entry requirements orders levels by group, no codes', () => {
  const m = src('mature-main.jsx'), a = src('AerWorkspace.jsx'), d = src('DataTable.jsx')
  expect(m).toContain('const PAGE_OF={level:100}')
  expect(m).toContain('data-filter-group={x.group}')
  expect(m).toContain('{x.meta&&!x.group&&<small>{x.meta}</small>}')
  expect(a).toContain('<FilterSelect label="Study level" value={f.level} onChange={(v,l)=>set(\'level\',v,l)} pageSize={60} options={levelOptions(o)}/>')
  expect(a).not.toContain("opt(l.code,l.name,l.code)")
  expect(d).toContain("help='',pageSize=10}")
})
