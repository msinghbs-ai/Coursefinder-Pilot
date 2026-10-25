// CF-247 SP-1 (speed programme release 1; Platform Admin 25 Oct 2026 22:05 / 22:27 / 22:34): "no page published by the provider" gap cause
// and the conjoint rule (Layer 4 first run per provider, then the 60% rule; re-opened by any page found; never deleted), universities
// first, extra course domains, the AI page match widened over existing inventories, and the S4-3 mislabel fix (target_list_refused).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261025003000_cf247_sp1_no_page_conjoint_domains_mislabel.sql', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('no page published: first run per provider to Layer 4, 60% rule, held out of search, re-opened, never deleted', () => {
  expect(m).toContain("'no_page_first_run'")
  expect(m).toContain("v_trusted := v_sample > 0 and v_conf::numeric / v_sample >= security.pipeline_num_v1('bind.no_page_trust_pct', 0.6);")
  expect(m).toContain("return 'no_page_by_provider';")
  expect(m).toMatch(/pg_temp\.edit_n\('security\.search_stop_gate_v1\(uuid,uuid,boolean,boolean\)', '[0-9a-f]{32}'/)
  expect(m).toContain("and not security.no_page_hold_v1(co.id)  -- SP-1: recorded no page / conjoint, until a newer map")
  expect(m).toContain("create trigger course_links_no_page_reopen after insert or update of status on catalogue.course_links")
  expect(m).toContain("create trigger coverage_ai_match_no_page after insert or update of state on pipeline.coverage_ai_match")
  expect(m).toContain("'no page: not published by the provider'")
  expect(m).toContain("order by (pt.code = 'university') desc nulls last, count(*) desc loop") // universities first (22:34)
  expect(m).toContain("security.pipeline_num_v1('bind.no_page_first_runs_per_run', 10)") // Layer 4 never flooded
  expect(m).toMatch(/\('pipeline', 'bind\.no_page_on', [^\n]*'number', '0'::jsonb, 0, 1,/) // activation is the Platform Admin's step
})

test('conjoint rule: one Layer 4 decision per provider; binding to the parent page waits for SP-2 (identity kind)', () => {
  expect(m).toContain("'conjoint_rule_first_run'")
  expect(m).toContain("'no page: conjoint or double degree (no page of its own)'")
  expect(m).toContain('binding to the parent page comes with SP-2')
  expect(m).not.toMatch(/insert into catalogue\.course_links/i) // nothing is bound by this release
})

test('extra domains, widened AI match, mislabel fix; housekeeping', () => {
  expect(m).toContain('create or replace function public.admin_provider_extra_domain(p_provider uuid, p_domain text, p_reason text)')
  expect(m).toContain("if security.third_party_host_v1('https://' || v_d) then raise exception")
  expect(w).toContain('for (const dom of ((p as any).extra_domains || []) as string[]) {')
  expect(m).toContain("or security.bind_match_scope_v1(co.provider_id))  -- SP-1")
  expect(m).toContain("if p_reason not in ('target_list_refused', 'credits_reserve', 'scholarship_share', 'no_firecrawl_key')")
  expect(w).toContain('if (!anyProvider && !isTarget(providerId)) { await noteRefusal(purpose, providerId, "target_list_refused"); return { ok: false, why: "target_list_refused" } }')
  expect(w).not.toMatch(/p_error: "budget"|error: "budget"|"map:budget"/) // the old label is gone from the worker
  expect(m).toContain("('no-page-propose', 'Course pages', 36,")
  expect(m).toMatch(/^-- Replaces: nothing\n-- Retires: nothing$/m)
  expect(m).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_/)
})
