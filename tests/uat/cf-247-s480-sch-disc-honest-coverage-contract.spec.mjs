// Guards: Controller instruction 8 Nov 2026 14:06 (lane SCH/DISC: honest per-provider scholarship states, "recover productive eligible work without uncontrolled re-crawls",
// no repeated zero-yield crawl) and IQ-00129 (transient and budget failures became permanent): a provider outside scholarship search by policy, or searched with no result, no longer reads
// "source not discovered"; suggested listings of eligible providers become listing sources only under a switch that ships off, once each, within the scholarship Firecrawl share; an unchanged
// complete catalogue is not re-read weekly; a candidate page that stopped on a time-out, server error or credit refusal gets a bounded, recorded second chance (switch off). The behaviour runs on
// isolated fixtures by tests/fixtures/sch-disc/run.sh (scratch PostgreSQL 16; three live definitions loaded from their live text and checked against the live md5s; the defects reproduced on them;
// the migration applied, then applied again unchanged; every case asserted). This spec holds the contract; G2, G3 and housekeeping are guarded centrally (s32, s57, s42).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261108160000_cf247_sch_disc_honest_coverage_and_recovery.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/sch-disc'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')
// executable text: comments removed, so a rule is asserted on code and not on the explanation
const code = m.replace(/^\s*--.*$/gm, '').replace(/\s--[^\n']*$/gm, '')

const EDITS = {
  'security.scholarship_coverage_items_v1(uuid[])': ['5605660603d40b3917001c37807a09bb', '6931746c40448bd7182472dd1f8b433e', 'security.scholarship_coverage_items_v1'],
  'security.scholarship_coverage_classify_v1(uuid[])': ['7cd322359de3c7f823df240452afc2a8', 'e305eb1354ba06dc5922d0d7b7f3ed19', 'security.scholarship_coverage_classify_v1'],
  'public.svc_scholarship_listing_record_v2(bigint,text,integer,jsonb,text,jsonb)': ['9207e7fd49ffa0ba7ae5f3aae4bbcbf6', '97b5f8cefd83b74c7e09f27a391ab69c', 'public.svc_scholarship_listing_record_v2'],
}

test('three live definitions are edited, md5-guarded both ways, from the live text the fixture loads', () => {
  for (const [sig, [b, a, file]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}'`)
    expect(run).toContain(`]=${b}`)
    expect(m).toContain(`'${sig}'::regprocedure)) <> '${a}' then raise exception 'post-check`)
    expect(md5(fs.readFileSync(`${FX}/live/${file}.def`, 'utf8'))).toBe(b)
    expect(m).toContain(`--   ${sig}`)
  }
  // the guard refuses a live definition that is neither the before nor the after text
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)'")
  expect(m).toContain("if md5(v_def) = p_after then return p_sig || ': already applied'")
})

test('every edit is exact-count and replaces text only inside the three definitions (no new behaviour hidden in a rewrite)', () => {
  expect(m).toContain('edit % must apply exactly % times (found %)')
  expect(m).toMatch(/array\[1, 1\]\);/) // items: two edits once each
  expect(m).toMatch(/array\[1\]\);/) // classify and listing record: one edit once each
})

test('two resolved states: searched_none needs a successful map and never a refusal; not_in_scope names the policy; neither escalates', () => {
  expect(m).toContain("dp.status = 'empty' and coalesce(dp.method, '') ~ 'map_search[(]' and coalesce(dp.method, '') !~ 'map:'")
  expect(m).toContain("security.scholarship_scope_v1(pv.id) <> 'in_scope' then 'not_in_scope'")
  expect(m).toMatch(/\('searched_none', .*, true, .*'never', 'succeeded', 131\)/s)
  expect(m).toMatch(/\('not_in_scope', .*, true, .*'never', 'succeeded', 132\)/s)
  // the provider state reads them before the old fallback
  expect(m).toContain("when p.states ? 'searched_none' then 'searched_none'")
  expect(m).toContain("when p.states ? 'not_in_scope' then 'not_in_scope'")
  // the reasons are the refill's own gates, named
  for (const r of ['unknown_provider', 'no_website', 'directory_site', 'country_not_open', 'discovery_not_eligible', 'country_or_type_not_admitted', 'no_active_courses', 'below_course_minimum', 'in_scope'])
    expect(m).toContain(`'${r}'`)
  expect(fixtures).toContain('map:budget')
  expect(fs.readFileSync(`${FX}/seed.sql`, 'utf8')).toContain("'map:budget'")
})

test('the new spend paths ship off and are switches in settings (G2 keys), never in the job command', () => {
  expect(m).toMatch(/'retry\.scholarship_transient_recover_on'.*to_jsonb\(0\)/s)
  expect(m).toContain("security.pipeline_num_v1('sch_cov.recover_listings_on', 0) < 1 then return")
  expect(m).toContain("security.pipeline_num_v1('retry.scholarship_transient_recover_on', 0) < 1 then return")
  expect(m).toMatch(/'sch_cov\.scope_states_on'.*to_jsonb\(1\)/s) // classification only, ships on
  expect(code).not.toMatch(/update\s+pipeline\.platform_toolset_settings/i) // no setting is switched by this change
  expect(m).toContain("'33 * * * *', 'select security.scholarship_listing_accept_v1()'")
  expect(m).toContain("'37 * * * *', 'select security.scholarship_transient_recover_v1()'")
})

test('listing accept: eligible, own site, not held, not hidden, share not held, each once, capped; admits nothing', () => {
  const f = m.slice(m.indexOf('create or replace function security.scholarship_listing_accept_v1'), m.indexOf('revoke all on function security.scholarship_listing_accept_v1'))
  for (const part of ["security.lane_paid_hold_v1('sch_scrape')", 'security.scholarship_admission_provider_ok_v1(r.provider_id)', 'security.fc_sch_held_v1(r.provider_id, true)', 'security.provider_sch_search_off_v1(r.provider_id)',
                      'security.provider_hidden_v1', 'security.third_party_host_v1(r.url)', 'security.url_on_provider_sites(r.url, r.provider_id)', "l.source = 'suggested' and not l.active",
                      "x.action = 'promote_listing'", "on conflict (item_key, action) do nothing", "'batch.sch_coverage_recover'", "'sch_cov.recover_per_provider_max'"])
    expect(f).toContain(part)
  expect(f).not.toMatch(/scholarship\.scholarships|publication_status|admit_status|insert into scholarship\./)
})

test('transient recover: only transient classes, parked, bounded per page and per run, share and provider checks, outcomes recorded', () => {
  const f = m.slice(m.indexOf('create or replace function security.scholarship_transient_recover_v1'), m.indexOf('revoke all on function security.scholarship_transient_recover_v1'))
  expect(f).toContain('c.http_status in (402, 408, 425, 429, 500, 502, 503, 504, 520, 522, 524)')
  expect(f.replace(/--.*$/gm, '')).not.toMatch(/\b(403|404|410)\b/) // a refusal and a missing page are not transient (code only, not the comment that says so)
  for (const part of ["security.lane_paid_hold_v1('sch_scrape')", "'retry.scholarship_transient_park_hours'", "'retry.scholarship_transient_cycles_max'", "'batch.scholarship_transient_recover'", "'sch_cov.recover_per_provider_max'",
                      'security.fc_sch_held_v1(r.provider_id, true)', 'security.provider_sch_search_off_v1(r.provider_id)', 'security.third_party_host_v1(r.url)', "'failed_again'", "'read'", 'outcomes_recorded'])
    expect(f).toContain(part)
  expect(f.indexOf('update pipeline.scholarship_read_retry_cycles y set outcome')).toBeLessThan(f.indexOf("retry.scholarship_transient_recover_on', 0) < 1")) // outcomes are recorded even with the switch off
  // every fixed number in the function is marked with why
  for (const line of f.split('\n').filter((l) => /attempts >= 3|interval '1 hour'/.test(l))) expect(line).toContain('-- fixed:')
  expect(f).not.toMatch(/insert into scholarship\.|admit_status\s*=|publication_status/)
})

test('beside the consumer API, retiring nothing, dropping nothing', () => {
  expect(m).toContain('-- Replaces: ')
  expect(m).toContain('-- Retires: nothing')
  expect(code).not.toMatch(/\b(drop|truncate)\s+(table|function|view|schema|column)\b|\bdelete\s+from\b|\balter\s+table\b/i)
  expect(code).not.toMatch(/(create|alter|drop)\s+(or\s+replace\s+)?(function|view|table)\s+(public\.website_v2_|public\.website_edge_|public\.website_api_v2_|public\.zoho_edge_|api\.)/i)
  expect(m).toContain("comment on table pipeline.scholarship_read_retry_cycles is")
})

test('the fixture proves it: defects before, the migration applied twice, the cases after', () => {
  for (const d of ['D1', 'D4', 'D2/D5']) expect(before).toContain(`before ${d}`)
  expect(run).toContain('did not apply its three guarded edits')
  expect(run).toContain('already applied$')
  for (const c of ['R0 switch 0', 'R1 the scholarship Firecrawl share is held', 'R2 three of Theta', 'R3 batch cap 1', 'R5 a second run accepts nothing more', 'T0 switch 0', 'T1 the scholarship Firecrawl share is held',
                   'T2 three pages released', 'T4 outcomes are recorded', 'T5 raising the cycle limit', 'a refusal (403) and a missing page (404) are not transient', 'the unchanged interval is the setting, not code',
                   'Beta: an "empty" row whose method is map:budget', 'sch_cov.scope_states_on 0'])
    expect(fixtures).toContain(c)
})
