// Guards: Platform Admin mandate 4 Nov 2026 08:16 §3 (first-run operational verification is part of the release contract), §4 (producer-to-consumer
// progress contract with a reason for every zero and stall detection), §5 (a known failure is linked to its existing issue and a code or SQL defect
// becomes owned engineering work with evidence and a bounded checkpoint; nothing merges, grants budget, bypasses Layer 4, overrides a lock or
// destroys) and §10 (self-sustainability scorecard). The behaviour runs on isolated fixtures by tests/fixtures/first-run-verification/run.sh
// (scratch PostgreSQL 16; the queue writer and ops_report_v1 loaded as live and md5-checked; the migration applied, then applied again unchanged;
// the 3-4 Nov 2026 production failures replayed). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104460000_cf247_first_run_verification.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/first-run-verification'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const har = fs.readFileSync(`${FX}/har-edit.sql`, 'utf8')

test('one md5-guarded edit (ops_report_v1, on the human-assisted recovery definition); the queue writer is guarded and unchanged', () => {
  expect(m).toContain("select pg_temp.edit_once('security.ops_report_v1(integer)', '3ba694dc078995d88a983e8e92b2f425', '518b5bf873549931a15d4173fef793d5'")
  expect(m).toContain('--   security.ops_report_v1(integer)           3ba694dc078995d88a983e8e92b2f425 -> 518b5bf873549931a15d4173fef793d5')
  expect(m).toContain("md5(pg_get_functiondef('security.ops_report_v1(integer)'::regprocedure)) <> '518b5bf873549931a15d4173fef793d5' then raise exception 'post-check: ops_report_v1'")
  expect(m).toContain("('security.integration_issue_upsert_v1(jsonb,text)', 'b0a1a64982680ae5d588c2d73b779e4e')")
  expect(m).toContain("('security.integration_issue_transition_v1(bigint,text,text,text,jsonb)', '3e8fc63663e5120c50f0859da97dd7a8')")
  expect(m.match(/select pg_temp\.edit_once\(/g)).toHaveLength(1)
  // the fixture builds 3ba694dc from the live 5a1e21cc with the human-assisted recovery release's own edit
  expect(har).toContain("select pg_temp.edit_once('security.ops_report_v1(integer)', '5a1e21cc42f8f54cbf0d9f3f7fe81c71', '3ba694dc078995d88a983e8e92b2f425'")
  expect(run).toContain('["security.ops_report_v1(integer)"]=3ba694dc078995d88a983e8e92b2f425')
  expect(run).toContain('the migration changed a function it does not declare')
})

test('first-run verification extends the V3 release contract: three statuses, the expected run from the schedule, a failed run raises the job issue', () => {
  expect(m).toContain("status text not null default 'awaiting_first_run' check (status in ('awaiting_first_run', 'operationally_verified', 'failed_first_run'))")
  expect(m).toContain('deploy_check_id bigint references pipeline.integration_deploy_checks(id)')
  expect(m).toContain("alter table pipeline.integration_deploy_checks add column if not exists operational_status text")
  expect(m).toContain("case when j.active then security.cron_next_run_v1(j.schedule, v_at) end")
  expect(m).toContain("'fingerprint', case when r.first_run_status = 'failed' then 'job_failed:' || r.jobname else 'first_run:' || r.jobname end")
  // a deployed fix whose first run fails goes back to remediation with its evidence
  expect(m).toContain("perform security.integration_issue_transition_v1(i.id, 'in_progress', 'first-run-verify',")
  // green CI, a migration or a configured switch is not operational success: zero output needs a justified reason
  expect(m).toContain("elsif coalesce(r.expected_min_output, 0) = 0 or z->>'reason' in ('no_eligible_work', 'correctly_excluded') then")
  expect(m).toContain("v_status := 'failed_first_run'; v_reason := 'first run ' || r.first_runid || ' succeeded but created nothing with eligible work: '")
})

test('the progress contract: 16 transitions of the two chains, the five zero reasons, stalls raised by fingerprint, each transition isolated', () => {
  for (const k of ['sch_classification', 'sch_source_recovery', 'sch_listing_traversal', 'sch_candidate_matching', 'sch_reading', 'sch_eligibility', 'sch_layer4', 'sch_admission',
    'sch_publication', 'aer_source_discovery', 'aer_extraction', 'aer_completeness', 'aer_technical_correction', 'aer_layer4_review', 'aer_active_records', 'aer_publication']) {
    expect(m).toContain(` ('${k}', '`)
    expect(m).toContain(`  when '${k}' then`)
  }
  expect(m).toContain("zero_reason in ('no_eligible_work', 'cap_reached', 'blocked_authority', 'correctly_excluded', 'technical_failure')")
  for (const c of ['input_eligible', 'input_processed', 'output_created', 'output_rejected', 'rejected_reasons', 'output_parked', 'parked_next_actions', 'downstream_queued',
    'output_admitted', 'output_published', 'last_advanced_at']) expect(m).toMatch(new RegExp(`^  ${c} `, 'm'))
  expect(m).toContain("'fingerprint', 'stall:' || t.key")
  expect(m).toContain("update pipeline.progress_transitions set measure_error = left(sqlerrm, 300), measured_at = now() where key = t.key;")
})

test("the recovery loop links duplicates the controller's way and makes code defects owned engineering work, within its authority", () => {
  expect(m).toContain("update pipeline.integration_issues set superseded_by = o.id, ops_state = 'superseded'")
  expect(m).toContain("values (s.id, 'supersede_into_owner', now(), jsonb_build_object('status', s.status), 'acted',")
  expect(m).toContain("('%cannot affect row a second time%', 'sql_cardinality', 'code_defect'")
  expect(m).toContain("('%canceling statement due to statement timeout%', 'time_budget', 'code_defect', 'The job does not fit its time budget (whole run rolled back)', 'ops.permanent_after_runs'")
  expect(m).toContain("set remediation_owner = v_cls.owner, remediation_status = v_rem, remediation_checkpoint_at = now() + make_interval(hours => v_h)")
  expect(m).toContain("select security.ops_remedy_register_v1('engineering_remediation', jsonb_build_object('authority', 'release'")
  expect(m).toContain("'route', 'needs_release'")
  // records only: no setting written, no job changed, no Layer 4 decision, no admission or publication, nothing dropped or deleted
  expect(m).not.toMatch(/update\s+pipeline\.platform_toolset_settings/i)
  expect(m).not.toMatch(/cron\.(alter_job|unschedule)|layer4_decide|layer4_.*_apply|publication_status\s*=\s*'published'\s*,/i)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(m).not.toMatch(/create\s+or\s+replace\s+function\s+(api\.|public\.website_|public\.zoho_)/i)
})

test('switches: everything that records ships on, closing on verification ships off; the job is catalogued and reads its sizes from settings', () => {
  for (const k of ['frv.on', 'progress.on', 'recovery.link_on', 'recovery.route_on'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}',[\\s\\S]*?'number', to_jsonb\\(1\\), 0, 1, 'on \\(1\\) or off \\(0\\)'`))
  expect(m).toMatch(/\('pipeline', 'recovery\.close_on_verified_on',[\s\S]*?'number', to_jsonb\(0\), 0, 1, 'on \(1\) or off \(0\)'/)
  expect(m).toContain("perform cron.schedule('first-run-verify', '2,32 * * * *', 'select security.first_run_verify_tick_v1()');")
  expect(m.indexOf("('first-run-verify', 'Platform upkeep', 18,")).toBeLessThan(m.indexOf("perform cron.schedule('first-run-verify'"))
})

test('the fixture replays the 3-4 Nov failures and asserts every case', () => {
  for (const s of ['case 1: failed_first_run with the run id and the error text', 'case 1: the SQL defect is owned engineering work',
    'case 2: IQ-00239 (assigned) is linked into IQ-00241 (deployed, furthest along)', 'case 2: idempotent: a second check links nothing again',
    'case 3: v2.15.461 operationally verified', 'case 4: a deployed fix whose first run fails goes back to in_progress', 'case 5: an active job with no run past its expected time and grace: did_not_run',
    'case 5: built but off', 'case 6: AER reading succeeded with 0 rows behind a valid cap', 'case 6: a successful run that created nothing with eligible work is not operational success',
    'case 7: reading with eligible pages and no read for progress.stall_hours is stalled and raised', 'case 7: one transition that cannot be read is recorded; the others still read',
    'case 8: one time-out is not yet a defect', 'case 9: a failing job with a SQL defect is diagnosed first_run_sql_defect', 'case 10: no setting, job or Layer 4 item changed by any check',
    'case 10: the scorecard has the ten measures of §10']) expect(fixtures).toContain(s)
  expect(run).toContain("grep -c ': applied$')\" = 1")
  expect(run).toContain("grep -c ': already applied$')\" = 1")
})
