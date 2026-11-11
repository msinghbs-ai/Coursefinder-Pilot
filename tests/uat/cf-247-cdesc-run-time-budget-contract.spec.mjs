// Guards: F-CDESC job time budget (CF-247 QA follow-up F1; Platform Admin 11 Nov 2026 13:45): the job course-description-machine ends inside its 120 s statement time-out whatever its earlier steps took — settle takes no item past 85 s of the statement and the read-back starts none past 100 s. Behaviour (real time) is proved by tests/fixtures/cdesc-run-time-budget/run.sh, the overrun reproduced on the live text first; this spec pins the migration text.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261112080000_cf247_cdesc_run_time_budget.sql', 'utf8')
const R = fs.readFileSync('supabase/held/cdesc_run_time_budget_forward_recovery.sql', 'utf8')
const live = (f) => fs.readFileSync(`tests/fixtures/cdesc-run-time-budget/live/${f}`, 'utf8')
const bodies = (s) => [...s.matchAll(/AS \$function\$([\s\S]*?)\$function\$/g)].map((m) => m[1])
const S = ['security.course_description_machine_settle_v1()', '4c40d655a7ff674ce184b598056d835f', '5fa17251727adbb49cb718be889fce54']
const C = ['security.course_description_machine_consumer_recheck_v1()', 'a6138e39a1ba4a3d1b04cc01994d2848', 'f4b6bc3e45866782c5f694046d07131f']

test('the migration follows the house pattern: header, two md5-guarded body replacements, post-checks, nothing dropped, no setting or job touched', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  for (const [sig, before, after] of [S, C]) {
    expect(M).toContain(`--   ${sig}   ${before} -> ${after}`)
    expect(M).toContain(`md5(v_src) = '${after}' then raise notice '${sig}: already applied'`)
    expect(M).toContain(`md5(v_src) <> '${before}' then raise exception`)
  }
  expect(M.match(/CREATE OR REPLACE FUNCTION/g)).toHaveLength(2)
  expect(M).toMatch(/post-check: security\.course_description_machine_settle_v1\(\) is not the body this change states/)
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/platform_toolset_settings|cron\.(schedule|job)/i)
})

test('each body differs from the live one only by the statement bound joined to its existing box', () => {
  const [ms, mc] = bodies(M)
  const ls = bodies(live('security.course_description_machine_settle_v1.sql'))[0]
  const lc = bodies(live('security.course_description_machine_consumer_recheck_v1.sql'))[0]
  const diff = (a, b) => a.split('\n').filter((l) => !b.split('\n').includes(l))
  expect(diff(ls, ms)).toEqual(['    exit when clock_timestamp() - v_t0 > make_interval(secs => 40); -- fixed: stays well inside the 120 s statement time-out of a job; the rest is taken next run'])
  expect(diff(ms, ls)).toHaveLength(2)
  expect(ms).toContain('or clock_timestamp() - statement_timestamp() > make_interval(secs => 85); -- fixed (11 Nov 2026)')
  expect(diff(lc, mc)).toEqual(['    exit when clock_timestamp() - v_t0 > make_interval(secs => 15); -- fixed: a follow-up, not the main work of the run'])
  expect(diff(mc, lc)).toHaveLength(2)
  expect(mc).toContain('or clock_timestamp() - statement_timestamp() > make_interval(secs => 100); -- fixed (11 Nov 2026)')
})

test('the forward recovery restores both live bodies byte for byte', () => {
  const [rs, rc] = bodies(R)
  expect(rs).toBe(bodies(live('security.course_description_machine_settle_v1.sql'))[0])
  expect(rc).toBe(bodies(live('security.course_description_machine_consumer_recheck_v1.sql'))[0])
  expect(R).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the real-time fixture runs in the course descriptions workflow', () => {
  const run = fs.readFileSync('tests/fixtures/cdesc-run-time-budget/run.sh', 'utf8')
  expect(run).toContain('security.fx_settle_after(83)')
  expect(run).toContain('supabase/held/cdesc_run_time_budget_forward_recovery.sql')
  const wf = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
  expect(wf).toContain('bash tests/fixtures/cdesc-run-time-budget/run.sh')
  expect(wf).toContain('tests/fixtures/cdesc-run-time-budget/**')
})
