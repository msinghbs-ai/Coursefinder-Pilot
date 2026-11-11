// Guards: F-OPS task runner (CF-247; Platform Admin 11 Nov 2026 13:45): a task whose slice meets a passing database error (40P01, 40001, 55P03) is taken again next run, up to jobs.transient_retry_max, instead of failing for good; any other error fails as before. Behaviour is proved by tests/fixtures/jobs-transient-retry/run.sh (live body, the failure reproduced on the old body first); this spec pins the migration text.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261111230000_cf247_jobs_transient_retry.sql', 'utf8')
const R = fs.readFileSync('supabase/held/jobs_transient_retry_forward_recovery.sql', 'utf8')
const LIVE = fs.readFileSync('tests/fixtures/jobs-transient-retry/live/security.admin_jobs_tick_v1.sql', 'utf8')
const BEFORE = 'f95f8c26d9bbd4fa07a74bcd0797e198'
const AFTER = 'd25e4bad56b632eae40d15f69ddfc4f4'
const body = (s) => s.match(/AS \$function\$([\s\S]*?)\$function\$/)[1]

test('the migration follows the house pattern: header, md5-guarded body replacement, one registered setting, post-checks, nothing dropped', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  expect(M).toContain(`--   security.admin_jobs_tick_v1(integer)   ${BEFORE} -> ${AFTER}`)
  expect(M).toContain(`md5(v_src) = '${AFTER}' then raise notice`)
  expect(M).toContain(`md5(v_src) <> '${BEFORE}' then raise exception`)
  expect(M.match(/CREATE OR REPLACE FUNCTION/g)).toHaveLength(1)
  expect(M).toContain("('pipeline', 'jobs.transient_retry_max', 'Tasks: tries after a passing database error'")
  expect(M).toContain("'number', to_jsonb(5), '0', '50', 'times', 787, 'Platform upkeep', 'security.admin_jobs_tick_v1 (job admin-jobs)'")
  expect(M).toContain("'toolsets', 'setting', 'pipeline.jobs.transient_retry_max'")
  expect(M).toMatch(/post-check: security\.admin_jobs_tick_v1\(integer\) is not the body this change states/)
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/cron\.(schedule|job)/i)
})

test('the only difference from the live body is the bounded retry at the top of the exception handler; the failure path is kept', () => {
  const after = body(M).split('\n').map((l) => l.trimEnd())
  const before = body(LIVE).split('\n').map((l) => l.trimEnd())
  for (const l of before) expect(after, l).toContain(l)
  const added = after.filter((l) => !before.includes(l))
  expect(added).toHaveLength(8)
  const b = body(M)
  expect(b).toContain("if sqlstate in ('40P01', '40001', '55P03')")
  expect(b).toContain("< security.pipeline_num_v1('jobs.transient_retry_max', 5) then")
  const h = b.indexOf('exception when others then')
  expect(b.indexOf("if sqlstate in ('40P01'")).toBeGreaterThan(h)
  expect(b.indexOf("update pipeline.admin_jobs set state = 'failed', error = left(sqlerrm, 500)")).toBeGreaterThan(b.indexOf("if sqlstate in ('40P01'"))
})

test('the forward recovery restores the live body byte for byte', () => {
  expect(R).toContain(BEFORE)
  expect(R).toContain(AFTER)
  expect(R).toContain("raise notice 'already the original'")
  expect(R).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(body(R)).toBe(body(LIVE))
})

test('the database fixture runs in its own workflow', () => {
  const run = fs.readFileSync('tests/fixtures/jobs-transient-retry/run.sh', 'utf8')
  expect(run).toContain(`BEFORE=${BEFORE}`)
  expect(run).toContain(`AFTER=${AFTER}`)
  expect(run).toContain('supabase/held/jobs_transient_retry_forward_recovery.sql')
  const wf = fs.readFileSync('.github/workflows/jobs-transient-retry-test.yml', 'utf8')
  expect(wf).toContain('bash tests/fixtures/jobs-transient-retry/run.sh')
})
