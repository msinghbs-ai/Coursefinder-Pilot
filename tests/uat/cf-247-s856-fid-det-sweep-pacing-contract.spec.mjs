// Guards: S856 deterministic fee, intake and deadline sweep pacing (Platform Admin 20 Nov 2026 19:15 AEDT, chat S1-Fees-Intakes): a batch is cut into queued calls, one call is sent a minute while fewer than fid.calls_open_max are out, and at most fid.replies_per_tick replies are recorded a run, so a run stays short and the shared worker never gets a burst.
// CF-247 s856. Migration 20261120193000.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const SQL = fs.readFileSync(migrationPath('20261120193000_cf247_s856_fid_det_sweep_pacing.sql'), 'utf8')
const tick = SQL.slice(SQL.indexOf('create or replace function security.fid_det_tick_v1('), SQL.indexOf('$function$;', SQL.indexOf('create or replace function security.fid_det_tick_v1(')))

test('two settings bound the pacing; the job command is unchanged', () => {
  expect(SQL).toMatch(/'fid\.calls_open_max'[\s\S]*?to_jsonb\(2\), 1, 5, 'calls'/)
  expect(SQL).toMatch(/'fid\.replies_per_tick'[\s\S]*?to_jsonb\(1\), 1, 5, 'replies'/)
  expect(SQL).not.toMatch(/cron\.schedule\(/)
})

test('a batch waits as queued calls; one call is sent a minute while fewer than calls_open_max are out', () => {
  expect(SQL).toContain("check (state in ('queued', 'sent', 'recorded', 'failed', 'expired'))")
  expect(tick).toContain("insert into pipeline.fid_det_runs(items, state, payload)")
  expect(tick).toContain("and not exists (select 1 from pipeline.fid_det_runs where state in ('queued', 'sent'))")
  expect(tick).toContain("if (select count(*) from pipeline.fid_det_runs where state = 'sent') < v_open then")
  expect(tick).toContain("where state = 'queued' order by id limit 1 for update skip locked")
  expect((tick.match(/svc_pilot_submit_nonce/g) || []).length).toBe(1)
})

test('at most replies_per_tick replies are recorded a run; the batch query and the gates are unchanged', () => {
  expect(tick).toContain('exit when v_done >= v_rpt;')
  expect(tick).toContain('security.fid_det_record_v1(r.id, v_call)')
  expect(tick).toContain("security.fid_det_batch_v1(security.pipeline_num_v1('fid.batch_size', 150)::int, v_ext)")
  expect(SQL).not.toMatch(/create or replace function security\.fid_det_(record|batch)_v1/)
})

test('the post-check runs in a subtransaction that is always rolled back and leaves no row; G3 checked', () => {
  expect(SQL).toContain("raise exception using errcode = 'P0002', message = 's856-probe-rollback';")
  expect(SQL).toContain("exception when sqlstate 'P0002' then null;")
  expect(SQL).toContain("raise exception 'post-check: a test call was left behind'")
  expect(SQL.match(/security\.consumer_api_check_v1\(\)/g).length).toBeGreaterThanOrEqual(2)
  expect(SQL).not.toMatch(/create (or replace )?(function|view|table)( if not exists)? public\./i)
})
