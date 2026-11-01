// SS-014 D14 and monitoring accuracy fixtures: prints the SQL that rebuilds, from this repository's own migrations, the two functions the
// 20261102040000 migration edits, as they are live before it: security.flag_jobs_v1 (created 20261015080000, wake rule 20261018160000,
// back-off cap 20261024004000) and security.queue_watch_run_v1 (created 20261022033000, progress rule 20261022037000). run.sh checks the
// rebuilt md5s against the live ones read on 2 Nov 2026.
import fs from 'node:fs'
const dir = new URL('../../../supabase/migrations/', import.meta.url)
const read = (f) => fs.readFileSync(new URL(f, dir), 'utf8')
const between = (sql, start, end) => { const a = sql.indexOf(start); if (a < 0) throw new Error(`not found: ${start}`); const e = sql.indexOf(end, a); if (e < 0) throw new Error(`end not found: ${end}`); return sql.slice(a, e + end.length) }
const out = []
if (process.argv[2] === 'collab') {
  // the flag unit functions the idle guard calls, as created by 20261015080000 (collaborators: not edited, so not md5-checked)
  const F0 = read('20261015080000_cf247_flag_unit.sql')
  for (const n of ['flag_list_num_v1(', 'flag_raise_v1(', 'flag_requeue_v1(', 'flag_release_v1(', 'worker_call_work_v1(']) out.push(between(F0, `CREATE OR REPLACE FUNCTION security.${n}`, n === 'flag_list_num_v1(' ? '$function$;' : 'end $function$;'))
  // SS-004's run classification (20261101010000): a run cancelled as the flag unit pauses its job is 'paused', not 'failed'
  out.push(between(read('20261101010000_cf247_ss004_reliability.sql'), 'create or replace function security.cron_run_outcome_v1(', '$function$;'))
  process.stdout.write(out.join('\n\n') + '\n'); process.exit(0)
}
const F1 = read('20261015080000_cf247_flag_unit.sql')
out.push(between(F1, 'CREATE OR REPLACE FUNCTION security.flag_jobs_v1()', 'end $function$;'))
const F2 = read('20261018160000_cf247_relink_levels_and_wake.sql')
out.push(between(F2, 'do $wake$', 'end $wake$;'))
const F3 = read('20261024004000_cf247_r1_backoff_ledger_identity.sql')
out.push(between(F3, 'create or replace function pg_temp.edit_n(', 'end $f$;'))
out.push(between(F3, "select pg_temp.edit_n('security.flag_jobs_v1()'", 'array[1]);'))
const F4 = read('20261022033000_cf247_queue_watchdog.sql')
out.push(between(F4, 'create or replace function security.queue_watch_run_v1(', 'end $function$;'))
const F5 = read('20261022037000_cf247_watchdog_finished_counts_as_progress.sql')
out.push(between(F5, 'do $edit$', 'end $edit$;'))
process.stdout.write(out.join('\n\n') + '\n')
