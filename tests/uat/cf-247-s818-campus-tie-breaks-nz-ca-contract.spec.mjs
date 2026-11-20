// Guards: CF-247 s818 (Platform Admin 20 Nov 2026 09:55 and 10:48, chat S1-Build): tied main campuses settled by register data ($0), the rest
// shown by the Catalogue › Providers Main campus filter; NZ and CA courses with no campus take their provider's only campus; NZ campus regions
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120115000_cf247_s818_campus_tie_breaks_nz_ca_projection.sql', 'utf8')
const MAIN = fs.readFileSync('src/mature-main.jsx', 'utf8')
const fn = (n) => { const a = MIG.indexOf(`create or replace function security.${n}(`); expect(a).toBeGreaterThan(-1); return MIG.slice(a, MIG.indexOf('end $f$;', a)) }

test('tie-breaks among the tied campuses only: registered city, register head office address, then the earliest registered co-located campus', () => {
  const t = fn('campus_primary_tiebreak_v1')
  expect(t).toContain('where z.rk = 1 and z.t > 1')
  expect(t).toContain('coalesce(lower(btrim(k.city)) = lower(btrim(p.primary_city)), false) city_match')
  expect(t).toContain("case when bool_or(c.addr_match) filter (where c.keep1) over (partition by c.provider_id) then c.addr_match else true end keep2")
  expect(t).toContain("when ncity = 1 and not nocity then 'earliest_registered_campus'")
  // never a second main campus, never a locked campus, nothing already set changes
  expect(t).toContain("and not exists (select 1 from catalogue.campuses y where y.provider_id = x.provider_id and y.is_primary);")
  expect(t).toContain("where l.entity = 'campus' and l.field in ('is_primary', 'primary_basis') and x.provider_id = p.id")
  // the catalogue's allowed basis values are not changed; the tie-break is kept in the audit row
  expect(t).toContain("set is_primary = true, primary_basis = 'highest_course_count'")
  expect(t).toContain("'decisions', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', x.provider_id, 'campus_id', x.campus_id, 'tiebreak', x.basis))")
  expect(MIG).toContain("raise exception 'post-check: % providers have more than one main campus'")
})

test('NZ and CA courses with no campus take their provider\'s only active campus, unless online only or locked', () => {
  const p = fn('course_campus_sole_projection_v1')
  expect(p).toContain("k.iso_alpha2 in ('NZ', 'CA')")
  expect(p).toContain("c.empty_reason_code is distinct from 'online_only_no_campus'")
  expect(p).toContain("(select count(*) from catalogue.campuses x where x.provider_id = p.id and x.status = 'active') = 1")
  expect(p).toContain("l.field in ('campus', 'campuses', 'course_campuses', 'all')")
  expect(p).toContain("insert into search.course_refresh_requests (course_id, requested_at, requested_by)")
})

test('NZ campus regions only when every name points to one region; the city list is a setting', () => {
  const r = fn('campus_nz_region_fill_v1')
  expect(r).toContain("group by k.id, k.name having count(distinct s.id) = 1")
  expect(r).toContain("security.toolset_setting('pipeline', 'campus.nz_city_regions')")
  expect(MIG).toContain("('pipeline', 'campus.nz_city_regions',")
})

test('Catalogue › Providers › More filters › Main campus: Set, Unset, No active campus (admin_providers_page_v3 primary_campus)', () => {
  expect(MIG).toContain("select pg_temp.cf_edit_def('security.admin_providers_page_v3(jsonb)'::regprocedure, '2f525d0c17ce5505b92f0e34fd4a2d4e',")
  expect(MIG).toContain("if v_primary is not null and v_primary not in ('set','unset','none') then raise exception 'unsupported main campus filter: %'")
  expect(MAIN).toContain("const PRIMARY_CAMPUS_OPTIONS=[{value:'unset',label:'Unset (has campuses, none is the main one)'},{value:'set',label:'Set'},{value:'none',label:'No active campus'}]")
  expect(MAIN).toContain("['primaryCampus','primary_campus']])if(filters[k])a[arg]=filters[k]")
  expect(MAIN).toContain('<FilterSelect key="primaryCampus" label="Main campus"')
})
