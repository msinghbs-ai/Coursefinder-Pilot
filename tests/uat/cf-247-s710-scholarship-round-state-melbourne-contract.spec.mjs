// Guards: scholarship round states on the Melbourne date (Platform Admin 18 Nov 2026 17:55 and 21:58): open, opening soon and closed are decided on Australia/Melbourne's date, refreshed hourly by rollup-scheduler; no number in the command.
// CF-247 S710. supabase/migrations/20261119041000_cf247_scholarship_round_state_melbourne_date.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119041000_cf247_scholarship_round_state_melbourne_date.sql', 'utf8')

test('every date comparison uses the Melbourne date, md5-guarded', () => {
  expect(M).toContain("v_new constant text := '(now() at time zone ''Australia/Melbourne'')::date';")
  expect(M).toContain("if md5(v_src) <> '09b6bce7b2eea9d25872af4fc9ed9cc0' then")
  expect(M).toContain("raise exception 'post-check: the Melbourne date'")
})

test('rollup-scheduler refreshes the round states hourly with the batch setting', () => {
  expect(M).toContain("values ('scholarship-round-state-refresh', null,")
  expect(M).toContain("'select security.scholarship_round_state_refresh_v1(security.pipeline_num_v1(''batch.scholarship_round_state'', 1000)::int)',")
  expect(M).toContain("'23 * * * *', 'A', 75, true, 'live', 3000,")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
