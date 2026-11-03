#!/usr/bin/env bash
# CF-247 IQ-00111: executes the containment paste, a second run (must refuse), the correction (and a refused second run), the correction rollback,
# the containment rollback and the interim stop on a stub database (scratch PostgreSQL only).
set -euo pipefail
D=${1:-cf_fee_units_paste}; H=/var/run/postgresql; P="psql -h $H -U postgres -v ON_ERROR_STOP=1 -qAt"
here=$(cd "$(dirname "$0")" && pwd); paste=$here/../../../docs/paste
dropdb -h $H -U postgres --if-exists $D; createdb -h $H -U postgres $D
$P -d $D -f $here/paste-stub.sql; $P -d $D -f $here/paste-rows.sql
# the stub notes differ from live, so the md5 guard values are rewritten to the stub notes' md5 (only those 13 literals change)
tmp=$(mktemp); cp $paste/PASTE-20261104-fee-units-holds-containment.sql $tmp
for row in $($P -d $D -c "select id||':'||md5(notes) from catalogue.course_fees"); do
  id=${row%%:*}; m=${row##*:}; sed -i -E "s/('$id', '[0-9a-f-]+', [0-9.]+, [0-9]+, ')[0-9a-f]{32}'/\1$m'/" $tmp; done
$P -d $D -f $tmp
echo "inactive=$($P -d $D -c "select count(*) from catalogue.course_fees where status='inactive' and notes like '%IQ-00111 P0 containment%'")"
echo "events=$($P -d $D -c "select count(*) from pipeline.admin_control_events where detail->>'batch'='IQ111-CONTAIN-20261104'")"
echo "savings_on_withdrawn=$($P -d $D -c "select count(*) from scholarship.course_financial_calculations fc join catalogue.course_fees f on f.id=fc.course_fee_id where f.status='inactive'")"
if $P -d $D -f $tmp 2>/dev/null; then echo "SECOND RUN CHANGED SOMETHING"; exit 1; else echo "second run refused (guard)"; fi
$P -d $D -f $paste/PASTE-20261104-fee-units-holds-correction.sql
echo "corrected=$($P -d $D -c "select count(*) from catalogue.course_fees where course_id='d9dc5bb8-025b-46ca-ac24-7ca13157599f' and status='active' and amount=37800 and fee_year=2027 and evidence_id='a58f1c88-e3de-4561-b4f9-0c415b960da0'") lock=$($P -d $D -c "select mode from pipeline.manual_locks") hold=$($P -d $D -c "select state from pipeline.enrichment_flags")"
if $P -d $D -f $paste/PASTE-20261104-fee-units-holds-correction.sql 2>/dev/null; then echo "SECOND CORRECTION CHANGED SOMETHING"; exit 1; else echo "second correction refused (guard)"; fi
$P -d $D -f $paste/PASTE-20261104-fee-units-holds-correction-rollback.sql
echo "after correction rollback: active_37800=$($P -d $D -c "select count(*) from catalogue.course_fees where amount=37800 and status='active'") hold=$($P -d $D -c "select state from pipeline.enrichment_flags")"
$P -d $D -f $paste/PASTE-20261104-fee-units-holds-containment-rollback.sql
echo "active_after_rollback=$($P -d $D -c "select count(*) from catalogue.course_fees where status='active' and valid_to is null and notes not like '%IQ-00111%' and notes not like 'Manual entry%'")"
$P -d $D -f $paste/PASTE-20261104-fee-units-holds-interim-stop.sql
echo "course_pages=$($P -d $D -c "select value from pipeline.platform_toolset_settings where key='fees.course_pages'")"
rm -f $tmp
