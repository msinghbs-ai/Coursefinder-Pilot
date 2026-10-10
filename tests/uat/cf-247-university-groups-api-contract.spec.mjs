import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = (f) => fs.readFileSync(`supabase/migrations-archive/${f}`, 'utf8')

test('university groups: official memberships and consumer API alignment', () => {
  const a = m('20260929170000_cf247_university_groups.sql')
  for (const c of ['au_go8', 'au_atn', 'au_iru', 'au_run']) expect(a).toContain(`('${c}',`)
  for (const u of ['https://go8.edu.au/about/the-go8', 'https://www.atn.edu.au/our-members/', 'https://iru.edu.au/our-universities/', 'https://run.edu.au/about-us/run-universities/']) expect(a).toContain(u)
  expect(a).toContain("('au_go8','04249J')")
  expect(a).toContain("expected 26 university-group memberships")
  const b = m('20260929172000_cf247_api_university_groups.sql')
  expect(b).toContain("'11ca4c7aed8d9998db7e4b6f8aac1d6a'")
  expect(b).toContain("'d0342eabc45c3caba89ab7d07d1287be'")
  expect(b).toContain("'33e7052d3bbdd0ba93fcb4a27c4953cc'")
  expect(b).toContain("f->'university_groups'")
  expect(b).toContain("'university_groups',security.provider_university_groups(p.provider_id)")
  expect(b).toContain("v_published boolean := coalesce((f->>'published_only')::boolean,false);")
  expect(b).toContain("jsonb_build_object('university_groups', coalesce((")
  expect(b).toContain('security.consumer_api_snapshot_v1()')
})
