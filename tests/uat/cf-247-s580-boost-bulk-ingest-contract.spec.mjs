// Guards: Boost bulk ingestion (Platform Admin 17 Nov 2026 16:15): worker-boost-bulk-ingest runs only inside the overnight window from settings (01:05 to 04:50 Melbourne), never in the migration squash blackout, never while housekeeping-daily runs or just after it starts, and loads a file only when no PR 1, PR 2 or PR 3 tick holds its lock; each file is loaded once; promotion admits only qualified study load and nothing is qualified by this change; the service calls are for the service role only
// CF-247 S580. Migration 20261117163500_cf247_boost_bulk_ingest and edge function worker-boost-bulk-ingest. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261117163500_cf247_boost_bulk_ingest.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const F = fs.readFileSync('supabase/functions/worker-boost-bulk-ingest/index.ts', 'utf8')
const gate = code.slice(code.indexOf('create or replace function security.boost_ingest_gate_v1'), code.indexOf('comment on function security.boost_ingest_gate_v1'))

test('the window, the squash blackout, housekeeping and the switch are settings read by the gate', () => {
  for (const k of ['boost.ingest_on', 'boost.ingest_window_start_minute', 'boost.ingest_window_end_minute', 'boost.ingest_blackout_start_epoch',
    'boost.ingest_blackout_end_epoch', 'boost.ingest_after_housekeeping_minutes', 'boost.ingest_files_per_run', 'boost.ingest_rows_per_call']) {
    expect(code, k).toContain(`('pipeline', '${k}',`)
    expect(gate, k).toContain(`security.pipeline_num_v1('${k}',`)
  }
  expect(code).toMatch(/'boost\.ingest_window_start_minute'[^\n]*\n\s*'number', to_jsonb\(65\)/)
  expect(code).toMatch(/'boost\.ingest_window_end_minute'[^\n]*\n\s*'number', to_jsonb\(290\)/)
  expect(gate).toContain("at time zone 'Australia/Melbourne'")
  expect(gate).toContain('security.maintenance_hold_v1()')
  expect(gate).toContain("j.jobname = 'housekeeping-daily'")
})

test('a file is loaded only while no PR 1, PR 2 or PR 3 tick holds its lock', () => {
  for (const k of ['cf247:rollup_tick', 'cf247:admission_tick:a', 'cf247:admission_tick:b', 'cf247:admission_tick:c',
    'cf247:coverage_lane_tick:a', 'cf247:coverage_lane_tick:b', 'cf247:coverage_lane_tick:c']) expect(gate, k).toContain(`'${k}'`)
  expect(gate).toContain("l.locktype = 'advisory' and l.granted and l.objsubid = 1")
  expect(code).toContain("return security.boost_ingest_gate_v1(true);")
  expect(F).toContain('let g = await gate(svc);')
  expect(F).toContain('if (done.length > 0) { g = await gate(svc); if (!g?.ok)')
})

test('the job is catalogued, allowlisted and has no number; the edge function checks its nonce and claims each file once', () => {
  expect(code).toContain("select cron.schedule('worker-boost-bulk-ingest', '*/5 * * * *',")
  expect(code).toContain("where (security.boost_ingest_gate_v1(false)->>''ok'')::boolean')")
  expect(code).toContain("insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values\n ('worker-boost-bulk-ingest', 'Boost',")
  expect(code).toContain("insert into pipeline.pilot_nonce_functions (function_name, note)\nselect 'worker-boost-bulk-ingest'")
  expect(F).toContain('rpc(svc, "svc_pilot_consume_nonce", { p_function: FN, p_nonce: nonce })')
  expect(F).toContain('rpc(svc, "svc_boost_ingest_claim", { p_paths: [path] })')
  expect(code).toContain('on conflict (path) do nothing returning path')
  const edge = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8'))
  expect(edge.functions['worker-boost-bulk-ingest']).toBe(false)
})

test('promotion admits only qualified study load; nothing is qualified; the service calls are for the service role only', () => {
  expect(code).toContain("when q.model is null then 'shadow'")
  expect(code).toContain("where c.id = p.entity_id and c.study_load is null;")
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications/)
  expect(code).toContain("if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'")
  for (const fn of ['svc_boost_ingest_gate', 'svc_boost_ingest_claim', 'svc_boost_inbound_load', 'svc_boost_ingest_done', 'svc_boost_promote']) {
    const body = code.slice(code.indexOf(`create or replace function public.${fn}(`))
    expect(body.slice(0, 400), fn).toContain("coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'")
  }
  expect(code).toMatch(/revoke all on function public\.svc_boost_ingest_gate\(\)[\s\S]*from public, anon, authenticated;/)
  expect(code).not.toMatch(/grant execute[^;]*(anon|authenticated)/)
})
