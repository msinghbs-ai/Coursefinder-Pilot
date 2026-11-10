// Guards: Platform Admin order 10 Nov 2026 12:07 (the EXISTING Data Delivery panel shows the provider-description AI cost, remaining allowance and the Basic -> Enriched outcome): source contract over migration 20261110150000, its forward recovery, the screen and the mock. The behaviour is proved by the PostgreSQL fixture tests/fixtures/pdesc-dd-ai/run.sh (run in CI by provider-description-integration.yml) and by the browser specs of the panel.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110150000_cf247_dd_provider_ai_allowance.sql', 'utf8')
const R = fs.readFileSync('supabase/held/dd_provider_ai_allowance_forward_recovery.sql', 'utf8')
const UI = fs.readFileSync('src/DataDelivery.jsx', 'utf8')
const WF = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const FN = M.slice(M.indexOf('create or replace function security.data_delivery_pdesc_v1'), M.indexOf('$pdesc$;', M.indexOf('as $pdesc$')))

test('the migration follows the house pattern: header, guarded edit of one function, one new read-only function, nothing dropped', () => {
  expect(M).toMatch(/^-- Replaces: security\.data_delivery_v1 is edited in place/m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  expect(M).toContain('--   security.data_delivery_v1() b67bd181c58546076da48e7b5f00a2a4 -> 849453412a8b9a448118e7b87362752a')
  expect(M).toContain('--   security.data_delivery_pdesc_v1() (new) -> 15b2f9882e77d7fcf0a8a4be2b6df18f')
  expect(M).toContain("if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)'")
  expect(M).toContain("if md5(v_src) = r.md5_after then continue; end if; -- already applied")
  expect(M).toContain('supabase/held/dd_provider_ai_allowance_forward_recovery.sql')
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/\balter\s+table\b/i)
  expect(M).not.toMatch(/^\s*(insert into|update)\s+(?!pipeline\.component_register)/im)   // the only write is the component register row
  expect(M.match(/create or replace function /g)).toHaveLength(1)
  // Admin only, read only, no grant
  expect(M).toContain('revoke all on function security.data_delivery_pdesc_v1() from public, anon, authenticated;')
  expect(M).not.toMatch(/\bgrant\b/i)
  expect(FN).toMatch(/language plpgsql stable security definer set search_path to ''/)
})

test('the edit adds one key for the stream pdesc after the course stages key and removes nothing', () => {
  expect(M).toContain("'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,")
  expect(M).toMatch(/array\[\$o\$ {6}'stages', case when s\.stream = 'cdesc' then security\.data_delivery_cdesc_stages_v1\(\) end,\$o\$\]/)
  // consumer API (G3): nothing the website or Zoho reads is named by the function
  expect(FN).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(FN).not.toMatch(/\b(insert|update|delete|truncate)\b/i)
})

test('no operational value is written into the function (G2): the ceiling, the daily guard, the number of reasons and the upgrade switch are settings', () => {
  expect(FN).toContain("security.pipeline_num_v1('pdesc.ai_usd_max', 1)")
  expect(FN).toContain("security.toolset_setting('openrouter', 'guard_provider_description')")
  expect(FN).toContain("security.pipeline_num_v1('data_delivery.reasons_shown', 3)")
  expect(FN).toContain("security.pipeline_num_v1('pdesc.registry_upgrade_on', 0)")
  expect(FN).toContain("l.source <> 'opening'")
  expect(FN).toContain("l.lane = 'provider_description'")
  // no limit of its own: the hold list is cut by the existing setting
  expect(FN).toMatch(/order by 2 desc, 1 limit v_top\)/)
  expect(FN).not.toMatch(/\blimit\s+\d/i)
  expect(FN).not.toMatch(/interval\s+'\d/i)
  // the only literal in the day boundary is marked fixed
  expect(FN).toMatch(/date_trunc\('day', now\(\) at time zone 'UTC'\) at time zone 'UTC'\), 0\) today\s*-- fixed:/)
})

test('the figures are the ones the order names, counted from the lane\'s own tables', () => {
  expect(FN).toContain("sum(r.reserved_usd), 0) usd, count(*) n from pipeline.provider_description_reads r where r.reserved_usd > 0")
  expect(FN).toContain("r.checks ? 'reservation_settlement'")
  expect(FN).toContain("'remaining_usd', greatest(0, ")
  expect(FN).toContain("r.state = 'admitted' and r.rule = 'missing'")
  expect(FN).toContain("l.tier <> 'registry_factual'")
  expect(FN).toContain("security.provider_description_basic_profile_v1(r.provider_id) is not null")
  // upgrade reads are the reads made after the profile admission, not the history that led to it
  expect(FN).toContain('r.created_at > l.created_at')
  // a person: a Layer 4 provider description approved with no admitted machine admission on the item
  expect(FN).toContain("i.field_code = 'provider_description' and i.status in ('approved', 'edited_approved')")
  expect(FN).toContain("m.review_item_id = i.id and m.outcome = 'admitted'")
  // a failure to count is shown as such
  expect(FN).toContain("'known', false, 'reason', 'The provider AI and upgrade counts could not be read: ' || sqlerrm")
})

test('the forward recovery restores the live Data Delivery function and is guarded by the md5 of what is live', () => {
  expect(R).toContain("if v not in ('849453412a8b9a448118e7b87362752a', 'b67bd181c58546076da48e7b5f00a2a4') then raise exception")
  expect(R).toContain("<> 'b67bd181c58546076da48e7b5f00a2a4' then raise exception 'post-check: the restored security.data_delivery_v1() does not match'")
  expect(R).toContain("'stages', case when s.stream = 'cdesc' then security.data_delivery_cdesc_stages_v1() end,")
  expect(R.slice(R.indexOf('CREATE OR REPLACE FUNCTION'))).not.toContain('provider_ai')   // the restored text has no new key
  expect(R).not.toMatch(/^\s*drop\b/im)
})

test('the existing panel draws the new key; a missing key is Not measured; nothing is a new panel', () => {
  expect(UI).toContain("{s.stream==='pdesc'&&<ProviderAi pa={s.provider_ai}/>}")
  expect(UI).toContain('data-dd-provider-ai="unknown"')
  expect(UI).toContain("pa==null||pa.known===false")
  expect(UI).toContain("function Usd({v,k}){return v==null?<em data-dd-unknown data-dd-money={k}>Not measured</em>")
  expect(UI).toContain("label=\"Machine rule\"") // shared Row chip
  expect(UI).toContain('actor="person"')
  expect((UI.match(/export default function/g) || []).length).toBe(1)
  // the course stages box still has its own marker, so it is not confused with the new box
  expect(UI).toContain('data-dd-stages="known"')
})

test('CI runs the fixture, this contract and the identity-seen spec', () => {
  expect(WF).toContain('run: bash tests/fixtures/pdesc-dd-ai/run.sh')
  expect(WF).toContain('tests/uat/cf-247-pdesc-dd-ai-contract.spec.mjs')
  expect(WF).toContain('tests/uat/cf-247-pdesc-identity-seen.spec.mjs')
})
