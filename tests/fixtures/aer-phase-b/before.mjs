// AER Phase B fixtures: prints the SQL that rebuilds, from this repository's own migrations, the live definitions the Phase B migration edits
// or relies on: public.admin_aer (created by 20261029010000, then the md5-guarded edits of 20261029020000, 20261029030000, 20261029060000 and
// 20261030290000, in order), and from 20261031091000 security.ops_scorecard_record_v1, security.platform_alerts_add_v1 and
// security.platform_alerts_evaluate_v1 (unchanged since). run.sh checks each rebuilt md5 against the live md5 read on 2 Nov 2026.
import fs from 'node:fs'
const dir = new URL('../../../supabase/migrations/', import.meta.url)
const read = (f) => fs.readFileSync(new URL(f, dir), 'utf8')
const between = (sql, start, endRe) => { const a = sql.indexOf(start); if (a < 0) throw new Error(`missing: ${start}`); endRe.lastIndex = a; const m = endRe.exec(sql); return sql.slice(a, m.index + m[0].length) }
const helper = (sql, name) => between(sql, `create or replace function pg_temp.${name}(`, /end \$f\$;/g)
const create = (sql, name) => between(sql, `create or replace function ${name}(`, /\nend \$(function)?\$;/g)
const edit = (sql, how, sig) => between(sql, `select pg_temp.${how}('${sig}'`, /array\[[\d,\s]+\]\);/g)
const out = []
const A = 'public.admin_aer(text,jsonb)'
out.push(create(read('20261029010000_cf247_aer_workspace.sql'), 'public.admin_aer'))
for (const f of ['20261029020000_cf247_aer_reader_settings_html_refetch.sql', '20261029030000_cf247_aer_course_programme_rendered_note.sql', '20261029060000_cf247_aer_label_levels.sql']) {
  const s = read(f); out.push(helper(s, 'edit_n'), edit(s, 'edit_n', A))
}
const D5 = read('20261030290000_cf247_d5_aer_scale_not_stated.sql')
out.push(helper(D5, 'edit_once'), edit(D5, 'edit_once', A))
const S = read('20261031091000_cf247_ss014_operational_automation.sql')
for (const n of ['security.platform_alerts_add_v1', 'security.platform_alerts_evaluate_v1', 'security.ops_scorecard_record_v1']) out.push(create(S, n))
process.stdout.write(out.join(';\n\n') + ';\n')
