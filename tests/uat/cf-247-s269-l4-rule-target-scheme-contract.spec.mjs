// Guards: CF-247 IQ-00189 (Integration Controller 4 Nov 2026, rule runs 20-21; Decision 263 rule executor): a course-link rule that uses the
// proposed page writes it as a full https:// address (an http:// address is given https://, recorded as an edited approval through the existing
// decision path); an address that cannot be written fails the item with a clear reason before any decision. The behaviour runs on isolated
// fixtures by tests/fixtures/l4-rule-target-scheme/run.sh (scratch PostgreSQL; the edited definitions and the decision path checked against the
// live md5s; the migration applied, applied again unchanged; http://, https:// and unwritable addresses).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104350000_cf247_l4_rule_target_scheme.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/l4-rule-target-scheme'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')

const EDITS = {
  'security.layer4_course_link_rule_validate_v1(text,uuid)': ['3a5d088e4aaf3ad1e1a5460524a2e70a', '0cf77b67b8d90c98ef3b160306b67faa'],
  'security.layer4_course_link_rule_execute_v1(text,integer,boolean)': ['85c991e7b626e07f9777f7a65249fd81', 'cafae1b603ee3d42513ef87f34cb1639'],
}

test('two live definitions are edited, md5-guarded both ways; the decision path and the link apply are not edited', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}',`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m).not.toMatch(/create or replace function security\.(layer4_review_decide_impl|layer4_course_link_apply_impl)\b/)
  expect(run).toContain('["security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)"]=75a53dbbcd5e20e1018a05b61f6763aa')
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('the target is the proposed page as a full https:// address; an unwritable address fails with a clear reason', () => {
  expect(m).toContain("case when v.choice = 'use' then regexp_replace(v.target_url, '^(https?://)?', 'https://', 'i') else v.target_url end")
  expect(m).toContain("then 'the proposed page is not a full web address (' || coalesce(lv.target_url, 'none') || ')' end], null) reasons")
  expect(fixtures).toContain("raise notice 'T1 ok")
})

test('the executor writes that address through the existing decision path, as an edited approval when it differs', () => {
  expect(m).toContain("case when r.choice = 'keep' then 'reject' when w.target_url is distinct from w.proposed_url then 'edit_and_approve' else 'approve' end, v_reason,")
  expect(m).toContain("then jsonb_build_object('course_url', w.target_url) end);")
  expect(fixtures).toContain("raise notice 'T2 ok")
  expect(m).not.toMatch(/\bdelete from\b|\bdrop (table|function|trigger)\b/i)
})
