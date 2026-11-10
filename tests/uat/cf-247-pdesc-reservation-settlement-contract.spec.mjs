// Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first) – an AI reservation that nothing settled must not consume the provider-description AI budget (abandoned reservations are settled at the floor or the observed cost, never released as free, never lost with a failed record call), and the Basic -> Enriched upgrade lane must not be starved by the queue of providers with no description
// Source contract over migrations 20261110140000 and 20261110141000, their forward recoveries and worker v0.61.0. The behaviour is proved by the isolated PostgreSQL fixture tests/fixtures/pdesc-reservation-settlement/run.sh (run in CI by provider-description-integration.yml).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M1 = fs.readFileSync('supabase/migrations/20261110140000_cf247_pdesc_reservation_settlement.sql', 'utf8')
const M2 = fs.readFileSync('supabase/migrations/20261110141000_cf247_pdesc_upgrade_lane_gate.sql', 'utf8')
const code = (m) => m.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')   // the statements, without the comment lines
const C1 = code(M1), C2 = code(M2)
const R1 = fs.readFileSync('supabase/held/pdesc_reservation_settlement_forward_recovery.sql', 'utf8')
const R2 = fs.readFileSync('supabase/held/pdesc_upgrade_lane_gate_forward_recovery.sql', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/pdesc-reservation-settlement/run.sh', 'utf8')
const SCEN = fs.readFileSync('tests/fixtures/pdesc-reservation-settlement/scenarios.sql', 'utf8')
const GATE = fs.readFileSync('tests/fixtures/pdesc-reservation-settlement/gate-scenarios.sql', 'utf8')
const EXP = fs.readFileSync('tests/fixtures/pdesc-reservation-settlement/expected.txt', 'utf8').split('\n').filter(Boolean)
const EXP_DUP = fs.readFileSync('tests/fixtures/pdesc-reservation-settlement/expected-duplicate.txt', 'utf8').split('\n').filter(Boolean)
const EXP_GATE = fs.readFileSync('tests/fixtures/pdesc-reservation-settlement/expected-gate.txt', 'utf8').split('\n').filter(Boolean)
const EXP_GATE_BEFORE = fs.readFileSync('tests/fixtures/pdesc-reservation-settlement/expected-gate-before.txt', 'utf8').split('\n').filter(Boolean)
const WF = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

const FIRE = ['21662da5fc9c4e15facbaef47b63a50f', 'e518081dfb0882f93c264813b6ce3788']
const VAL = ['7347f51b70a0c4a6cdd01a117080aad5', '91a7c9b7757cace6006af37df2bdc40a']
const ENQ = ['e97170e51cb27dee62db0cef3e07bb43', '6506620f2895f0b977e40261f4ff6afd']
const SETTLE = '6d27f04c5555ecdb7f8c4efb26abdcfb'

test('the settlement migration names what it replaces and retires, records the live md5 before and after, edits the fire and the validator only, and adds one function', () => {
  expect(M1).toMatch(/^-- Replaces: .*provider_description_fire_v1.*provider_description_validate_v1/m)
  expect(M1).toMatch(/^-- Retires: nothing/m)
  expect(M1).toContain(`security.provider_description_fire_v1() ${FIRE[0]} -> ${FIRE[1]}`)
  expect(M1).toContain(`security.provider_description_validate_v1(uuid,text,timestamptz,jsonb) ${VAL[0]} -> ${VAL[1]}`)
  expect(M1).toContain(`security.provider_description_settle_abandoned_v1() (new) -> ${SETTLE}`)
  expect(C1).toContain(`edit_all('security.provider_description_fire_v1()', '${FIRE[0]}', '${FIRE[1]}'`)
  expect(C1).toContain(`edit_all('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)', '${VAL[0]}', '${VAL[1]}'`)
  expect(C1).toContain("raise exception 'live % differs from the definition this change edits")
  expect(C1).toContain("return p_sig || ': already applied'")
  // the record, the reserve and the lease are not edited (the leak is settled at the fire; the time-out is removed at the validator)
  expect(C1).not.toMatch(/edit_all\('(public\.svc_provider_description_(record|next|reserve_v1))/)
  expect(C1.match(/create or replace function (?!pg_temp)[a-z0-9_.]+/gi)).toEqual(['create or replace function security.provider_description_settle_abandoned_v1'])
  expect(C1).not.toMatch(/\b(delete from|drop |truncate|alter table|create table|create trigger|create index|cron\.schedule|insert into pipeline\.platform_toolset_settings)\b/i)
  expect(C1).not.toMatch(/insert into pipeline\.ai_spend_ledger/i)   // the ledger row is written by the existing trigger ai_spend_capture
  expect(C1).toContain("t.tgname = 'ai_spend_capture'")
  expect(M1).toContain('Consumer API (G3): not touched')
  expect(M1).toContain('No operational value is written into code (G2)')
  expect(M1).toContain(SETTLE)
})

test('the settlement settles, never releases: an abandoned reservation is charged at the dearer of the floor and the observed cost, capped by the reservation, with the ledger row from the existing trigger, and a live lease is never touched', () => {
  const body = C1.slice(C1.indexOf('$settle$') + 8, C1.lastIndexOf('$settle$'))
  expect(C1).toContain('security definer set search_path to')
  expect(body).toContain("current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role'")
  expect(body).toContain("pg_advisory_xact_lock(hashtext('cf247 provider description spend'))")   // the lock the reservation takes
  // abandoned: a reservation, and not a read in flight
  expect(body).toContain("r.reserved_usd > 0 and (r.state <> 'reading' or r.leased_until is null or r.leased_until < now())")
  expect(body).toContain('for update skip locked')
  // the cost: the floor and the observed cost of a read (the expression the lease uses) from settings, never above the reservation, never released as free
  expect(body).toContain("security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003)")
  expect(body).toContain('sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0)')
  expect(body).toContain('v_est := greatest(v_floor, v_avg)')
  expect(body).toContain('cost_usd = r.cost_usd + least(r.reserved_usd, v_est)')
  expect(body).toContain('ai_calls = r.ai_calls + 1')
  expect(body).toContain('reserved_usd = 0')
  expect(body).toContain("'basis', 'abandoned_reservation_assumed_called'")
  for (const k of ["'settled_usd'", "'reserved_usd'", "'floor_usd'", "'observed_average_usd'", "'ai_calls_before'", "'state_before'", "'at'"]) expect(body, k).toContain(k)
  // bounded by an existing setting, oldest first; no new setting
  expect(body).toContain("security.pipeline_num_v1('pdesc.queue_cap', 60)")
  expect(body).toContain('order by r.updated_at, r.id limit v_bound')
  expect(body).not.toMatch(/\b(delete|drop|truncate)\b/i)
  // an expired reading read is held with the rule the fire already requeues; any other read keeps its state, rule and reason
  expect(body).toContain("state = case when r.state = 'reading' then 'held' else r.state end")
  expect(body).toContain("rule = case when r.state = 'reading' then 'existing_cost_reservation_uncertain' else r.rule end")
  expect(C1).toContain('revoke all on function security.provider_description_settle_abandoned_v1() from public, anon, authenticated')
  expect(C1).toMatch(/comment on function security\.provider_description_settle_abandoned_v1\(\)/)
})

test('the fire settles before it requeues, and the duplicate test counts shared words before it works out the similarity', () => {
  const fire = C1.slice(C1.indexOf("select pg_temp.edit_all('security.provider_description_fire_v1()'"), C1.indexOf("select pg_temp.edit_all('security.provider_description_validate_v1"))
  const fireNew = fire.slice(fire.indexOf('$new$'))   // the text the edit writes
  expect(fire.slice(0, fire.indexOf('$new$'))).not.toContain('settle_abandoned')
  expect(fireNew.indexOf('perform security.provider_description_publication_check_v1();')).toBeGreaterThan(-1)
  expect(fireNew.indexOf('perform security.provider_description_settle_abandoned_v1();')).toBeGreaterThan(fireNew.indexOf('perform security.provider_description_publication_check_v1();'))
  expect(fireNew.indexOf("update pipeline.provider_description_reads set state='queued'")).toBeGreaterThan(fireNew.indexOf('perform security.provider_description_settle_abandoned_v1();'))
  const dup = C1.slice(C1.indexOf("select pg_temp.edit_all('security.provider_description_validate_v1"))
  expect(dup).toContain('position(x in lower(p.description)) > 0')
  expect(dup).toContain('>= (v_dup - 0.0001) * cardinality(w.wa)')   // never above the true overlap: the share less the four-decimal rounding of the similarity
  expect(dup).toContain('-- fixed: rounding slack of pdesc_similarity_v1')
  expect(dup).toContain('offset 0) f')   // the cheap count runs before the similarity
  expect(dup).toContain('security.pdesc_similarity_v1(v_text, f.description) sim')
  // the second half of the union and the exact test are the earlier text
  expect(dup).not.toContain('duplicate_other_provider')   // the rule, the reason and the order of the validator are untouched
})

test('the fixtures prove the arithmetic: the floor, the observed average above the floor, the reservation as the cap, idempotence, the bound, the freed ceiling, the fire requeue', () => {
  const has = (l) => expect(EXP, l).toContain(l)
  has('floor_case_settled|4')
  has('floor_case_held_by_uncertainty|held|existing_cost_reservation_uncertain|reserved=0.00000|calls=1|cost=0.00300|ledger=0.00300|abandoned_reservation_assumed_called|lease=false')
  has('floor_case_reading_expired|held|existing_cost_reservation_uncertain|reserved=0.00000|calls=1|cost=0.00300|ledger=0.00300|abandoned_reservation_assumed_called|lease=false')
  has('floor_case_reading_live_untouched|reading|-|reserved=0.00700|calls=0|cost=0.00000|ledger=0.00000|-|lease=true')
  has('floor_case_below_floor_reservation_is_the_cap|queued|-|reserved=0.00000|calls=1|cost=0.00200|ledger=0.00200|abandoned_reservation_assumed_called|lease=false')
  has('floor_case_finished_read_with_unknown_cost|proposed|-|reserved=0.00000|calls=2|cost=0.00370|ledger=0.00370|abandoned_reservation_assumed_called|lease=false')
  has('floor_case_no_reservation_untouched|queued|-|reserved=0.00000|calls=0|cost=0.00000|ledger=0.00000|-|lease=false')
  has('floor_case_ledger_before|0.00150'); has('floor_case_ledger_after|0.01250')   // 0.0015 recorded + 0.003 + 0.003 + 0.002 + 0.003 settled
  has('again_settled|0'); has('again_ledger|0.01250')
  has('observed_case_average|0.02000')
  has('observed_case_capped_by_reservation|held|existing_cost_reservation_uncertain|reserved=0.00000|calls=1|cost=0.00700|ledger=0.00700|abandoned_reservation_assumed_called|lease=false')
  has('observed_case_dearer_than_floor|queued|-|reserved=0.00000|calls=2|cost=0.03000|ledger=0.03000|abandoned_reservation_assumed_called|lease=false')
  has('bound_run_1|2'); has('bound_run_2|2'); has('bound_run_3|1'); has('bound_run_4|0')
  has('before_settlement_reserve|false|ai_ceiling'); has('after_settlement_reserve|true')
  expect(EXP.some((l) => l.startsWith('fire_after|queued|existing_cost_reservation_uncertain|reserved=0.00000|calls=1|cost=0.00300|ledger=0.00300|abandoned_reservation_assumed_called|lease=false|tries=1|next_try_later=true'))).toBe(true)
  has('privileges|false|false|true|{"search_path=\\"\\""}')
  // the scenarios use the real functions, a rolled-back block each
  expect(SCEN).toContain('security.provider_description_settle_abandoned_v1()')
  expect(SCEN).toContain('public.svc_provider_description_reserve_v1')
  expect(SCEN).toContain('security.provider_description_fire_v1()')
  expect((SCEN.match(/^rollback;/gm) || []).length).toBe((SCEN.match(/^begin;/gm) || []).length)
  // the duplicate test gives the same results before and after, including the share setting at and just above the similarity
  expect(EXP_DUP).toContain('count_never_below_overlap|0.5:0:true,0.8:0:true,0.95:0:true')
  expect(EXP_DUP).toContain('share_equals_similarity|held|duplicate_other_provider|p12|0.6923')
  expect(EXP_DUP).toContain('share_just_above_similarity|propose|missing|-|-')
  expect(EXP_DUP.filter((l) => l.includes('duplicate_other_provider')).length).toBeGreaterThanOrEqual(8)
})

test('the upgrade lane is gated on its own queued count: the live starvation is reproduced before and gone after; the bound and the switch stay', () => {
  expect(EXP_GATE_BEFORE).toContain('full_queue_lane_ran|0'); expect(EXP_GATE_BEFORE).toContain('full_queue_provider1_queued|0'); expect(EXP_GATE_BEFORE).toContain('many_queued_provider1_queued|0')
  expect(EXP_GATE).toContain('full_queue_lane_ran|1'); expect(EXP_GATE).toContain('full_queue_provider1_queued|1'); expect(EXP_GATE).toContain('many_queued_provider1_queued|1')
  expect(EXP_GATE).toContain('own_queue_at_bound_lane_ran|0'); expect(EXP_GATE).toContain('own_queue_below_bound_lane_ran|1'); expect(EXP_GATE).toContain('empty_queue_provider1_queued|1')
  expect(EXP_GATE).toContain('switch_off_provider1_queued|0'); expect(EXP_GATE).toContain('edited_profile_is_not_counted|null|0')
  expect(GATE).toContain("set local track_functions = 'all'")
  expect((GATE.match(/^rollback;/gm) || []).length).toBe((GATE.match(/^begin;/gm) || []).length)
  expect(M2).toMatch(/^-- Replaces: .*provider_description_enqueue_v1/m)
  expect(M2).toMatch(/^-- Retires: nothing/m)
  expect(M2).toContain(`security.provider_description_enqueue_v1() ${ENQ[0]} -> ${ENQ[1]}`)
  expect(C2).toContain(`edit_all('security.provider_description_enqueue_v1()', '${ENQ[0]}', '${ENQ[1]}'`)
  expect(C2).toContain("raise exception 'live % differs from the definition this change edits")
  expect(C2.match(/create or replace function (?!pg_temp)[a-z0-9_.]+/gi)).toBeNull()
  expect(C2).not.toMatch(/\b(insert into|delete from|drop |truncate|alter table|create table|create trigger|create index|cron\.schedule)\b/i)
  // the gate: its own queued count (profile holders) against the lower of the two existing settings; the size asked for is the difference; the switch still decides
  expect(C2).toContain("security.provider_description_basic_profile_v1(q.provider_id) is not null")
  expect(C2).toContain("if v_up is not null and v_up<least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60)) then")
  expect(C2).toContain("least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60))::int-v_up,'prefilter',true,'upgrade',true,")
  expect(C2).toContain("when security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 then")
  // the whole-queue test is gone from the lane (the earlier text is in the forward recovery)
  expect(C2.slice(C2.indexOf('array[$n1$'))).not.toContain("<security.pipeline_num_v1('pdesc.queue_cap',60) then")
  expect(R2).toContain("(select count(*) from pipeline.provider_description_reads q where q.state='queued')<security.pipeline_num_v1('pdesc.queue_cap',60) then")
  expect(M2).toContain('Consumer API (G3): not touched')
  expect(M2).toContain('No operational value is written into code (G2)')
})

test('the forward recoveries are guarded by the md5 of what is live and restore the earlier bodies byte for byte', () => {
  expect(R1).toContain('differs from both texts this recovery knows')
  for (const m of [...FIRE, ...VAL]) expect(R1, m).toContain(m)
  expect(R1).toContain('CREATE OR REPLACE FUNCTION security.provider_description_fire_v1()')
  expect(R1).toContain('CREATE OR REPLACE FUNCTION security.provider_description_validate_v1(')
  expect(R1).not.toMatch(/\b(drop |delete from|truncate)\b/i)
  expect(R2).toContain('differs from both texts this recovery knows')
  for (const m of ENQ) expect(R2, m).toContain(m)
  expect(R2).toContain('CREATE OR REPLACE FUNCTION security.provider_description_enqueue_v1()')
  expect(R2).not.toMatch(/\b(drop |delete from|truncate)\b/i)
  for (const m of [...FIRE, ...VAL, ...ENQ, SETTLE]) expect(RUN, m).toContain(m)
  expect(RUN).toContain('pdesc_reservation_settlement_forward_recovery.sql')
  expect(RUN).toContain('pdesc_upgrade_lane_gate_forward_recovery.sql')
  expect(RUN).toContain('both forward recoveries return the fire, the validator and the enqueue to the live md5 byte for byte')
  expect(WF).toContain('bash tests/fixtures/pdesc-reservation-settlement/run.sh')
  expect(WF).toContain('tests/uat/cf-247-pdesc-reservation-settlement-contract.spec.mjs')
})

test('worker v0.61.0 posts one record call for each item, tries a failed item once more, names what still fails, and changes nothing else', () => {
  expect(IX).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.61\.0"; |\/\/ was v0\.61\.0 )\/\/ v0\.61\.0 \(10 Nov 2026, CF-247 F-PDESC delivery/)   // later versions keep the note ("was v0.61.0")
  expect(IX).toMatch(/\/\/ was v0\.60\.0 \/\/ v0\.60\.0 \(10 Nov 2026, CF-247 F-PDESC delivery/)
  expect(IX).not.toContain('rpc("svc_provider_description_record", { p_results: noNul(out) })')
  const at = IX.indexOf('// v0.61.0: one record call for each item')
  expect(at).toBeGreaterThan(0)
  const rec = IX.slice(at, at + 1400)
  expect(rec).toContain('for (const o of out) {')
  expect(rec).toContain('rpc("svc_provider_description_record", { p_results: noNul([o]) })')
  expect(rec).toContain('attempt < 2 && !done')
  expect(rec).toContain('// fixed: one retry of a failed record')
  expect(rec).toContain('record_errors')
  expect(rec).toContain('recordErrors.length ? 500 : 200')
  // the AI call, the reservation and the reader behaviour stamp are the earlier text
  expect(IX).toMatch(/reader_behavior_version: "provider-description-source-guard-v[45]" \};/)
  expect(IX).toContain('const reservation = await rpc("svc_provider_description_reserve_v1"')
  // the records of the items come after all the reads, in the order the items finished (nothing is recorded twice)
  expect(IX.indexOf('for (const o of out) o.fc_reads = fcBy.get(String(o.item_id)) || 0;')).toBeLessThan(at)
})
