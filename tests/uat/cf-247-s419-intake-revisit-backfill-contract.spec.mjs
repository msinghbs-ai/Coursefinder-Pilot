// Guards: F-INT D3 forward fix (Platform Admin decision 9 Nov 2026: "Do not manually rerun an already-applied migration. If the revisit backfill was missed, implement an idempotent forward migration with checksum, row-count and rollback/forward-recovery safeguards."): migration 20261109170000 gives the held intake rows their first revisit time only while intake_dates.revisit_stored_inputs is 1, never turns a switch on, changes only next_revisit_at from null, leaves hand-locked, withdrawn and rejected rows alone, records every row, checks a checksum and counts and rolls back on any difference, and can be recovered forward; fixtures in tests/fixtures/intake-revisit-backfill
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109170000_cf247_intake_revisit_backfill.sql'
const FX = 'tests/fixtures/intake-revisit-backfill'
const sql = fs.readFileSync(MIG, 'utf8')
const body = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const read = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const backfill = body.slice(body.indexOf('do $backfill$'), body.indexOf('end $backfill$'))

test('housekeeping and G3: replaces and retires lines, a purpose for both tables, RLS and no open access, nothing dropped, no consumer API object named', () => {
  expect(sql).toMatch(/^-- Replaces: nothing/m)
  expect(sql).toMatch(/^-- Retires: nothing/m)
  for (const t of ['pipeline.intake_revisit_backfill_batches', 'pipeline.intake_revisit_backfill_log']) {
    expect(body).toContain(`comment on table ${t} is '`)
    expect(body).toContain(`alter table ${t} enable row level security;`)
    expect(body).toContain(`revoke all on ${t} from public, anon, authenticated;`)
  }
  expect(body).not.toMatch(/\b(drop\s+(table|function|column|index|trigger|schema|view)|truncate)\b/i)   // 'on commit drop' on the temporary plan table is not a drop of anything kept
  expect(body).not.toMatch(/\bdelete\s+from\b/i)
  expect(body).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  for (const n of ['pipeline.intake_revisit_backfill_batches', 'pipeline.intake_revisit_backfill_log', 'security.intake_revisit_backfill_undo_v1', 'public.admin_intake_revisit_backfill_undo_v1']) expect(body).toContain(`'${n}'`)
  expect(body).not.toMatch(/automation_catalogue|cron\.schedule/)   // no job: nothing to catalogue (G1)
})

test('switch first and no self-enabling: nothing is done unless intake_dates.revisit_stored_inputs is 1, and no setting is written', () => {
  expect(backfill.indexOf("security.pipeline_num_v1('intake_dates.revisit_stored_inputs', 0)")).toBeGreaterThan(-1)
  const guard = backfill.indexOf('if v_switch is distinct from 1 then')
  expect(guard).toBeGreaterThan(-1)
  expect(backfill.slice(guard, guard + 400)).toContain('return;')
  // the first write of the block comes after the guard
  expect(backfill.search(/\b(insert into|update|create temp table)\b/)).toBeGreaterThan(guard)
  expect(body).not.toMatch(/(insert\s+into|update)\s+pipeline\.platform_toolset_settings/i)
  expect(body).not.toMatch(/set_config|alter\s+system/i)
})

test('same rows as the original backfill, never more, and only next_revisit_at from null', () => {
  const flat = (x) => x.replace(/\s+/g, ' ')
  const orig = flat(fs.readFileSync('supabase/migrations/20261109040000_cf247_intake_revisit_page_fingerprint.sql', 'utf8'))
  const mine = flat(backfill)
  // the same predicate, the same helper, the same spread formula as step 6 of the released migration
  for (const t of ["i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)", 'd.next_revisit_at is null', 'security.intake_revisit_stored_inputs_v1(d.next_action)',
    "hashtextextended(d.intake_id::text, 0)) % 10000) / 10000.0", "security.pipeline_num_v1('intake_dates.revisit_days', 14)"]) {
    expect(orig, `original: ${t}`).toContain(t)
    expect(mine, t).toContain(t)
  }
  // the four actions are not listed here: the one helper names them and reads the switch
  expect(backfill).not.toContain('evidence_ambiguous')
  // left alone: hand lock, withdrawn (reason, event), rejected (reason, rejected-value memory)
  for (const t of ["k.entity = 'course' and k.entity_id = d.course_id and k.field in ('intakes', 'intake')", "not ilike 'withdrawn:%'", "not ilike '%recorded as rejected%'", "w.outcome = 'withdrawn'", 'pipeline.intake_date_rejections j']) expect(backfill, t).toContain(t)
  // the bound and the clean no-op
  expect(backfill).toContain('if v_cand = 0 then')
  expect(backfill).toContain('if v_cand > v_live then')
  // the only column written on pipeline.course_intake_dates
  const upd = [...body.matchAll(/update pipeline\.course_intake_dates d set ([^\n]+)/g)].map((m) => m[1])
  expect(upd.length).toBe(2)
  for (const u of upd) expect(u).toMatch(/^next_revisit_at = /)
  expect(backfill).toContain('and d.next_revisit_at is null;')
  // G2: no operational number in code (fixed values are marked)
  expect(body).not.toMatch(/interval\s+'\d+\s*(day|days|hour|hours|week|weeks|month|months)\b/i)
  expect(body).not.toMatch(/\blimit\s+\d{3,}/i)
  expect(sql).toMatch(/-- fixed: seconds in a day/)
  expect(sql).toMatch(/-- fixed: technical safety time-out/)
})

test('safeguards: lock, record before change, checksum over (row, new value), counts, every other column and row unchanged, read-back; any difference raises (whole migration rolls back)', () => {
  for (const t of ['pg_try_advisory_xact_lock', "set local lock_timeout = '30s';  -- fixed:", 'order by d.intake_id for update of d', "insert into pipeline.intake_revisit_backfill_batches", "insert into pipeline.intake_revisit_backfill_log",
    "md5(string_agg(p.intake_id::text || '=' || to_char(p.new_value at time zone 'UTC'", "(to_jsonb(d) - 'next_revisit_at')::text", 'v_changed <> v_cand or v_logged <> v_cand', 'v_after is distinct from v_exp',
    'v_other_after is distinct from v_other_before', 'v_rest_after is distinct from v_rest_before', 'the log does not match the rows', 'v_stored is distinct from v_exp or v_logsum is distinct from v_exp'])
    expect(backfill, t).toContain(t)
  expect((backfill.match(/raise exception/g) || []).length).toBeGreaterThanOrEqual(8)
  expect(backfill.indexOf('insert into pipeline.intake_revisit_backfill_log')).toBeLessThan(backfill.indexOf('update pipeline.course_intake_dates d set'))
  expect(backfill.indexOf('update pipeline.course_intake_dates d set')).toBeLessThan(backfill.indexOf('v_after is distinct from v_exp'))
})

test('forward recovery: restores only rows that still hold the value the backfill set, records skips, not open to anon or authenticated, the Platform Admin call is gated and logged', () => {
  const undo = body.slice(body.indexOf('create or replace function security.intake_revisit_backfill_undo_v1'), body.indexOf('create or replace function public.admin_intake_revisit_backfill_undo_v1'))
  expect(undo).toContain('d.next_revisit_at is not distinct from g.new_next_revisit_at')
  expect(undo).toContain("'skipped_changed'")
  expect(undo).toContain("errcode = '22023'")
  expect(undo).toMatch(/set next_revisit_at = l\.previous_next_revisit_at/)
  expect(body).toContain('revoke all on function security.intake_revisit_backfill_undo_v1(uuid) from public, anon, authenticated;')
  expect(body).not.toMatch(/grant execute on function security\.intake_revisit_backfill_undo_v1/)
  const admin = body.slice(body.indexOf('create or replace function public.admin_intake_revisit_backfill_undo_v1'))
  expect(admin).toContain("auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required'")
  expect(admin).toContain('insert into pipeline.admin_control_events')
  expect(body).toContain('revoke all on function public.admin_intake_revisit_backfill_undo_v1(uuid, text) from public, anon;')
  expect(body).toContain('grant execute on function public.admin_intake_revisit_backfill_undo_v1(uuid, text) to authenticated;')
  expect(body).toMatch(/insert into pipeline\.component_register[\s\S]*20261109170000/)
})

test('fixtures: every positive and negative case, the tampering, the production parity, G3 and the CI run', () => {
  const run = read('run.sh')
  for (const t of ['b6d11a5f07271ba950de01d1a0ae6517', 'dd10dc1c02a0ecf7a75d63467df1110a', '3353fe59717325d9870808e10d5af40d', 'd709d92dbd7a648ccf78e594d68ca980', 'PASS switch off:', 'PASS consumer API frozen', 'PASS no definition changed',
    'tamper row_checksum', 'tamper other_column', 'tamper other_row', 'tamper row_not_updated', 'tamper log_value', 'tamper batch_checksum', 'PASS abort (concurrent run)', 'cases-after.sql', 'cases-undo.sql', 'cases-admin.sql', 'apply() { "${P[@]}" -d $DB -1 -f $MIG'])
    expect(run, t).toContain(t)
  const seed = read('seed.sql')
  for (const t of ["'locked_by_hand'", "'withdrawn_event'", "'withdrawn_reason'", "'withdrawn_status'", "'rejected_reading'", "'rejected_reason'", "'fully_dated'", "'inactive_course'", "'already_timed'", "'other_action'", "'tamper_pick'", "'edited_since_a'"]) expect(seed, t).toContain(t)
  const cases = read('cases-after.sql') + read('cases-undo.sql') + read('cases-admin.sql')
  for (const t of ['PASS expected rows:', 'PASS bound:', 'PASS untouched:', 'PASS spread:', 'PASS checksum:', 'PASS time:', 'PASS no self-enabling:', 'PASS surface:', 'PASS idempotent:', 'PASS undo:', 'PASS undo again:', 'PASS re-run after recovery:', 'PASS Platform Admin call:', 'skipped_changed'])
    expect(cases, t).toContain(t)
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain("'tests/fixtures/intake-revisit-backfill/**'")
  expect(wf).toContain('RB_REUSE=1 bash tests/fixtures/intake-revisit-backfill/run.sh | tee intake-revisit-backfill-results.log')
  expect(wf).toContain('intake-revisit-backfill-results.log')
})
