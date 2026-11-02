// Prints the real admitted RMIT Nepal rows (11, admitted 27 Oct 2026; read-only export in ../entry-matrix/rmit-stored/complete-25-rows.json)
// as active provider_entry_matrix rows for the fixtures. Values, quotes and row hashes are as admitted; nothing is invented.
import fs from 'node:fs'
const j = JSON.parse(fs.readFileSync(new URL('../entry-matrix/rmit-stored/complete-25-rows.json', import.meta.url), 'utf8'))
const q = (v) => v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`
const page = j.pages.nepal
const out = [`-- RMIT Nepal page: run ${page.run}, ${page.rows.length} rows (real, admitted 27 Oct 2026)`]
for (const r of page.rows) {
  out.push(`insert into catalogue.provider_entry_matrix(id, provider_id, country_id, country_code, qualification_name, min_grade, min_value, grade_scale, benchmark_band, level_label, quote, source_url, source_id, evidence_id, run_id, status, row_hash, provenance) values (${q(r.id)}, fx.rmit(), fx.country('NP'), 'NP', ${q(r.qualification_name)}, ${q(r.min_grade)}, ${r.min_value == null ? 'null' : r.min_value}, ${q(r.grade_scale)}, ${q(r.benchmark_band)}, ${q(r.study_level)}, ${q(r.quote)}, 'https://www.rmit.edu.au/study-with-us/international-students/apply-to-rmit-international-students/entry-requirements/country-equivalency/nepal', fx.src('nepal'), fx.ev('nepal'), '${page.run}', 'active', ${q(r.row_hash)}, '{"reader": "ai"}');`)
}
process.stdout.write(out.join('\n') + '\n')
