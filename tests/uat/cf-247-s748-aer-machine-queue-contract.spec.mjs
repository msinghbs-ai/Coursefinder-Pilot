// Guards: S748 AER course machine queue (Platform Admin 19 Nov 2026 06:49 AEDT item 1, session S2-BOOST-AER; delivers S1-AER finding S677 of 19 Nov 2026 03:15): in admit mode a declined or audit-sample result also records the item's last check in its shadow ledger row, so the job's 6-hour gap applies and the run reaches the items behind; nothing else in admission changes (Decision 276).
// CF-247 S748. Migration 20261119080500_cf247_s748_aer_machine_queue_last_checked (rolled-back live dry run with a two-run probe).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119080500_cf247_s748_aer_machine_queue_last_checked.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const edit = M.split('do $ad$')[1].split('end $ad$;')[0]

test('one function is edited in place under its live md5 of 19 Nov, exactly once, with the after md5 recorded', () => {
  expect(edit).toContain("v_sig constant text := 'security.aer_machine_admit_v1(uuid, text)'; v_before constant text := '7473f475f1385e4d25765f34b1a7a7c1'")
  expect(edit).toContain('the edit must apply exactly once')
  expect(edit).toContain('already applied')
  expect(M).toMatch(/--   security\.aer_machine_admit_v1\(uuid, text\)\s+7473f475f1385e4d25765f34b1a7a7c1 -> [0-9a-f]{32}\n/)
  expect(M).toContain('-- Replaces: security.aer_machine_admit_v1')
  expect(M).toContain('-- Retires: nothing')
  expect(code(M)).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger|materialized)/i)
})

test('the non-admitted branch of admit mode records the last check in the shadow ledger row, as the shadow mode does, before it returns', () => {
  const nw = edit.split('v_new := $n0$')[1].split('$n0$;')[0]
  expect(nw).toContain("values (p_item, v_course, v_prov, 'shadow', v_out, v->>'rule'")
  expect(nw).toContain("on conflict (review_item_id) where mode = 'shadow' do update set outcome = excluded.outcome")
  expect(nw).toContain('updated_at = now();')
  expect(nw.trim().endsWith("return jsonb_build_object('ok', false, 'mode', 'admit', 'outcome', v_out, 'rule', v->>'rule', 'reason', v->>'reason');")).toBe(true)
  // the edit is only in that branch: the anchor is the admit-mode return for an outcome that is not admitted
  expect(edit.split('v_old := $o0$')[1].split('$o0$;')[0]).toBe("    return jsonb_build_object('ok', false, 'mode', 'admit', 'outcome', v_out, 'rule', v->>'rule', 'reason', v->>'reason');")
})

test('nothing else in admission changes: no setting, threshold, validator, decision or withdrawal; the validator stays the one the renewal pins', () => {
  expect(code(M)).not.toMatch(/update\s+pipeline\.platform_toolset_settings|aer\.machine_mode'\s*,\s*'|layer4_decisions|withdraw|delete from|truncate|drop /i)
  expect(M).toContain("'945077fe5dc291cc0893976f8fe65aef'")
  expect(M).toContain("raise exception 'post-check: AER v1 thresholds must stay unchanged (Decision 276)'")
  expect(M).toContain("raise exception 'post-check: G3 must stay 75 functions and 48 relations'")
  expect(M).toContain("'finding', 'S1-AER S677 (19 Nov 2026 03:15)'")
})
