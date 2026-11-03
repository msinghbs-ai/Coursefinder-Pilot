// Guards: P0 Autonomous AI Operations mandate (Platform Admin 3 Nov 2026 15:37) §11 budget-aware execution and §16 efficiency reporting,
// workstream F (ops brief 3 Nov 2026 15:45): the cost and yield controller measures the six kinds of waste on the existing waste-guard job, trips
// circuit breakers that only pause or skip (each refusal or hold off by its own setting), registers its root causes and remedies on workstream
// A's contract, exposes security.ops_step_value_v1 to the planner and security.ops_cost_report_v1 to the consolidated report, and raises no
// budget. The behaviour runs on isolated fixtures by tests/fixtures/ops-cost/run.sh (scratch PostgreSQL; the two live definitions loaded from
// their live text and checked against the live md5s; the waste reproduced on them; the migration refused without A's contract, applied, applied
// again unchanged; every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104050000_cf247_ops_cost_yield.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-cost'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const stub = fs.readFileSync(`${FX}/stub-ops-contract.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf('\n]::text[][], array[', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf('end $function$;', a)) }

const MD5 = {
  'public.svc_fc_spend(numeric,text,uuid,text)': 'd418c451d681ffd95134f5f4dcf7c504',
  'security.waste_guard_v1()': '101d6fbf97e3c7d3e5830f762c33107b',
}

test('two live definitions are edited only from their live md5 and checked after; workstream D\'s plan functions are not edited; A lands first', () => {
  for (const [sig, b] of Object.entries(MD5)) {
    const a = m.match(new RegExp(`^--   ${sig.replace(/[.()]/g, '\\$&')} +${b} -> ([0-9a-f]{32})$`, 'm'))
    expect(a, sig).not.toBeNull()
    expect(edit(sig)).toContain(`'${b}', '${a[1]}'`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m.match(/select pg_temp\.edit_once\(/g)).toHaveLength(2)
  for (const f of ['enrich_plan_v1', 'enrich_plan_tick_v1', 'admin_jobs_tick_v1', 'admin_job_watch_v1', 'admin_job_close_v1', 'integration_validate_v1', 'integration_yield_checks_v1'])
    expect(m).not.toMatch(new RegExp(`(edit_once\\('[a-z]+\\.${f}\\(|create or replace function [a-z]+\\.${f}\\()`))
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null then")
  expect(run).toContain("must be applied first")
  expect(run).toContain("grep -c ': applied$')\" = 2 ]")
  expect(run).toContain("grep -c ': already applied$')\" = 2 ]")
  for (const k of ['create table if not exists pipeline.ops_root_causes', 'create table if not exists pipeline.ops_remedies', 'create table if not exists pipeline.ops_remedy_runs',
    'create or replace function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb', 'create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb'])
    expect(stub).toContain(k)
})

test('every refusal or hold ships off; measuring, issues and reports ship on; no budget is raised', () => {
  for (const k of ['enforce_ai_loop_hold', 'enforce_repeat_search', 'enforce_stored_page', 'enforce_ineligible'])
    expect(m).toMatch(new RegExp(`\\('pipeline', 'ops_cost\\.${k}', [\\s\\S]*?'number', '0'::jsonb, 0, 1, 'on \\(1\\) or off \\(0\\)'`))
  expect(m).toMatch(/\('pipeline', 'ops_cost\.measure_on', [\s\S]*?'number', '1'::jsonb, 0, 1, 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/\('pipeline', 'ops_cost\.fc_usd_per_credit', [\s\S]*?'number', '0'::jsonb, 0, 1, 'US\$ per credit'/)
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(m).not.toMatch(/cron\.(schedule|alter_job)/)
  for (const k of ['S1 22 cost and yield settings', 'S2 the four enforcement switches ship off', 'S3 measuring ships on', 'B1 switches off: a repeated search is paid for as before',
    'G4 enforcement off: nothing is held', 'B5 the month limit still decides first', 'B6 a switch on does nothing while its breaker is clear'])
    expect(fixtures).toContain(k)
})

test('the six waste checks: repeated AI reads, repeated searches, stored pages, retries past the cap, low-confidence loops, ineligible providers', () => {
  const w = fn('security.ops_cost_waste_v1')
  for (const k of ["'cost_repeat_ai_read', c1", "'cost_repeat_search', c2", "'cost_paid_stored_page', c3", "'cost_unbounded_retry', c4", "'cost_low_conf_loop', c5", "'cost_ineligible_scan', c6"])
    expect(w).toContain(k)
  expect(w).toContain("bool_or(state in ('filled', 'skipped', 'review')) over (w rows between unbounded preceding and 1 preceding) prior_answered")
  expect(w).toContain("lag(u.at) over (partition by u.purpose, lower(u.url) order by u.at, u.id) prev_at")
  expect(w).toContain("where lower(e.source_url) = lower(rd.url) and e.captured_at < rd.at - interval '10 minutes'  -- fixed:")
  expect(w).toContain("security.pipeline_num_v1('waste.retry_max_attempts', 3)")
  expect(w).toContain("having count(*) >= v_loop and bool_and(i.state <> 'filled')")
  expect(w).toContain("when pv.purpose like 'sch\\_%' and not security.fc_sch_eligible_v1(pv.provider_id) then 'scholarship_ineligible' end why")
  expect(w).toContain('language plpgsql stable security definer')
  for (const k of ['W1 repeated AI reads of identical evidence', 'W2 the identical query within a day is one repeat', 'W3 one of six paid reads bought a page stored 3 hours earlier',
    'W4 the match attempt past waste.retry_max_attempts counts', 'W5 the course field read three times with no value is one loop', 'W6 credits on the search-stopped, scholarship-ineligible and skip-listed providers count',
    'W8 the loop size is a setting'])
    expect(fixtures).toContain(k)
  for (const k of ['before: the identical search one minute later is paid for again', 'before: a page stored 3 hours ago is bought again', 'before: the waste guard has no cost checks'])
    expect(before).toContain(k)
})

test('circuit breakers extend the existing guards: waste-guard measures and trips, svc_fc_spend refuses, the flag unit holds; each breaker only pauses or skips', () => {
  expect(after(edit('security.waste_guard_v1()'))).toContain("'cost', security.ops_cost_guard_v1());")
  const s = after(edit('public.svc_fc_spend(numeric,text,uuid,text)'))
  expect(s).toContain('elsif security.ops_cost_fc_refusal_v1(p_units, p_purpose, p_provider_id, p_url) is not null then')
  expect(m).toContain("$o$  elsif p_provider_id is not null and p_purpose in ('sch_map', 'sch_search') and not security.fc_sch_eligible_v1(p_provider_id) then$o$")
  const r = fn('security.ops_cost_fc_refusal_v1')
  for (const k of ["return 'repeat_search';", "return 'stored_page';", "return 'ineligible_provider';", "and not exists (select 1 from pipeline.scholarship_pages sp where sp.url = p_url and sp.requested_at is not null)"])
    expect(r).toContain(k)
  expect(r.match(/b\.state = 'tripped'/g)).toHaveLength(3)
  const h = fn('security.ops_cost_loop_hold_v1')
  expect(h).toContain("perform security.flag_raise_v1('course', r.course_id::text, r.provider_id, r.field, 'enrich_no_value',")
  expect(h).toContain("'soft', 'ops-cost-guard', 'auto',")
  const g = fn('security.ops_cost_guard_v1')
  expect(g).toContain("security.integration_issue_upsert_v1(jsonb_build_object(\n          'fingerprint', 'cost:' || k,")
  expect(g).toContain("diagnosis = coalesce(i.diagnosis, jsonb_build_object('root_cause', k,")
  expect(g).toContain("exception when others then")
  for (const k of ['G1 waste_guard_v1 keeps its three checks and adds the cost checks', 'G3 one integration issue per check, by fingerprint', 'G5 an unchanged problem re-observes its issue; no duplicate',
    'G6 a diagnosis already recorded is not overwritten', 'B2 repeated search refused', 'B3 a page a person asked to be read again is never held', 'B3 an on-demand run a person started is decided before the breakers',
    'B4 the tripped ineligible provider is refused', 'H3 the existing hold now skips it', 'H5 a new page read lifts the hold', 'C1 their issues are marked cleared', 'O2 a failing cost check never fails the waste guard'])
    expect(fixtures).toContain(k)
})

test('workstream A\'s contract: eight root causes, three remedies (auto breaker with action and verify; release; admin budget)', () => {
  for (const k of ['cost_repeat_ai_read', 'cost_repeat_search', 'cost_paid_stored_page', 'cost_unbounded_retry', 'cost_low_conf_loop', 'cost_ineligible_scan', 'cost_ai_ceiling_burst', 'cost_fc_plan_below_settings'])
    expect(m).toContain(` ('${k}', jsonb_build_object('class', `)
  expect(m).toContain("select security.ops_remedy_register_v1('cost_breaker', jsonb_build_object(")
  expect(m).toContain("'action_fn', 'security.ops_cost_remedy_breaker_v1(bigint)', 'verify_fn', 'security.ops_cost_remedy_verify_v1(bigint)',")
  expect(m).toContain("'max_attempts_key', 'ops_cost.remedy_max_attempts', 'cooldown_key', 'ops_cost.remedy_cooldown_hours',")
  expect(m).toMatch(/ops_remedy_register_v1\('cost_result_reuse'[\s\S]*?'authority', 'release'/)
  expect(m).toMatch(/ops_remedy_register_v1\('cost_budget_decision'[\s\S]*?'authority', 'admin'/)
  expect(fn('security.ops_cost_remedy_breaker_v1')).toContain("'changed', v_on and coalesce(v_was, 'clear') <> 'tripped',")
  for (const k of ['R1 eight root causes registered', 'R2 with its switch off the remedy trips the breaker but reports no change', 'R3 with its switch on it trips and reports a change',
    'R4 verify fails while the waste is still measured', 'R5 verify passes when nothing was wasted since the remedy started', 'R6 the breaker remedy refuses an issue that is not a cost check'])
    expect(fixtures).toContain(k)
})

test('ops_step_value_v1 for workstream D and ops_cost_report_v1 for workstream A: read-only, from measured history', () => {
  const v = fn('security.ops_step_value_v1')
  expect(m).toContain('create or replace function security.ops_step_value_v1(p_provider uuid, p_step text, p_scope jsonb default \'{}\'::jsonb) returns jsonb\nlanguage plpgsql stable')
  for (const k of ["'expected_eligible', v_elig", "'expected_recovery', jsonb_build_object('records', v_exp", "'evidence_available', v_evid", "'estimated_cost', jsonb_build_object('ai_usd', v_ai",
    "'likelihood', v_like", "'in_progress', v_prog", "'retry', v_retry", "'value_per_dollar'", "v_uc := security.enrich_unit_costs_v1();", "from pipeline.ai_spend_ledger l\n     where l.lane = v_lane and l.at > v_since and l.source <> 'opening';"])
    expect(v).toContain(k)
  const r = fn('security.ops_cost_report_v1')
  expect(m).toContain('create or replace function security.ops_cost_report_v1(p_window_hours int default 24) returns jsonb\nlanguage plpgsql stable')
  for (const k of ["'paid_operations'", "'evidence_cache_reuse'", "'avoided_duplicate_reads'", "'useful_yield_per_execution'", "'consumption'", "'cost_per_verified_improvement'"])
    expect(r).toContain(k)
  for (const k of ['V1 fields: 6 eligible', "V1 expected recovery from the provider''s measured yield", 'V3 below the minimum sample the platform-wide yield is used', 'V4 pages: 7 courses',
    'V5 the previous failure, its reason and its spend', 'V5 work in progress: skip', 'V8 an unknown step is refused', 'P1 the report has the six §16 efficiency parts', 'P3 cost per verified improvement',
    'P5 the report, the step value and the waste checks are read-only (stable)'])
    expect(fixtures).toContain(k)
})
