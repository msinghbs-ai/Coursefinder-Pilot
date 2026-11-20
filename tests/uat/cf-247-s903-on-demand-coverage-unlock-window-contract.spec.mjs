// Guards: CF-247 s903 (Platform Admin 21 Nov 2026 07:48, chat S1-Coverage-Unlock-UI-Notes; decision "On-demand, up to 20,000"): an on-demand
// request with a Firecrawl cap stops covering spend once its recorded use reaches the cap; one window for the universities with coverage gaps,
// Firecrawl only, purpose groups central, scholarships and reads (never course page search), capped at 20,000 credits; no setting changed
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121102000_cf247_s903_on_demand_coverage_unlock_window.sql', 'utf8')

test('the cap: an md5-guarded edit of security.on_demand_request_for_v2; requests without a cap are unchanged', () => {
  expect(MIG).toContain("select pg_temp.edit_once('security.on_demand_request_for_v2(uuid,text)', '2b6d99d5302434bed1040625a0248338', '3a41986e53e8dc4629c120db84176bd2', array[")
  expect(MIG).toContain("and (r.estimate->>'cap_firecrawl_units' is null")
  expect(MIG).toContain("or coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.on_demand_request = r.id), 0) < (r.estimate->>'cap_firecrawl_units')::numeric)")
  expect(MIG).toContain('create index if not exists coverage_vendor_usage_on_demand_request_idx on pipeline.coverage_vendor_usage (on_demand_request) where on_demand_request is not null;')
})

test('the window: gap universities in AU, NZ and CA, Firecrawl only, three purpose groups, capped at 20,000; no setting changed', () => {
  expect(MIG).toContain("where p.lifecycle_status = 'active' and k.iso_alpha2 in ('AU', 'NZ', 'CA') and security.scholarship_university(p.id)")
  expect(MIG).toContain("jsonb_build_object('firecrawl_units', 20000, 'cap_firecrawl_units', 20000,")
  expect(MIG).toContain("null, '{firecrawl}');")
  expect(MIG).toContain("perform security.on_demand_scope_v1(v_id, '{central,scholarships,reads}');")
  expect(MIG).toContain("if security.on_demand_request_for_v2(v_ids[1], 'course_link_search') is not null then raise exception 'post-check: course page search is covered'; end if;")
  expect(MIG).not.toMatch(/update\s+pipeline\.platform_toolset_settings|insert\s+into\s+pipeline\.platform_toolset_settings/i)
  expect(MIG).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: .+$/m)
})
