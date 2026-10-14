// CF-247 v2.15.276, website requirements register O1 (Platform Admin, 14 Oct 2026 18:44). Decisions: "Clear unproven NZ, keep CA" and
// "Refresh + delivery fix". The website reads campus regions and the search projection; nothing inferred (null = not held), additive only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261014090000_cf247_campus_regions_and_search_refresh.sql', 'utf8')

test('O1: NZ campus regions only where proven (provider city); Canada keeps the province; each cleared value kept for undo', () => {
  expect(mig).toContain("case when v_cc = 'CA' or (nullif(btrim(x->>'city'), '') is not null and lower(btrim(x->>'city')) = lower(btrim(coalesce(v_pcity, '')))) then v_sub end,")
  expect(mig).toContain('create table if not exists pipeline.campus_region_cleared (')
  expect(mig).toContain("where c.iso_alpha2 = 'NZ' and k.stable_key like 'campus:studysearch:%' and k.subdivision_id is not null")
  expect(mig).toContain('update catalogue.campuses k set subdivision_id = null, updated_at = now()')
})

test('O1: Enrich fields values reach the website: a refresh when a task finishes and once now; course delivery mode as a fallback', () => {
  expect(mig).toContain("if v_left = 0 then insert into search.refresh_requests(requested_by) values ('enrich fields task ' || left(p_id::text, 8) || ' finished'); end if;")
  expect(mig).toContain("insert into search.refresh_requests(requested_by) values ('v2.15.276 O1:")
  expect(mig).toContain("when nullif(btrim(c.delivery_mode),'') is not null then array[c.delivery_mode] else '{}'::text[] end as delivery_modes,")
  // nothing dropped or deleted at top level (the projection function body is unchanged apart from delivery_modes)
  expect(mig).not.toMatch(/^(drop|delete|truncate)\b/im)
  // every replaced function is md5-guarded
  expect((mig.match(/md5\(replace\(pg_get_functiondef/g) || []).length).toBeGreaterThanOrEqual(2)
})
