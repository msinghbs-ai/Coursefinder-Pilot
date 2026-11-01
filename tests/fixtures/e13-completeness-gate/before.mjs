// E13 fixtures: prints the SQL that rebuilds, from this repository's own migrations, the three functions the E13 migration changes, as they
// are live before it (security.enrich_entry_record_v1, security.course_entry_review_apply_v1, security.aer_review_read_v1): each one's create
// statement, then the md5-guarded edits later migrations made to it, in order. run.sh checks the rebuilt md5s against the live ones.
import fs from 'node:fs'
const dir = new URL('../../../supabase/migrations/', import.meta.url)
const read = (f) => fs.readFileSync(new URL(f, dir), 'utf8')
const helper = (sql) => sql.slice(sql.indexOf('create or replace function pg_temp.edit_n('), sql.indexOf('end $f$;') + 'end $f$;'.length)
const create = (sql, name) => { const a = sql.indexOf(`create or replace function ${name}(`); const e = /\nend \$(function)?\$;/g; e.lastIndex = a; const m = e.exec(sql); return sql.slice(a, m.index + m[0].length) }
const edit = (sql, sig) => { const a = sql.indexOf(`select pg_temp.edit_n('${sig}'`); const m = /array\[[\d,\s]+\]\);/g; m.lastIndex = a; const e = m.exec(sql); return sql.slice(a, e.index + e[0].length) }
const out = []
const F1 = read('20261028001000_cf247_entry_step_b_course_read_resolver.sql')
out.push(create(F1, 'security.enrich_entry_record_v1'), create(F1, 'security.course_entry_review_apply_v1'))
const F2 = read('20261029080000_cf247_aer_nz_course_identity.sql')
out.push(helper(F2), edit(F2, 'security.enrich_entry_record_v1(bigint,jsonb)'))
const F3 = read('20261029130000_cf247_aer_course_sliced_read.sql')
out.push(helper(F3), edit(F3, 'security.enrich_entry_record_v1(bigint,jsonb)'))
const F4 = read('20261030070000_cf247_aer_review_path.sql')
out.push(create(F4, 'security.aer_review_read_v1'), helper(F4), edit(F4, 'security.course_entry_review_apply_v1(uuid,text,jsonb,text)'))
const F5 = read('20261030260000_cf247_d4_supersede_rule.sql')
out.push(helper(F5), edit(F5, 'security.course_entry_review_apply_v1(uuid,text,jsonb,text)'))
process.stdout.write(out.join(';\n\n') + ';\n')
