// Guards: F-CDESC shortening by whole sentences (Platform Admin 13 Nov 2026 12:16, conditional approval): a held description over its size limits is shortened by setting aside whole sentences through the existing subset recovery, with every existing check unchanged; behaviour is proven by tests/fixtures/cdesc-shorten
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261113310000_cf247_cdesc_shorten_by_sentence.sql', 'utf8')
const H = fs.readFileSync('supabase/held/cdesc_shorten_forward_recovery.sql', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/cdesc-shorten/run.sh', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const P = ['security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '3c263a1984a33a133a331883cc6f8eae', 'cc54bd91d7a58f522af3ef7b9141e3eb']

test('only the subset plan is edited (md5-guarded) and the held file reverses it; the check, the wording policy and the machine rule are not touched', () => {
  expect(M).toContain(`select pg_temp.edit_all('${P[0]}', '${P[1]}', '${P[2]}',`)
  expect(H).toContain(`select pg_temp.edit_all('${P[0]}', '${P[2]}', '${P[1]}',`)
  expect((M.match(/select pg_temp\.edit_all\(/g) || []).length).toBe(1)
  for (const fn of ['course_description_check_with_v1', 'course_description_check_v1', 'cdesc_sentence_fault_v1', 'cdesc_machine_text_check_v1', 'course_description_machine_check_v1', 'course_description_machine_admit_v1', 'cdesc_subset_recover_v1'])
    expect(M).not.toMatch(new RegExp(`(create or replace function|edit_all\\(')\\s*security\\.${fn}`))
  expect(M).not.toMatch(/platform_toolset_settings/)
  expect(RUN).toContain(P[1]); expect(RUN).toContain(P[2])
})

test('the conditions of the approval are in the rule: whole sentences, size-only readings, least loss first, never the first, protected kinds last, dangling openers counted and removed, cannot fit stays held', () => {
  expect(M).toContain('exit when v_cnt <= 1 or (v_cnt <= v_max and v_tot <= v_maxc);')
  // only a reading with no failing sentence is shortened; the first kept sentence is never a candidate
  expect(M).toContain('if not exists (select 1 from unnest(v_fault) x(f) where x.f is not null) then')
  expect(M).toContain('for k in reverse n .. v_first + 1 loop')
  // the loss of a candidate counts the sentences that would dangle; a protected kind of sentence loses to any other; the later sentence wins a tie
  expect(M).toContain("v_c := v_c + security.cdesc_sentence_substance_v1(v_s->(i - 1)->>'text', v_s->(i - 1)->>'quote');")
  expect(M).toContain('v_f := not (v_cnt - v_rc <= v_max and v_tot - v_rl <= v_maxc);')
  expect(M).toContain('if v_victim is null or (v_p, v_f, v_c) < (v_bp, v_bf, v_bc) then v_victim := k; v_bp := v_p; v_bf := v_f; v_bc := v_c; end if;')
  // a choice that would remove a protected sentence is never taken: the reading stays held
  expect(M).toContain('exit when v_victim is null or v_bp;')
  expect(M).toContain('create or replace function security.cdesc_refers_back_v1(p_text text) returns boolean language sql immutable')
  expect(M).toContain("v_fault[v_victim] := 'over_limit';")
  expect(M).toContain("exit when v_fault[i] is not null or not security.cdesc_refers_back_v1(v_s->(i - 1)->>'text');")
  // the limits are the existing settings (read by the plan as v_max and v_maxc); no text function cuts inside a sentence
  expect(M).not.toMatch(/\b(left|substr|substring)\(\s*(t|v_text|s->>'text')/)
})

test('the fixture runs in CI and proves the regression', () => {
  expect(WF).toContain('bash tests/fixtures/cdesc-shorten/run.sh 2>&1 | tee -a course-description-results.log')
  expect(RUN).toContain('REGRESSION checks fail on the database from before the migration')
})
