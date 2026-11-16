// Guards: Consolidation PR 1 fix (Platform Admin 16 Nov 2026 22:44, after the 22:30 cutover review was held): the rollup run history is trimmed by housekeeping-daily, never inside the tick; a live target's due minute is recorded and committed before it runs, so a run cut off by the 120 s statement limit is not taken again before its next due minute; layer2-onboarding-snapshot stays on its own job (target disabled, legacy job untouched) and the shadow report counts enabled targets only; every target stays in shadow
// CF-247 S566. Migration 20261116210000_cf247_rollup_scheduler_fix. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116210000_cf247_rollup_scheduler_fix.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the tick is edited from its known live text only, each edit exactly once, and refuses anything else', () => {
  const fn = code.slice(code.indexOf('create or replace function pg_temp.cf_pr1_edit'), code.indexOf('end $edit$;'))
  expect(fn).toContain("if md5(v_def) <> p_md5 then raise exception")
  expect(fn).toContain("if v_n <> 1 then raise exception")
  expect(fn).toContain("if position(p_done in v_def) > 0 then return 'already'; end if;")
  expect(code).toContain("select pg_temp.cf_pr1_edit('security.rollup_tick_v1()', '85c2e4a49fc3f55ce38b7cce0b8a934a'")
  expect(code).toContain("select pg_temp.cf_pr1_edit('security.rollup_shadow_report_v1(integer)', 'c4625e76e28cabca40fa2154783f3686'")
})

test('a live target: due minute recorded and committed before it runs; shadow targets unchanged', () => {
  expect(M).toContain("    if v_r.mode = ''live'' then  -- PR 1 fix (16 Nov 2026): the due minute is recorded before a live target runs")
  expect(M).toContain("      update pipeline.rollup_targets set last_due_at = v_r.due_at, updated_at = now() where target_code = v_r.target_code;\\n      commit;\\n    end if;\\n    perform security.rollup_run_target_v1(")
})

test('the history is trimmed by housekeeping-daily with rollup.keep_days, and the tick no longer deletes', () => {
  expect(M).toContain("'old', E'  delete from pipeline.rollup_runs where tick_at < now() - make_interval(days => v_keep);\\n  commit;\\n'")
  expect(code).toContain("delete from pipeline.rollup_runs where tick_at < now() - make_interval(days => security.pipeline_num_v1('rollup.keep_days', 14)::int);")
  expect(code).toContain("perform cron.alter_job(v_job, command := 'select security.housekeeping_daily_v1(); select security.rollup_runs_trim_v1();');")
  expect(code).toContain("select jobid into v_job from cron.job where jobname = 'housekeeping-daily' and command = 'select security.housekeeping_daily_v1()';")
  expect(code).toContain("raise exception 'post-check: the tick is not the fixed one'")
})

test('layer2-onboarding-snapshot stays on its own job; the shadow report counts enabled targets; everything stays in shadow', () => {
  expect(code).toContain("set enabled = false, updated_at = now(),")
  expect(code).toContain("where target_code = 'layer2-onboarding-snapshot' and enabled;")
  expect(code).not.toMatch(/cron\.alter_job\([^)]*active/)
  expect(code).not.toMatch(/set\s+mode\s*=/)
  expect(M).toContain("where t.rollup_group = ''A'' and t.enabled) z(x);")
  expect(code).toContain("if v_n <> 26 then raise exception 'post-check: % of 26 legacy jobs are unchanged and active', v_n; end if;")
  expect(code).toContain("raise exception 'post-check: a target is live (this change is shadow only)'")
})
