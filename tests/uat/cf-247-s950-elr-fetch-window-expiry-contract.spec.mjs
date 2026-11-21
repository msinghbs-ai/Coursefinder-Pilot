// Guards: CF-247 s950 (Platform Admin 21 Nov 2026 18:15, logic-only guard; Pilot CLAUDE.md on-demand rule): the central English page fetch (s907, s926) closes its on-demand request with its report when the request's window times out, once none of its pages is in flight; queued pages stay queued and are counted; nothing is opened or sent
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261122010000_cf247_s950_elr_fetch_window_expiry_close.sql', 'utf8')

test('the sweep closes a timed-out fetch request only when none of its pages is in flight, and keeps the queue-empty close', () => {
  expect(MIG).toContain("pg_temp.edit_lit('security.elr_det_sweep_tick_v1()', '602ee934e953fefcf467a7d06257fe79', '2a09bbdb08e77eeeb01917c854272b71'")
  expect(MIG).toContain("and not exists (select 1 from pipeline.elr_central_fetches g where g.on_demand_id = f.on_demand_id and g.status = 'sent')")
  expect(MIG).toContain("and (r.expires_at <= now() or not exists (select 1 from pipeline.elr_central_fetches g where g.on_demand_id = f.on_demand_id and g.status = 'queued')) loop")
  expect(MIG).toContain('security.on_demand_close_v1(v_od) || case when v_left > 0 then jsonb_build_object(\'closed_by\', \'window_expired\', \'left_queued\', v_left)')
})

test('logic only: no on-demand request is opened, no page is queued or sent, nothing is dropped or scheduled', () => {
  const body = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(body).not.toMatch(/on_demand_open_v1|on_demand_scope_v1|svc_pilot_submit_nonce\(/)
  expect(body).not.toMatch(/update\s+pipeline\.elr_central_fetches|insert\s+into\s+pipeline\.elr_central_fetches\b/i)
  expect(body).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b|cron\.schedule\(/i)
  expect(MIG).toContain("'post-check: an on-demand request was opened'")
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
})
