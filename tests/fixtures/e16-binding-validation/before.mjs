// E16 fixtures: prints the SQL that rebuilds, from this repository's own migrations, the five functions the E16 migration changes, as they
// are live before it: the binding guard (security.coverage_page_refused_host_guard), the award-link lane (security.exit_awards_apply_v2),
// the AI reader's page choice (security.enrich_fields_slice_v1) and the two search projections (search.refresh_course_enrichment_core_v1 and
// ..._scoped_v1). Each is its create statement, then the md5-guarded edits later migrations made to it, in order. run.sh checks the
// rebuilt md5s against the live ones read on 2 Nov 2026.
import fs from 'node:fs'
const root = new URL('../../../supabase/', import.meta.url)
const read = (f) => fs.readFileSync(new URL(f, root), 'utf8')
const between = (sql, start, endRe) => {
  const a = sql.indexOf(start); if (a < 0) throw new Error(`not found: ${start.slice(0, 80)}`)
  const r = new RegExp(endRe, 'g'); r.lastIndex = a; const m = r.exec(sql); if (!m) throw new Error(`no end after: ${start.slice(0, 80)}`)
  return sql.slice(a, m.index + m[0].length)
}
const helper = (sql) => between(sql, 'create or replace function pg_temp.edit_once(', '\\nend \\$f\\$;')
const edit = (sql, sig) => between(sql, `select pg_temp.edit_once('${sig}'`, '\\]\\](, array\\[[\\d, ]+\\])?\\);')
const out = []
// 1 binding guard: created 4 Oct (archive), edited 21 Oct and 31 Oct (SS-007)
const G0 = read('migrations-archive/20261004001260_cf247_adapter_admission_and_refused_hosts.sql')
out.push(between(G0, 'create or replace function security.coverage_page_refused_host_guard()', '\\nend \\$f\\$;'))
for (const f of ['migrations/20261021235000_cf247_page_filter_calendars_nzist.sql', 'migrations/20261031030000_cf247_ss007_remediation_hold.sql']) {
  const s = read(f); out.push(helper(s), edit(s, 'security.coverage_page_refused_host_guard()'))
}
// 2 award-link lane: whole definition of 15 Oct
const A = read('migrations/20261015010000_cf247_enrichment_waste_rules.sql')
out.push(between(A, 'CREATE OR REPLACE FUNCTION security.exit_awards_apply_v2(p_provider_id uuid)', '\\nend \\$function\\$'))
// 3 AI reader page choice: whole definition of 14 Oct, then 18 Oct (do block) and seven md5-guarded edits
const E0 = read('migrations/20261014090000_cf247_campus_regions_and_search_refresh.sql')
out.push(between(E0, 'CREATE OR REPLACE FUNCTION security.enrich_fields_slice_v1(p_id uuid, p_items integer)', '\\nend \\$function\\$'))
out.push(between(read('migrations/20261018100000_cf247_enrich_reads_page_reading.sql'), 'do $slice$', '\\nend \\$slice\\$;'))
for (const f of ['20261021110000_cf247_field_register_gap_queue', '20261021150000_cf247_delivery_modes', '20261022011000_cf247_nz_review_route_reader_stats',
  '20261022019000_cf247_nz_resolutions_finish', '20261023012000_cf247_ai_reader_every_attribute_and_gap_causes', '20261023016000_cf247_course_list_international_fee_city',
  '20261023017000_cf247_ai_reader_bound_pages_only']) {
  const s = read(`migrations/${f}.sql`); out.push(helper(s), edit(s, 'security.enrich_fields_slice_v1(uuid,integer)'))
}
// 4 search projections: whole definitions of 16 Oct
const P = read('migrations/20261016010000_cf247_api_data_fixes.sql')
out.push(between(P, 'CREATE OR REPLACE FUNCTION search.refresh_course_enrichment_core_v1(p_apply boolean DEFAULT false)', '\\nend\\s*\\$function\\$'))
out.push(between(P, 'CREATE OR REPLACE FUNCTION search.refresh_course_enrichment_core_scoped_v1(p_course_ids uuid[], p_apply boolean DEFAULT false)', '\\nend\\s*\\$function\\$'))
process.stdout.write(out.join(';\n\n') + ';\n')
