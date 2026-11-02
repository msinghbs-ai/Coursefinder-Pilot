#!/usr/bin/env bash
# AU catalogue export on isolated fixtures (Platform Admin 2 Nov 2026 11:10 and 11:18). Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database from the live baseline's table definitions, loads fixtures.sql,
# and runs the export as a role that can only select, in single mode and in the per_dataset fall-back. Every manifest check must pass, the
# counts must equal the fixture's, and nothing in the database may change. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AUX_DB:-au_export_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
OUT=${AUX_OUT:-$(mktemp -d)}; mkdir -p "$OUT"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${AUX_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
node tests/fixtures/au-catalogue-export/schema.mjs | $P -d $DB >/dev/null
$P -d $DB -f tests/fixtures/au-catalogue-export/fixtures.sql >/dev/null
$P -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'au_export_reader') then create role au_export_reader login password 'fixture'; end if; end \$\$" >/dev/null
$P -d $DB -c "grant usage on schema catalogue, search, pipeline, scholarship, ref, security, extensions, cron to au_export_reader; grant select on all tables in schema catalogue, search, pipeline, scholarship, ref, security, cron to au_export_reader" >/dev/null
fingerprint() { $P -d $DB -Atc "select sum(n_tup_ins + n_tup_upd + n_tup_del) from pg_stat_user_tables" ; }
before=$($P -d $DB -Atc "select md5(string_agg(t, '' order by t)) from (select format('%s:%s', c.relname, (xpath('/row/n/text()', query_to_xml(format('select count(*) n from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text) t from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.relkind = 'r' and n.nspname in ('catalogue','search','pipeline','scholarship','ref','security')) x")
for mode in single fallback; do
  extra=""; [ $mode = fallback ] && extra="FORCE_SINGLE_ABORT=1"
  env PGUSER=au_export_reader PGPASSWORD=fixture PGDATABASE=$DB PACING=off BATCH=100 MODE=single GIT_SHA=fixture OUT_DIR=$OUT/$mode $extra node scripts/export/au-catalogue-export.mjs > $OUT/$mode.log 2>&1 || { tail -20 $OUT/$mode.log; exit 1; }
  node -e '
    const m = JSON.parse(require("fs").readFileSync(process.argv[1] + "/manifest.json", "utf8")); const mode = process.argv[2]
    const r = Object.fromEntries(m.datasets.map((d) => [d.name, d.rows]))
    const want = { courses: 260, course_fees: 806, course_intakes: 260, english_requirements: 234, course_links: 260, course_campuses: 240, course_identifiers: 260,
      course_pages_held: 234, course_scholarships: 242, scholarship_master: 2, scholarship_award_tiers: 1, scholarship_criteria: 1, course_entry_requirements: 52,
      provider_entry_matrices: 2, provider_rankings: 0, search_course_documents: 206, layer4_course_review_items: 2, providers: 2,
      website_api_v2_field_reconciliation: 206 * 25, field_state_reconciliation: 260 * 16 }
    const bad = Object.entries(want).filter(([k, v]) => r[k] !== v).map(([k, v]) => `${k}: ${r[k]} != ${v}`)
    const failed = m.checks.filter((c) => !c.pass).map((c) => c.check)
    const used = m.production_impact.mode_used
    if (bad.length || failed.length || !m.all_checks_pass) { console.error("counts:", bad, "failed checks:", failed); process.exit(1) }
    if (mode === "single" && (used !== "single" || m.snapshots.length !== 1)) { console.error("expected one snapshot"); process.exit(1) }
    if (mode === "fallback" && (used !== "per_dataset" || !m.production_impact.fallback || m.snapshots.length < 10)) { console.error("expected the per_dataset fall-back"); process.exit(1) }
    if (m.snapshots.some((s) => s.read_only !== "on" || s.isolation !== "repeatable read")) { console.error("a snapshot was not REPEATABLE READ READ ONLY"); process.exit(1) }
    console.log(`${mode}: ${m.checks.length} checks pass; ${m.snapshots.length} snapshot(s); ${m.production_impact.queries_run} queries; mode ${used}`)
  ' $OUT/$mode $mode
  if grep -q "About course\|Line one" $OUT/$mode.log; then echo "row data printed in the log"; exit 1; fi
done
python3 scripts/export/au-catalogue-workbook.py $OUT/single > $OUT/workbook.log
python3 -I -c '
import sys, openpyxl
wb = openpyxl.load_workbook(sys.argv[1] + "/au-catalogue-export.xlsx", read_only=True)
assert wb.sheetnames[0] == "Index", wb.sheetnames
c = wb["01 Courses"]; rows = list(c.iter_rows(values_only=True)); assert len(rows) == 261, len(rows)
h = rows[0]; d = dict(zip(h, rows[1])); assert d["description"] == "Line one, with a comma\nline two \"quoted\"", d["description"]
print("workbook:", len(wb.sheetnames), "sheets; courses sheet matches")
' $OUT/single
after=$($P -d $DB -Atc "select md5(string_agg(t, '' order by t)) from (select format('%s:%s', c.relname, (xpath('/row/n/text()', query_to_xml(format('select count(*) n from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text) t from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.relkind = 'r' and n.nspname in ('catalogue','search','pipeline','scholarship','ref','security')) x")
[ "$before" = "$after" ] || { echo "row counts changed"; exit 1; }
echo "database unchanged; select-only role; AU export fixtures pass"
