// Guards: Platform Admin decision D10, 27 Nov 2026 (permanent rollup scheduler fix, s1290): the tick estimates by the 95th percentile plus a bounded margin with a conservative small-sample fallback, runs protected targets first and starved targets next, and keeps the 60 s budget, the 100 s finish rule and the one tick lock.
// CF-247 S1290. supabase/migrations/20261130090000_cf247_s1290_rollup_tick_p95_estimate_fair_order.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261130090000_cf247_s1290_rollup_tick_p95_estimate_fair_order.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('the replaced procedure is the one captured live (md5 guard) and the repository now holds it in full', () => {
  expect(code).toContain("md5(pg_get_functiondef('security.rollup_tick_v1()'::regprocedure)) <> '36a8d4f314788d4a292bac677b568858'")
  expect(code).toContain('CREATE OR REPLACE PROCEDURE security.rollup_tick_v1()')
})

test('estimate: percentile plus margin, never above the longest run, longest run when history is short', () => {
  expect(code).toContain('when coalesce(e.runs, 0) < v_min_runs then coalesce(e.max_ms, t.expected_ms, 0)')
  expect(code).toContain('else least(e.max_ms, e.p_ms * (1 + v_margin / 100.0)) end exp_ms')
  for (const k of ['rollup.estimate_percentile', 'rollup.estimate_margin_percent', 'rollup.estimate_min_runs', 'rollup.starved_after_minutes', 'rollup.protected_priority_max']) expect(code).toContain(`'${k}'`)
})

test('order: protected first, then starved, then priority; budget, finish rule, lock and due-minute record unchanged', () => {
  expect(code).toContain('order by case when t.priority <= v_protect then 0 when d.first_due < v_tick - make_interval(mins => v_starve) then 1 else 2 end')
  expect(code).toContain('if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then')
  expect(code).toContain("if not pg_try_advisory_lock(hashtext('cf247:rollup_tick')) then return; end if;")
  expect(code).toContain('update pipeline.rollup_targets set last_due_at = v_r.due_at, updated_at = now() where target_code = v_r.target_code;')
  expect(code).not.toMatch(/cron\.schedule\(|cron\.unschedule|\bdelete\s+from|\bdrop\s+(table|function|procedure)/i)
})
