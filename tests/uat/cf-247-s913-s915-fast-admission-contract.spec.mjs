// Guards: CF-247 s913 to s915 (Platform Admin 21 Nov 2026 10:03, chat S1-Fast-Admission: "accelerate verified data admission into live canonical
// tables today"): the partial entry-table admission is live without the 24-hour shadow and admits only rows that pass every machine row rule, a
// course lock, conflict and shared-identity check; verified course entry reads are not held for an audit sample; the admission and reconcile jobs run
// every 15 minutes with their commands unchanged; the $0 sweeps take three times the work, all as settings; the aer-det NUL fix is md5-guarded
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121140000_cf247_s913_s915_fast_admission.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const fn = MIG.slice(MIG.indexOf('create or replace function security.aer_partial_admit_v1()'), MIG.indexOf("revoke all on function security.aer_partial_admit_v1()"))
const sweep = MIG.slice(MIG.indexOf('create or replace function security.aer_det_sweep_v1()'), MIG.indexOf("comment on function security.aer_det_sweep_v1()"))
const S835 = fs.readFileSync('supabase/migrations/20261120163000_cf247_s835_aer_det_academic_promotion_and_sweep.sql', 'utf8')

test('s913: the decision is quoted and the cutover replaces the shadow, which is switched off and retiring', () => {
  expect(MIG).toContain('Platform Admin 21 Nov 2026 10:03 AEDT, chat S1-Fast-Admission')
  expect(MIG).toContain('that cutover is this change and is not made again')
  expect(code).toContain("update pipeline.admission_rules set enabled = false")
  expect(code).toContain("where rule_code = 'aer-uniwide-partial-shadow' and enabled;")
  expect(code).toContain("'aer-partial-admit', 'aer-partial-admit', 'select security.aer_partial_admit_v1()', md5('select security.aer_partial_admit_v1()')")
  expect(code).toContain("'14,29,44,59 * * * *', 60, 'live'")
  expect(code).toMatch(/set status = 'retiring'[\s\S]*retire_after = current_date \+ security\.pipeline_num_v1\('hygiene\.retire_after_days', 14\)/)
  expect(code).toContain("('aer-partial-admit', 'Admission', 22,")
})

test('s913: only a read stopped by completeness, and only rows that pass every row rule, a course lock, conflict and identity check', () => {
  expect(fn).toContain("continue when coalesce(c->>'rule', '') not in ('gate_incomplete', 'completeness');")
  expect(fn).toContain('c := security.aer_matrix_machine_check_v1(r.id);')
  expect(fn).toContain("and i.claimed_at is null and i.assigned_to is null")
  for (const why of ['excluded_by_rule', 'low_confidence', 'short_quote', 'level_unmapped', 'no_minimum', 'minimum_not_in_quote', 'course_locked', 'conflicting_active', 'duplicate_identity']) {
    expect(fn).toContain(`'${why}'`)
  }
  expect(fn).toContain("l.entity = 'course' and l.entity_id = m.course_id and l.field in ('entry_requirements', 'all')")
  expect(fn).toContain("continue when coalesce(v_run.result->>'reader', '') = 'pdf-grid-v1' and v_grid < 1;")
  expect(fn).toContain("if security.aer_matrix_machine_effective_v1() < 2 then")
  // nothing but the passing rows becomes active; nothing is deleted; the item stays with a person
  expect(fn).toContain("where m.id = any(v_ok) and m.status = 'proposed';")
  expect(fn).not.toMatch(/delete\s+from|layer4_decisions|set\s+status\s*=\s*'approved'/i)
  expect(fn).toContain("raise exception 'aer-partial: read-back found % active of % admitted rows'")
  // reversible by the existing withdrawal
  expect(fn).toContain("'admit', 'admitted', 'aer-partial-v1', 'partial'")
  expect(fn).toContain("status_reason = 'replaced by run ' || v_run.id")
})

test('s914: audit samples to 0, admission every 15 minutes, proposer three times; s915: reconcile every 15 minutes, sweeps three times', () => {
  expect(code).toContain("where toolset_key = 'pipeline' and key in ('aer.machine_audit_pct', 'aer.matrix_machine_audit_pct') and value = to_jsonb(5);")
  expect(code).toContain("perform cron.alter_job(v_adm, schedule => '6,21,36,51 * * * *');")
  expect(code).toContain("perform cron.alter_job(v_rec, schedule => '12,27,42,57 * * * *');")
  expect(code).toContain("jobname = 'aer-machine-admission' and command = 'select security.aer_machine_run_v1()'")
  expect(code).not.toMatch(/cron\.schedule\(|cron\.unschedule|command\s*=>/)
  for (const [k, from, to] of [['aer_det.propose_per_run', 50, 150], ['aer_det.propose_max_pending', 400, 1200], ['aer_det.sweep_calls', 3, 9], ['aer_det.sweep_max_open', 4, 12],
                               ['elr_det.in_flight_max', 8, 24], ['batch.elr_det_sweep', 200, 600], ['batch.elr_central', 6, 18]]) {
    expect(code).toMatch(new RegExp(`value = to_jsonb\\(${to}\\), updated_at[\\s\\S]{0,320}?key = '${k.replace('.', '\\.')}' and value = to_jsonb\\(${from}\\);`))
  }
  expect(code).toContain("raise exception 'post-check: setting(s) not at the new value or outside the range: %'")
  expect(code).toContain("raise exception 'post-check: the active job count changed'")
  expect(code).toContain("raise exception 'post-check: the manual locks changed'")
})

test('s915: the aer-det sweep edit is md5-guarded and changes only the cast line', () => {
  expect(code).toContain("md5(pg_get_functiondef('security.aer_det_sweep_v1()'::regprocedure)) <> '9856b441c16e408184e069bd5d8f1cbe'")
  expect(sweep).toContain("v_body := regexp_replace(resp.content, '(?<!\\\\)\\\\u0000', '', 'g')::jsonb;")
  const before = S835.slice(S835.indexOf('create or replace function security.aer_det_sweep_v1()'), S835.indexOf("comment on function security.aer_det_sweep_v1()"))
  const strip = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--') && !l.includes('v_body :=')).join('\n').trim()
  expect(strip(sweep)).toBe(strip(before))
})

test('housekeeping: Replaces and Retires lines, nothing dropped, no consumer object, no spend', () => {
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: .+$/m)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(fn).not.toMatch(/openrouter|firecrawl|net\.http_|svc_pilot_submit/i)
})
