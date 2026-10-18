// CF-247 v2.15.279 (S41): central pages for the top providers, and fee admission after a cross-check. Platform Admin decisions, 15 Oct 2026:
// "Central pages, per course group"; "Clear the >=90% ones"; "Auto-approve checked AI proposals", "Double degrees take the shared default",
// "Research degrees need a research default", "Keep the other holds".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261015020000_cf247_central_policies_and_fee_checks.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('settings on Pipeline settings › Admission checks', () => {
  for (const k of ['admit.fee_crosscheck_pct', 'central.auto_approve', 'central.max_disagree_pct', 'central.min_compare']) expect(mig).toContain(`('pipeline', '${k}',`)
  expect(fs.readFileSync('src/SettingsRegister.jsx', 'utf8')).toContain("'Admission checks':'Checks a value must pass")
})

test('fees: fee only for the four adapters that passed; a fee far from the registered total is held back and flagged first', () => {
  expect(mig).toContain("update pipeline.uni_adapters set admit = true, admit_fields = array['fee']")
  expect(mig).toContain("update pipeline.uni_adapters set admit_fields = admit_fields || array['fee']")
  expect(mig).toContain("where x.months >= 12 and abs(x.fee * x.months / 12.0 - x.reg) > v_pct / 100.0 * x.reg")
  expect(mig).toContain("perform security.fee_crosscheck_guard_v1();  -- CF-247 15 Oct: a fee far from the registered course total is held back first")
  expect(mig).toContain("'adapter_fee_fails_check'")
})

test('central pages: AI readings approved automatically only when checked; the recorder still never approves', () => {
  expect(mig).toContain("where x.status = 'proposed' and x.parser like 'ai:%' and x.kind in ('english_policy', 'intake_calendar')")
  expect(mig).toContain("join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id and f.in_focus")
  expect(mig).toContain("if v_ag + v_df >= v_min and 100.0 * v_df / (v_ag + v_df) > v_max then")
  expect(mig).toContain("'policy_disagrees'")
  expect(mig).toContain("select cron.schedule('policy-auto-approve', '5-59/10 * * * *', 'select security.policy_auto_approve_v1()');")
  expect(mig).not.toMatch(/function public\.svc_central_ai_record/)
  expect(worker).toContain('if (!on(x.quote) || !has(x.ielts_overall, x.quote)) { dropped.push(lv); continue }')
})

test('English plan: same-level double degrees and stated research defaults; other holds stay', () => {
  expect(mig).toContain("else 'other' end = p_grp)")
  expect(mig).toContain("and not security.double_degree_same_group_v1(m.t, m.grp) then 'held|double degree (its parts are at different levels)'")
  expect(mig).toContain("jsonb_typeof(v_defaults->'research') is distinct from 'array' then 'held|research degree (the policy states no research requirement)'")
  expect(mig).toContain("then 'held|level not covered by the policy default'")
  expect(worker).toContain('for (const lv of ["undergraduate", "postgraduate", "research"]) {')
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(2[4-9]|3\d)\.\d+"/) // v0.25.0 (logo finder) keeps this
})

test('md5-guarded and nothing dropped or deleted', () => {
  expect(mig).toContain("raise exception 'live % differs from the definition this change replaces', v_sig;")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
