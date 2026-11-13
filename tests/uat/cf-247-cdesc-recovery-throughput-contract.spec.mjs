// Guards: F-CDESC recovery and throughput (S2-CF directive, Platform Admin 13 Nov 2026 10:25): the subset plan agrees with the check and follows pointing-back sentences, the recovery sees copied_sentence holds, the machine check's exact-text lookups are indexed and the job runs every two minutes; behaviour is proven by tests/fixtures/cdesc-recovery
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261113280000_cf247_cdesc_recovery_throughput.sql', 'utf8')
const H = fs.readFileSync('supabase/held/cdesc_recovery_throughput_forward_recovery.sql', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/cdesc-recovery/run.sh', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const P = ['security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '1350a9c8f46331a5469cabbd60acf660', '3c263a1984a33a133a331883cc6f8eae']
const R = ['security.cdesc_subset_recover_v1()', '5f73026bc5ed0350107a97a0953f7588', '1652bacc1954b2a9d51ef28d6b411f35']

test('two bodies are edited by md5-guarded named edits, and the held file reverses them', () => {
  for (const [sig, before, after] of [P, R]) {
    expect(M).toContain(`select pg_temp.edit_all('${sig}', '${before}', '${after}',`)
    expect(H).toContain(`select pg_temp.edit_all('${sig}', '${after}', '${before}',`)
    expect(RUN).toContain(before); expect(RUN).toContain(after)
  }
  expect(M).toContain("raise exception 'live % differs from the definition this change replaces (body md5 %)'")
  expect(H).toContain("perform cron.alter_job(v_id, schedule := '4,14,24,34,44,54 * * * *');")
})

test('the plan tests a sentence as the check does and sets a pointing-back sentence aside with the one it points to; only sentences are removed', () => {
  expect(M).toContain("f := security.cdesc_sentence_fault_v1(security.cdesc_known_strip_v1(s->>'text', v_title, v_prov), s->>'quote',")
  expect(M).toContain("if v_fault[i] is null and v_fault[i - 1] is not null and security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then v_fault[i] := 'depends_on_dropped_sentence'; end if;")
  // the pointing-back test is one definition: the plan's own literal is replaced by the function, whose body carries the same literal
  const re = M.match(/select btrim\(coalesce\(p_text, ''\)\) ~\* ('\^[^\n]+')\n/)[1]
  expect(M).toContain(`if btrim(coalesce(v_s->(i - 1)->>'text', '')) ~* ${re} then$o4$`)
  expect(M).toContain("$n4$if security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then$n4$")
  // the copy test is also run on the sentence as written (a run through the course's title is still copied wording)
  expect(M).toContain("if f->>'rule' is distinct from 'copied_sentence' then f := null; end if;")
  expect(M).toContain("|\\S+\\s+then\\M)'")
  // the check, the wording policy, the machine rule and the size rule are not edited
  for (const fn of ['course_description_check_with_v1', 'cdesc_sentence_fault_v1', 'cdesc_machine_text_check_v1', 'course_description_machine_check_v1', 'course_description_machine_admit_v1']) expect(M).not.toContain(`pg_temp.edit_all('security.${fn}`)
  expect(M).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/)
})

test('the recovery looks at copied_sentence and generic_phrase holds; its time box is a marked technical value', () => {
  expect(M).toContain("unsupported_marketing|incomplete_sentence|copied_sentence|generic_phrase):'$n0$")
  expect(M).toContain('$n2$v_dl := least(v_t0 + make_interval(secs => 45), statement_timestamp() + make_interval(secs => 60));$n2$')
  expect(M).toContain('$n1$-- fixed: the whole subset step ends 45 s after it began or 60 s after the job began')
})

test('index, schedule and catalogue row; the data marks are bounded; the fixture runs in CI', () => {
  expect(M).toContain("on pipeline.layer4_review_items (field_code, md5(security.cdesc_norm_v1(proposed_value->>'description')));")
  expect(M).toContain("perform cron.alter_job(v_id, schedule := '0-34/2,44,50-58/2 * * * *');")
  expect(M).toContain("'Every 2 minutes (not from :35 to :43 or from :45 to :49)'")
  expect(M).toContain("if v_a > 8000 or v_b > 1000 then raise exception")
  expect(M).toContain("e.value->'subset_attempt'->>'result' in ('depends_on_dropped_sentence', 'nothing_to_drop', 'remainder_unsupported_sentence')")
  expect(WF).toContain('bash tests/fixtures/cdesc-recovery/run.sh 2>&1 | tee -a course-description-results.log')
  expect(RUN).toContain('REGRESSION checks fail on the database from before the migration')
})
