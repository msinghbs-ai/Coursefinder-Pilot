// Intake dates fixtures: prints the SQL that rebuilds, from this repository's own migrations, the function the intake-dates migration
// edits, as it is live before it: security.coverage_apply_course_v1 (the common admission write; created 1 Oct in the archive, edited
// 23 Oct (fee floor) and 24 Oct (R1 identity check), md5-guarded), and the two live triggers on catalogue.course_intakes (the same-month
// guard of 15 Oct and the manual lock guard of 30 Sep, edited 1 Oct). run.sh checks the rebuilt md5s against the live ones read on 2 Nov 2026.
import fs from 'node:fs'
const root = new URL('../../../supabase/', import.meta.url)
const read = (f) => fs.readFileSync(new URL(f, root), 'utf8')
const between = (sql, start, endRe) => {
  const a = sql.indexOf(start); if (a < 0) throw new Error(`not found: ${start.slice(0, 80)}`)
  const r = new RegExp(endRe, 'g'); r.lastIndex = a; const m = r.exec(sql); if (!m) throw new Error(`no end after: ${start.slice(0, 80)}`)
  return sql.slice(a, m.index + m[0].length)
}
const SIG = 'security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)'
const out = []
out.push(between(read('migrations-archive/20261001173000_cf247_country_admission_rules.sql'), 'create or replace function security.coverage_apply_course_v1(', '\\nend \\$fn\\$'))
const F = read('migrations/20261023026000_cf247_fee_floor.sql')
out.push(between(F, 'create or replace function pg_temp.edit_once(', '\\nend \\$f\\$'))
out.push(between(F, `select pg_temp.edit_once('${SIG}'`, '\\]\\]\\)'))
const R = read('migrations/20261024004000_cf247_r1_backoff_ledger_identity.sql')
out.push(between(R, 'create or replace function pg_temp.edit_n(', '\\nend \\$f\\$'))
out.push(between(R, `select pg_temp.edit_n('${SIG}'`, '\\]\\], array\\[[\\d, ]+\\]\\)'))
// the two guards on catalogue.course_intakes, as live
const G = read('migrations/20261015040000_cf247_intake_duplicates_and_ca_regions.sql')
out.push(between(G, 'CREATE OR REPLACE FUNCTION security.course_intake_same_month_guard()', '\\nend \\$function\\$'))
out.push(between(G, 'create trigger course_intake_same_month_guard', 'security\\.course_intake_same_month_guard\\(\\)'))
const M = read('migrations-archive/20260930120000_cf247_crud_manual_first.sql')
out.push(between(M, 'create or replace function security.manual_fact_guard()', '\\nend \\$\\$'))
// edited 1 Oct 2026 (manual lock for every link type)
out.push(between(read('migrations-archive/20261001170000_cf247_course_links_and_applicants.sql'), 'do $guard$', '\\nend \\$guard\\$'))
out.push('create trigger manual_lock_guard before insert or update or delete on catalogue.course_intakes for each row execute function security.manual_fact_guard()')
process.stdout.write(out.join(';\n\n') + ';\n')
