// Guards: Platform Admin 19 Nov 2026 15:18 AEDT (chat S1-Build, s773; IQ-00594): admission runner B stays inside the 120-second statement limit. The adapter overwrite reads one window of batch.adapter_overwrite_window pages a run from a course-id cursor (security.adapter_overwrite_gated_v1), with the Layer 4 block check as one anti-join on security.layer4_active_blocks; without a window any other caller reads every page as before.
// The live rolled-back dry run (label live-dry-run) runs the migration's pre- and post-checks against production (one window measured at 1.1 s on 19 Nov 2026); these checks keep the rules in the file.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119155000_cf247_s773_adapter_overwrite_window.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const gated = c.slice(c.indexOf('create or replace function security.adapter_overwrite_gated_v1('), c.indexOf('$function$;', c.indexOf('create or replace function security.adapter_overwrite_gated_v1(')))

test('each function is changed only from the definition that was read; nothing is created, dropped or deleted but one setting', () => {
  expect(c).toContain("select pg_temp.cf_edit_def('security.adapter_overwrite_v1(integer)'::regprocedure, 'c800a74c92beed1e445d1fe47b553987',")
  expect(c).toContain("<> 'ef72b3865d2a75bb7146321e1d2ef1ac' then")
  expect(c).toContain('if v_c <> 1 then raise exception')
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: nothing/m)
  expect(c).not.toMatch(/\b(create\s+(temp\w*\s+|unlogged\s+)?table|drop\s+(table|function|index)|truncate|delete\s+from|alter\s+table|create\s+(unique\s+)?index)\b/i)
  expect(c).toContain("('pipeline', 'batch.adapter_overwrite_window', 'Adapter overwrite: pages checked per run',")
  expect(c).toContain("'number', to_jsonb(1000), 100, 20000, 'pages', 102, 'Job sizes', 'security.adapter_overwrite_gated_v1',")
})

test('the overwrite checks Layer 4 blocks set-based and reads only the run window when one is set', () => {
  expect(c).toContain("and not exists (select 1 from security.layer4_active_blocks b where b.block_scope = 'operational'")
  expect(c).toContain("and ((b.entity_type = 'course' and b.entity_id = pg.course_id) or (b.entity_type = 'provider' and b.entity_id = co.provider_id)))")
  expect(c).toContain("and (nullif(current_setting('cf247.ao_hi', true), '') is null")
  expect(c).toContain("and pg.course_id <= current_setting('cf247.ao_hi', true)::uuid))")
})

test('the gated job walks a cursor, re-reads a window that reached the limit, and skips between passes as before', () => {
  expect(gated).toContain("v_win int := greatest(100, security.pipeline_num_v1('batch.adapter_overwrite_window', 1000)::int);")
  expect(gated).toContain("v_lo := nullif(m.last_result->>'cursor', '')::uuid;")
  expect(gated).toContain('if v_lo is null and not coalesce((m.last_result->>\'more\')::boolean, true) and m.last_input_at is not null and v_in <= m.last_input_at')
  expect(gated).toContain('order by pg.course_id limit v_win) w;')
  expect(gated).toContain("v_cur := case when v_hit then v_lo when v_last then null else v_hi end;")
  expect(gated).toContain('set last_input_at = case when v_last and not v_hit then v_pass_in else last_input_at end,')
  expect(gated).toContain("perform set_config('cf247.ao_hi', '', true);")
  expect(gated).toContain('perform security.fee_crosscheck_guard_v1();')
  expect(gated).not.toMatch(/max\(w\.course_id/)
})

test('the dry run proves the block check equal to the function and one window inside the limit', () => {
  expect(c).toContain("raise exception 'post-check: the set-based block check differs from the function (% against %)'")
  expect(c).toContain("raise exception 'post-check: one adapter overwrite window took % ms'")
})
