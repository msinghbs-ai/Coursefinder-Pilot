import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = (f) => fs.readFileSync(`supabase/migrations/${f}`, 'utf8')

test('consumer API update for the website developer: names, regional class, English summary, place names', () => {
  const a = m('20260929160000_cf247_api_provider_names_regional_class.sql')
  expect(a).toContain('create or replace function security.provider_presentable_name(p text)')
  expect(a).toContain("split_part(x,';',1)")
  expect(a).toContain('Migration (LIN 19/217: Regional Areas) Instrument 2019')
  for (const r of ["('AU-VIC',3211,3232,2,'Geelong')", "('AU-QLD',4207,4275,2,'Gold Coast')", "('AU-WA',6000,6038,2,'Perth')", "('AU-SA',5000,5171,2,'Adelaide')", "('AU-TAS',7000,7000,2,'Hobart')", "('AU-NSW',2311,2490,3,null)", "('AU-VIC',3430,3799,3,null)", "('AU-QLD',4580,4895,3,null)"]) expect(a).toContain(r)
  expect(a).toContain("when x.st='AU-VIC' then jsonb_build_object('category',1,'metro_area','Melbourne')")
  expect(a).toContain("when x.st='AU-ACT' then jsonb_build_object('category',2,'metro_area','Canberra')")
  const b = m('20260929161000_cf247_api_search_patch.sql')
  expect(b).toContain("'2ba07114c90a83926c038dac50fed2af'")
  expect(b).toContain("'legal_name',p.provider_name")
  expect(b).toContain("'regional_category',rc.category")
  expect(b).toContain("or lower(rc.metro_area) = any(v_cities)")
  expect(b).toContain("'basis',case when jsonb_array_length")
  expect(b).toContain('security.consumer_api_snapshot_v1()')
  const c = m('20260929162000_cf247_api_place_names.sql')
  expect(c).toContain("'a36efb8c473d2d5bc0354631048c8af9'")
  expect(c).toContain('security.place_presentable(k.city)')
})
