// Guards: Platform Admin 24 Nov 2026 23:24 AEDT (AER-FU-11 P0; renumbered from s1093, which never ran; Admin #1013, #1015: the entry_matrices route hands the worker its qualified cascade; unqualified models never sent; other routes, budgets, G3, locks and cron unchanged)
// s1099: entry_matrices migration_state routed, a rolled-back regression of the resolver, and a requeue without duplicates.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261126050000_cf247_s1099_entry_matrices_route_routed.sql', 'utf8')

test('s1099: only entry_matrices moves to routed, from routed_single, when at least two cascade models are qualified; logged with the approval', () => {
  expect(MIG).toContain("update pipeline.ai_service_routes set migration_state = 'routed', reason = v_reason, changed_at = now(), changed_by = null where service_code = 'entry_matrices';")
  expect(MIG).toContain("if v_before is distinct from 'routed_single' then raise exception")
  expect(MIG).toContain("raise exception 's1099: fewer than two cascade models are qualified for entry_matrices; nothing changed'")
  expect(MIG).toContain("values ('ai_routes', 'transition', 'entry_matrices'")
  expect(MIG).toContain("raise exception 'post-check: another route changed'")
  expect(MIG).not.toMatch(/daily_usd_cap\s*=|platform_toolset_settings|cron\.schedule|delete from/i)
})

test('s1099: the regression proves order and qualification inside the migration and always rolls back', () => {
  expect(MIG).toContain("if cardinality(v_codes) < 2 or v_codes[1] <> 'mistral-small-3.2' then raise exception")
  expect(MIG).toContain("set status = 'unqualified' where service_code = 'entry_matrices' and model_code = 'qwen3-30b';")
  expect(MIG).toContain("raise exception 'an unqualified model is still handed out'")
  expect(MIG).toContain("if sqlerrm <> 'S1099_REGRESSION_OK' then raise exception 's1099 regression failed: %', sqlerrm; end if;")
})

test('s1099: failed runs since s1085 are queued once per source, never beside a queued, running or leased run', () => {
  expect(MIG).toContain('select distinct on (r.source_id) r.id from pipeline.entry_matrix_runs r')
  expect(MIG).toContain("(o.state in ('queued', 'running') or coalesce(o.leased_until, '-infinity') > now())")
})
