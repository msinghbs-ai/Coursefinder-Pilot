// Guards: Platform Admin mandate 4 Nov 2026 08:16 §8 (restore AER throughput: readiness-aware selection, technical recovery, provider fairness,
// the 600 limit and the E13/D-R3 gates kept): readiness gates never-gated entry reads first; technical recovery records the gate class; E13
// recovery re-reads held reads a re-read can fix from the stored copy of the same page through the existing corrected read (D-R2), fair by
// university, bounded a run and a day by settings, shipped off; the scheduled held step yields to it while it is on. The behaviour runs on a
// production-shaped seed by tests/fixtures/aer-throughput/run.sh (scratch PostgreSQL 16; the live definitions checked against their live md5s;
// the migration applied, then applied again unchanged). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104470000_cf247_aer_throughput.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/aer-throughput'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')
const EDITS = {
  'security.layer4_readiness_tick_v1()': ['5ed0f7d1ba89c9248403fa4bce76d6fe', '06e5f4394b0c2831404fc7a766d669c4'],
  'security.aer_technical_recovery_v1()': ['3b8ea81abeae4b7d45f43e8cdb27ed26', '370baa57bfb81fe58df767ad852ca9dd'],
  'security.aer_schedule_held_v1(integer)': ['0ea5886c2956255ea2d3f102c64b0166', '2a0d51faada02e5e36dafb88749b4707'],
}

test('three md5-guarded edits from the live text, to recorded after md5s; the live text kept as the fixture', () => {
  for (const [sig, [before, after]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${before}', '${after}'`)
    expect(m).toContain(`--   ${sig} ${before} -> ${after}`)
    const file = `${FX}/live/${sig.replace(/\(.*$/, '')}.sql`
    expect(md5(fs.readFileSync(file, 'utf8'))).toBe(before)
  }
  expect(m).toContain("('security.course_entry_correction_v1(uuid,uuid,text)', '1e2947b30a02a38327e2b67e312339af')")
  expect(m).toContain("('security.course_entry_read_enqueue_v1(uuid,uuid,text)', 'df0f2a2826e61b92b168847f1557435b')")
  expect(run).toContain('the migration changed a function it does not own')
  expect(run).toContain("grep -c ': already applied$'")
})

test('readiness gates a never-gated entry read first and classifies it again every run until it is gated; the gate batch is unchanged', () => {
  expect(m).toContain("or (x.gate_checked_at is null and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')))")
  expect(m).toContain("order by (x.gate_checked_at is null and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')) desc,")
  expect(m).not.toMatch(/'layer4\.gate_batch'[^\n]*to_jsonb/)
  expect(fixtures).toContain("one run gates 20 (layer4.gate_batch), all of them never-gated held reads")
})

test('E13 recovery: readiness-aware, re-read-fixable holds only, the stored copy of the same page, the existing corrected read, fair and bounded', () => {
  expect(m).toContain("and x.readiness = 'technical_blocked' and 'completeness_gate' = any (x.reasons)")
  expect(m).toContain("and security.aer_e13_class_v1(x.gate) = 'drops_uncovered'")
  expect(m).toContain("and pg.evidence_id is not null and pg.url = i.proposed_value->>'url'")
  expect(m).toContain('v_res := security.course_entry_correction_v1(r.id, v_owner,')
  expect(m).toContain('g := security.course_entry_gate_v1(r.id);')  // re-checked before acting
  expect(m).toContain('row_number() over (partition by c.provider_id order by c.tries, c.created_at, c.id) turn')
  for (const k of ["'batch.aer_e13_recover', 10", "'aer.e13_recover_daily_max', 40", "'aer.e13_recover_per_provider', 2", "'aer.schedule_held_max_tries', 2", "'aer.schedule_held_retry_days', 14"])
    expect(m).toContain(`security.pipeline_num_v1(${k})`)
  expect(m).toContain("v_ai := security.ai_use_refusal_v1('enrich_fields');")
  expect(m).toContain("when coalesce(v_rank, 0) < 6 then")
  expect(m).not.toMatch(/svc_pilot_submit_nonce|'scraper', true|fc_setting_num_v1/)  // no page fetch: the existing stored-page read only
})

test('ships off; the held step yields only while it is on; the limit, the gates and the consumer API are not touched', () => {
  expect(m).toMatch(/\('pipeline', 'aer\.e13_recover_on',[\s\S]*?'number', to_jsonb\(0\), 0, 1, 'on \(1\) or off \(0\)'/)
  expect(m).toContain("if security.pipeline_num_v1('aer.e13_recover_on', 0) >= 1 then return; end if;")
  expect(m).toContain("raise exception 'post-check: aer.e13_recover_on must ship off'")
  expect(m).not.toMatch(/edit_once\('security\.(course_entry_gate_v1|entry_matrix_gate_v1|course_entry_review_apply_v1|entry_matrix_review_apply_v1|aer_schedule_tick_v1)/)
  expect(m).not.toMatch(/aer\.schedule_layer4_max'[^\n]*to_jsonb/)
  expect(m).not.toMatch(/(api\.|public\.website_v2|zoho_edge|website_edge|website_api_v2)/)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(fixtures).toContain("'E13 recovery ships off and asks nothing'")
})

test('the fixture is production-shaped: live cardinality, gate classes, never-gated holds, refused tries, repeated keys, missing stored copies', () => {
  expect(seed).toContain("(9, '8e1adb6c-e069-43db-9584-bd054255e702', 'RMIT University (RMIT)', 303, 0)")
  expect(seed).toContain("('complete', 89), ('row_level', 2), ('row_limit', 94), ('shared_page', 27), ('drops_uncovered', 91)")
  expect(seed).toContain("('complete', 80), ('row_level', 23), ('row_limit', 68), ('shared_page', 18), ('drops_uncovered', 72)")
  expect(seed).toContain("raise exception 'seed: % course items'")
  expect(seed).toContain("raise exception 'seed: % matrix items'")
  expect(seed).toContain('case when g <= 3 then 2 else 1 end')  // repeated keys
  expect(run).toContain('the seed does not reproduce the live starvation')
  expect(fixtures).toContain('still 605 waiting items: the change opens and closes none')
})
