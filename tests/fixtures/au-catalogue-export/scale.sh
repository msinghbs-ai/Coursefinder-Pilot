#!/usr/bin/env bash
# AU catalogue export at live scale on isolated fixtures (2 Nov 2026 run 41377240304: Node heap out of memory during verification).
# Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the fixtures plus scale.sql (live AU
# counts of 2 Nov), runs the export under a Node heap cap (SCALE_HEAP_MB, default 512) and requires every manifest check to pass and the
# peak resident memory recorded in the manifest to stay under SCALE_RSS_MB (default 2048). Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AUX_DB:-au_export_scale}
P="psql -v ON_ERROR_STOP=1 -q -X"
OUT=${AUX_OUT:-$(mktemp -d)}; mkdir -p "$OUT"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${AUX_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
node tests/fixtures/au-catalogue-export/schema.mjs | $P -d $DB >/dev/null
$P -d $DB -f tests/fixtures/au-catalogue-export/fixtures.sql >/dev/null
$P -d $DB -v n=${SCALE_COURSES:-26652} -f tests/fixtures/au-catalogue-export/scale.sql >/dev/null
$P -d $DB -c "analyze" >/dev/null
$P -d $DB -Atc "select 'scaled fixture: ' || (select count(*) from catalogue.courses c join catalogue.providers p on p.id = c.provider_id where p.country_id = '00000000-0000-0000-0000-0000000000a1') || ' AU courses, ' || (select count(*) from catalogue.course_fees) || ' fees, ' || (select count(*) from scholarship.course_mappings) || ' scholarship links, ' || (select count(*) from catalogue.course_campuses) || ' campus rows, ' || (select count(*) from search.course_documents) || ' projection rows, ' || (select count(*) from pipeline.layer4_review_items) || ' Layer 4 items'"
set +e
env PGDATABASE=$DB PACING=off MODE=${SCALE_MODE:-single} GIT_SHA=fixture OUT_DIR=$OUT/export NODE_OPTIONS=--max-old-space-size=${SCALE_HEAP_MB:-512} node ${EXPORT_SCRIPT:-scripts/export/au-catalogue-export.mjs} > $OUT/scale.log 2>&1
code=$?
set -e
tail -3 $OUT/scale.log
[ $code = 0 ] || { echo "export failed under a ${SCALE_HEAP_MB:-512} MB heap (exit $code)"; exit 1; }
node -e '
  const m = JSON.parse(require("fs").readFileSync(process.argv[1] + "/manifest.json", "utf8"))
  const failed = m.checks.filter((c) => !c.pass).map((c) => c.check)
  if (!m.all_checks_pass || failed.length) { console.error("failed checks:", failed); process.exit(1) }
  const rss = m.memory && m.memory.max_rss_mb
  if (!(rss > 0) || rss > Number(process.argv[2])) { console.error(`peak resident memory ${rss} MB is over ${process.argv[2]} MB`); process.exit(1) }
  const r = Object.fromEntries(m.datasets.map((d) => [d.name, d.rows]))
  console.log(`scale: ${m.checks.length} checks pass; ${r.courses} courses, ${r.course_fees} fees, ${r.website_api_v2_field_reconciliation} reconciliation rows, ${r.field_state_reconciliation} field-state rows; peak resident ${rss} MB, peak heap ${m.memory.max_heap_mb} MB`)
' $OUT/export ${SCALE_RSS_MB:-2048}
