// Guards: S749 AER course machine queue order (Platform Admin 19 Nov 2026 06:49 AEDT item 1, session S2-BOOST-AER; follows S748): within its group the least recently checked item comes first, so every waiting course read is checked once a cycle and a refreshed item waits behind the rest; eligibility, batch, time limit, cap, gap, rule, thresholds, validators and audit sample are unchanged (Decision 276).
// CF-247 S749. Migration 20261119095500_cf247_s749_aer_machine_queue_fair_order (rolled-back live dry run).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119095500_cf247_s749_aer_machine_queue_fair_order.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const edit = M.split('do $rn$')[1].split('end $rn$;')[0]

test('the run is edited in place under its live md5 of 19 Nov, exactly once, with the after md5 recorded', () => {
  expect(edit).toContain("v_sig constant text := 'security.aer_machine_run_v1()'; v_before constant text := 'da1f53c6970cb5eef2c1826208b2bb0a'")
  expect(edit).toContain('the edit must apply exactly once')
  expect(edit).toContain('already applied')
  expect(M).toMatch(/--   security\.aer_machine_run_v1\(\)\s+da1f53c6970cb5eef2c1826208b2bb0a -> [0-9a-f]{32}\n/)
  expect(M).toContain('-- Replaces: security.aer_machine_run_v1')
  expect(code(M)).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger|materialized)/i)
})

test('only the order changes: same groups first, then the least recently checked, then the oldest', () => {
  const o = edit.split('v_old := $o0$')[1].split('$o0$;')[0], n = edit.split('v_new := $n0$')[1].split('$n0$;')[0]
  expect(o).toBe("            order by coalesce((k.gate->>'complete')::boolean, false) desc, (s.id is null) desc, i.created_at")
  expect(n.trim().endsWith("order by coalesce((k.gate->>'complete')::boolean, false) desc, (s.id is null) desc, s.updated_at nulls first, i.created_at")).toBe(true)
  expect(code(M)).not.toMatch(/update\s+pipeline\.platform_toolset_settings|make_interval|batch\.aer_machine'|aer\.machine_audit_pct|delete from|truncate|drop /i)
  expect(M).toContain("'945077fe5dc291cc0893976f8fe65aef'")
  expect(M).toContain("raise exception 'post-check: G3 must stay 75 functions and 48 relations'")
})
