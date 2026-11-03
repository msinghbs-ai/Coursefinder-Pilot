// Guards: P0 autonomous AI operations mandate (Platform Admin 3 Nov 2026 15:37) §5, §7, §12 and acceptance mandate 15:52 §8 (workstream C: scholarship and AER coverage; IQ-00041, IQ-00058)
// Workstream C: refused scholarship discovery rows end with an outcome instead of waiting for ever; a permanent, incremental provider-level
// coverage reconciliation of scholarships and entry requirements against what the sources list, one investigation per provider in the
// integration queue; the AER coverage reader counts courses again. The database behaviour runs on isolated fixtures by
// tests/fixtures/ops-coverage-sch-aer/run.sh (scratch PostgreSQL; the live definitions checked against the md5s read on 3 Nov 2026); this spec
// holds the contract and the fixtures' case lines. G2, G3 and housekeeping are guarded centrally (s32, s57, s42) and not re-asserted here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104040000_cf247_ops_c_scholarship_aer_coverage.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-coverage-sch-aer'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const RELEASE_C = ['entry_matrix_enabled_v1', 'entry_matrix_fire_v1', 'course_entry_eligible_v1', 'course_entry_programme_v1', 'aer_course_outcomes_build_v1', 'aer_schedule_']

test('one md5-guarded edit from live text; lands after workstream A; Release C functions and the consumer API untouched', () => {
  const guarded = [...m.matchAll(/select pg_temp\.(?:replace|edit)_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(guarded).toEqual([['security.aer_provider_states_v1()', 'db5fb0c9f75b8bcca91bdcb34a2632d5', 'ea058f55ec77b191995e16985211b366']])
  expect(m).toContain("to_regclass('pipeline.ops_remedies') is null")
  for (const f of RELEASE_C) expect(m, f).not.toMatch(new RegExp(`create or replace function security\\.${f}|edit_once\\('security\\.${f}`))
  expect(m).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|create or replace function api\./)
  const run = fx('run.sh')
  expect(run).toContain('["security.aer_provider_states_v1()"]=db5fb0c9f75b8bcca91bdcb34a2632d5')
  expect(run).toContain('["security.fc_sch_eligible_v1(uuid)"]=2c44de24ea2d1bda123e1c8679591a9f')
  expect(run).toContain("grep -c ': already applied$')\" = 1")
})

test('refused discovery rows get an outcome and come back when the reason clears; updated_at (health "last progress") is not touched', () => {
  const settle = m.slice(m.indexOf('create or replace function security.scholarship_discovery_settle_v1('), m.indexOf("comment on function security.scholarship_discovery_settle_v1"))
  expect(settle).toContain("set status = 'not_eligible', settled_from = pick.status, settle_reason = pick.why")
  expect(settle).toContain("set status = coalesce(d.settled_from, 'pending')")
  expect(settle).not.toMatch(/updated_at\s*=/)
  expect(m).toMatch(/'scholarship\.discovery_settle_on'[\s\S]{0,700}?'boolean', 'true'::jsonb/)
  expect(m).toContain("perform cron.schedule('scholarship-discovery-settle', '16 * * * *', 'select security.scholarship_discovery_settle_v1()')")
  const c = fx('fixtures.sql')
  expect(c).toContain("'C3 small VET settled, updated_at kept'")
  expect(c).toContain("'C4 small VET pending, due now'")
  expect(fx('fixtures-before.sql')).toContain('4 refused discovery rows wait as pending with no outcome')
})

test('coverage is measured against what the sources list, by category and fact; AER by country, qualification, pathway and study level', () => {
  for (const g of ['zero_scholarships', 'under_represented', 'not_searched', 'listing_partial', 'listing_not_fanned_out', "'category_missing:'", "'fields_incomplete:'", 'admission_policy'])
    expect(m, g).toContain(g)
  for (const g of ['outside_aer_population', 'no_source', 'source_unread', 'cells_omitted', 'countries_missing', 'domestic_only_source', 'course_level_gap', 'intake_gap', 'deadline_gap', "'pathway_missing:'"])
    expect(m, g).toContain(g)
  expect(m).toMatch(/'coverage\.aer_pathways'[\s\S]{0,900}?IB=international baccalaureate[\s\S]{0,200}?Nepal=/)
  expect(m).toContain('pwl as (select man.provider_id, pw.label from man cross join pw where man.txt ~* pw.pat)') // a pathway is a gap only where the provider's source names it
  const c = fx('fixtures.sql')
  for (const l of ["'C5 under-represented, shortfall 8: '", "'C5 a school named by the register is not applicable'", "'C6 a pathway the source does not name is never a gap: '",
                   "'C6 a university the eligibility rule leaves out is reported: '", "'C6 River: domestic-only source flagged, intakes held: '"]) expect(c).toContain(l)
})

test('reconciliation is incremental and opens one investigation per provider, never per record; nothing is admitted', () => {
  expect(m).toContain("perform cron.schedule('coverage-reconcile', '26 * * * *', 'select security.coverage_reconcile_v1()')")
  expect(m).toContain("v_fp := 'coverage:' || v_dom || ':' || r.provider_id;")
  expect(m).toContain("from security.coverage_due_v1(v_dom, null)")
  expect(m).toMatch(/case when l\.provider_id is null then 'new' when ch\.at > l\.computed_at then 'changed' when l\.gapped and l\.computed_at < now\(\) - s\.recheck then 'discrepancy'/)
  expect(m).toContain("'authority', 'admin', 'verify_fn', 'security.coverage_investigation_verify_v1(bigint)'")
  expect(m).not.toMatch(/insert into (scholarship\.scholarships|catalogue\.course_entry_requirements|catalogue\.provider_entry_matrix|pipeline\.layer4_review_items)/)
  const c = fx('fixtures.sql')
  for (const l of ["'C7 cap of 3 new a run: '", "'C8 nothing changed: nothing looked at: '", "'C8 no duplicate issue'", "'C10 no Layer 4 item created'"]) expect(c).toContain(l)
})
