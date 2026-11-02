// D-R2/D-R3 fixtures: prints the SQL that rebuilds, from this repository's own migrations, security.entry_matrix_review_apply_v1 as it is
// live before 20261103010000 (its create statement, then the md5-guarded edits later migrations made to it, in order). The other edited
// functions are rebuilt by the E13 fixture builder (tests/fixtures/e13-completeness-gate/before.mjs) followed by the E13 migration itself.
// run.sh checks every rebuilt md5 against the live one read on 2 Nov 2026.
import fs from 'node:fs'
const dir = new URL('../../../supabase/migrations/', import.meta.url)
const read = (f) => fs.readFileSync(new URL(f, dir), 'utf8')
const helper = (sql) => sql.slice(sql.indexOf('create or replace function pg_temp.edit_n('), sql.indexOf('end $f$;', sql.indexOf('create or replace function pg_temp.edit_n(')) + 'end $f$;'.length)
const create = (sql, name) => { const a = sql.indexOf(`create or replace function ${name}(`); const e = /\nend \$(function)?\$;/g; e.lastIndex = a; const m = e.exec(sql); return sql.slice(a, m.index + m[0].length) }
const edit = (sql, sig) => { const a = sql.indexOf(`select pg_temp.edit_n('${sig}'`); const m = /array\[[\d,\s]+\]\);/g; m.lastIndex = a; const e = m.exec(sql); return sql.slice(a, e.index + e[0].length) }
const SIG = 'security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'
const out = [create(read('20261026001000_cf247_entry_matrix_step_a.sql'), 'security.entry_matrix_review_apply_v1')]
for (const f of ['20261026009000_cf247_entry_matrix_band_identity.sql', '20261026010000_cf247_entry_matrix_completeness_guard.sql',
  '20261026011000_cf247_entry_matrix_complete_admission.sql', '20261029030000_cf247_aer_course_programme_rendered_note.sql',
  '20261030070000_cf247_aer_review_path.sql', '20261030260000_cf247_d4_supersede_rule.sql']) {
  const s = read(f); out.push(helper(s), edit(s, SIG))
}
process.stdout.write(out.join(';\n\n') + ';\n')
