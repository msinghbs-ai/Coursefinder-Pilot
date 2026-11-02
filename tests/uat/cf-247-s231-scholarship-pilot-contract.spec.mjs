// Guards: Platform Admin decision 3 Nov 2026 08:44 §4 (phased non-university scholarships; legitimacy criteria)
// Scholarships beyond universities, phased: the two v2.15.413 proposals (P1 non-university admission, P2 evidence-based legitimacy) apply only to
// the providers listed in scholarship.pilot_provider_ids while scholarship.pilot_only is on; an empty list is nobody; turning pilot_only off is the
// wider activation. The stop conditions (wrong-provider admission, unsupported eligibility, budget and operational regressions) are read-only
// reports. The database behaviour runs on isolated fixtures by tests/fixtures/scholarship-pilot/run.sh (scratch PostgreSQL: today's live
// definitions rebuilt and checked against the live md5s read on 3 Nov 2026 08:47 AEDT); this spec holds the contract and the fixtures' case lines.
// G2, G3 and housekeeping are guarded centrally (s32, s57, s42) and not re-asserted here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103090000_cf247_scholarship_nonuni_pilot.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/scholarship-pilot'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')

// [definition, live md5 before (3 Nov 2026 08:47 AEDT), md5 after]
const CHANGED = [
  ['security.scholarship_admission_provider_ok_v1(uuid)', '804be95b3e78fb9efe3ea0d967cbe666', '269f74a985acbc37f1f3b8615efa6254'],
  ['security.fc_sch_eligible_v1(uuid)', '8064816107a9b44bb2aeccbfa4a2d867', '2c44de24ea2d1bda123e1c8679591a9f'],
  ['security.fc_provider_tier_v1(uuid)', '3d0aa9dc690e23df4fd0c7248aaa7300', '2d71dcbd8aab00516c8222f68b6cc51b'],
  ['security.scholarship_discovery_refill_v1(integer)', '46a66f131b574375db6e9edbc2ad3f36', '5a72808f07e2f5219518ed3fc20fcdb7'],
  ['security.scholarship_admit_from_provider_page_v1(bigint)', '5b3557c1ea4488f3e9b751ad9e7371e9', '0741db9c35ef91eba6caa55b04fde869'],
]

test('five md5-guarded changes from today\'s live text; the fixture run rebuilds the same live definitions and applies the migration twice', () => {
  const guarded = [...m.matchAll(/select pg_temp\.(?:replace|edit)_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(guarded.sort()).toEqual([...CHANGED].sort())
  expect(m).not.toContain('__AFTER')
  const live = JSON.parse(fx('live-md5s.json'))
  for (const [sig, before] of CHANGED) expect(live[sig], sig).toBe(before)
  const run = fx('run.sh')
  expect(run).toContain('[ "$BEFORE" = "$LIVE" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }')
  expect(run).toContain("grep -c ': applied' | grep -qx 5")
  expect(run).toContain("grep -c 'already applied' | grep -qx 5")
  expect(run).toContain('MIG0=../../../supabase/migrations/20261103050000_cf247_scholarship_recovery.sql')
  expect(m).toMatch(/^-- Replaces: security\.scholarship_admission_provider_ok_v1, security\.fc_sch_eligible_v1, security\.fc_provider_tier_v1, security\.scholarship_discovery_refill_v1, security\.scholarship_admit_from_provider_page_v1 \(same names; md5-guarded\)$/m)
})

test('nothing is switched on: the list ships empty, pilot only on, both proposals stay off; no Firecrawl or AI limit is written', () => {
  expect(m).toMatch(/'scholarship\.pilot_provider_ids'[\s\S]{0,700}?'list', '\[\]'::jsonb/)
  expect(m).toMatch(/'scholarship\.pilot_only'[\s\S]{0,700}?'boolean', 'true'::jsonb/)
  expect(m).toContain("raise exception 'scholarship pilot post-check: the two proposals must stay off")
  expect(m).toContain("raise exception 'scholarship pilot post-check: the pilot list must ship empty'")
  expect(m).toContain("raise exception 'scholarship pilot post-check: the pilot must not start on apply'")
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/)
  expect(m).not.toMatch(/cron\.(schedule|alter_job)\(/)
})

test('the pilot scope sits in both proposals and nowhere else decides it; empty list = nobody', () => {
  expect(m).toContain("select not security.scholarship_flag_v1('scholarship.pilot_only', true) or security.scholarship_pilot_member_v1(p_provider_id)")
  expect(m).toMatch(/scholarship_flag_v1\('scholarship\.non_university_admission', false\)\n\s+-- CF-247 scholarships beyond universities[^\n]*\n\s+and security\.scholarship_pilot_scope_v1\(p_provider_id\)/)
  expect(m).toContain("if security.scholarship_flag_v1('scholarship.legitimacy_checks_on', false) and security.scholarship_pilot_scope_v1(p_provider_id) then")
  // the pilot start runs only with a proposal on and a non-empty list, and re-admits only provider-rule refusals from stored facts
  expect(m).toContain("and x.admit_reasons = array['not a university provider in a scholarship country'] and x.read_status = 'read'")
  expect(m).toContain("security.pipeline_num_v1('batch.scholarship_pilot_readmit', 50)")
  expect(m).toContain('v_pilot := security.scholarship_pilot_start_v1();')
  // official award source: a non-university page naming another body's award is refused; universities unchanged; the words are a setting
  expect(m).toContain("elsif not security.scholarship_university(c.provider_id) and security.scholarship_external_award_v1(v_name) then r:=jsonb_build_object('admitted',false,'reason','award of another body');")
  expect(m).toMatch(/'scholarship\.external_award_patterns'[\s\S]{0,900}?'list', '\["australia awards", "manaaki"/)
})

test('stop conditions: every one measured per provider and in total, every threshold a setting, nothing switched off automatically', () => {
  for (const k of ['scholarship.pilot_stop_wrong_provider_max', 'scholarship.pilot_stop_unsupported_max', 'scholarship.pilot_stop_fc_share_pct',
    'scholarship.pilot_stop_ai_share_pct', 'scholarship.pilot_stop_failed_pct', 'scholarship.pilot_stop_min_reads']) expect(m).toContain(`security.pipeline_num_v1('${k}',`)
  for (const r of ["'wrong-provider admission (", "'admission without eligibility evidence (", "'failed page reads (", "'discovery stuck (", "array['Firecrawl ", "array['AI US$"]) expect(m).toContain(r)
  expect(m).toContain("security.fc_setting_num_v1('daily_share_scholarships', 3500)")
  expect(m).toContain("s.toolset_key = 'openrouter' and s.key = 'guard_scholarship_ai'")
  expect(m).toMatch(/create or replace function security\.scholarship_pilot_report_v1\(\)[\s\S]*?language sql stable/)
  expect(m).toMatch(/create or replace function security\.scholarship_pilot_stop_v1\(\) returns jsonb language sql stable/)
})

const CASES = [
  'shipped: list empty, pilot only on, proposals off; the pilot does not start', 'shipped: universities only, the course minimum (as today)',
  'empty list = nobody: a TAFE is not admitted, the course minimum holds', 'empty list = nobody: an untyped Canadian provider is still searched (P2 globally would stop it)',
  'empty list = nobody: the pilot does not start, tiers unchanged',
  'pilot: a listed TAFE is admitted and searched by the legitimacy checks', "pilot: providers not listed keep today''s rules",
  'pilot: a listed school is never admitted or searched', 'pilot: a listed provider is first in the discovery order',
  'pilot start (hourly refill): one fresh discovery, the recent refused page admitted again; the school is not queued',
  'pilot start: the old page and the page refused for another reason are left alone; the record starts unpublished',
  'award source: a college\'\'s page naming a government award is refused as an award of another body',
  'award source: universities are unchanged (a university\'\'s own "University of" award is admitted)',
  'pilot start runs once: a second refill changes nothing',
  'report: the listed providers, one admission, no stop', 'stop 1: a wrong-provider admission stops the expansion', 'stop 1: a Layer 4 decision naming the provider counts too',
  'stop 2: an admission without eligibility evidence stops the expansion', 'stop: cleared when the evidence is there',
  'stop 3: Firecrawl over the pilot share a day', 'stop 3: AI over the pilot share a day', 'stop 4: failed page reads over the share', 'stop 4: stuck discovery',
  'the stop thresholds are settings',
  'wider activation: an unlisted VET is admitted and searched by legitimacy; the untyped Canadian provider is no longer searched',
  'proposals off: the list alone changes nothing (TAFE refused, tier as before)',
]
test('database cases: every rule and stop condition has its case on the fixtures', () => {
  const after = fx('fixtures.sql')
  for (const c of CASES) expect(after, c).toContain(`perform fx_ok('${c}',`)
  expect([...after.matchAll(/perform fx_ok\('/g)].length).toBe(CASES.length)
})
