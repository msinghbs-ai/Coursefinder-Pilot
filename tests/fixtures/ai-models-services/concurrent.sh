#!/usr/bin/env bash
# CF-247 AI models and services: the five migrations applied while writers keep recording AI costs and reading settings (independent QA B2, 13 Nov
# 2026: the first version held ACCESS EXCLUSIVE on pipeline.ai_spend_ledger through its backfill and then on pipeline.platform_toolset_settings,
# and deadlocked against a concurrent record). Usage: concurrent.sh <database that is as live, before the migrations>. Scratch PostgreSQL only.
# Three writers loop, each statement under the 8 second lock_timeout of a PostgREST session:
#   a  reads settings, then records a cost (the cost trigger inserts into the ledger)        b  records a cost, then reads settings
#   c  inserts a ledger row and reads a setting through security.pipeline_num_v1
# Passes when every migration applies, no writer statement fails (no deadlock, no lock time-out) and no writer waited 3 seconds for a lock.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=$1; P="psql -X -q -v ON_ERROR_STOP=1"; OUT=$(mktemp -d)
MIGS="20261113377000_cf247_ai_ledger_columns 20261113378000_cf247_ai_settings_home_columns 20261113379000_cf247_ai_item_model_column 20261113380000_cf247_ai_models_services 20261113390000_cf247_ai_routes_only"
ROWS=${AIMS_LEDGER_ROWS:-80000}
$P -d $DB -c "insert into pipeline.ai_spend_ledger (lane, source, source_id, cost_usd) select 'enrich_fields', 'field_enrich_items', (1 + g % 5)::text, 0.0005 from generate_series(1, $ROWS) g" >/dev/null
ITEM=$($P -d $DB -Atc "select id from pipeline.field_enrich_items order by id limit 1")
writer() {  # name, statements of one transaction
  local n=0
  while [ ! -e $OUT/stop ]; do
    S=$(date +%s%N)
    if ! psql -X -q -v ON_ERROR_STOP=1 -d $DB -c "set lock_timeout = '8s'" -c "begin" -c "$2" -c "$3" -c "commit" >/dev/null 2>>$OUT/$1.err; then echo fail >> $OUT/$1.fail; fi
    echo $(( ($(date +%s%N) - S) / 1000000 )) >> $OUT/$1.ms; n=$((n + 1))
  done; echo $n > $OUT/$1.n
}
writer a "select count(*) from pipeline.platform_toolset_settings" "update pipeline.field_enrich_items set cost_usd = coalesce(cost_usd, 0) + 0.0001 where id = $ITEM" &
writer b "insert into pipeline.ai_spend_ledger (lane, source, source_id, cost_usd) values ('scholarship_ai', 'scholarship_ai_extractions', '1', 0.0001)" "select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline'" &
writer c "insert into pipeline.ai_spend_ledger (lane, source, source_id, cost_usd) values ('fee_ai', 'fee_reader_queue', null, 0.0001)" "select security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)" &
sleep 2
for m in $MIGS; do
  S=$(date +%s%N)
  for try in 1 2 3; do  # a columns step that cannot have its lock in 3 seconds fails fast and is simply run again
    if $P -d $DB -1 -f supabase/migrations/$m.sql >/dev/null 2>$OUT/mig.err; then break; fi
    grep -q "lock timeout" $OUT/mig.err && [ $try -lt 3 ] || { echo "$m failed:"; tail -3 $OUT/mig.err; touch $OUT/stop; wait; exit 1; }
  done
  echo "applied $m in $(( ($(date +%s%N) - S) / 1000000 )) ms (attempt $try)"
done
sleep 2; touch $OUT/stop; wait
FAILS=$( (cat $OUT/*.fail 2>/dev/null || true) | wc -l); MAX=$(cat $OUT/*.ms | sort -n | tail -1); N=$(cat $OUT/*.n | awk "{s += \$1} END {print s}")
echo "writers: $N transactions, $FAILS failed, slowest $MAX ms; ledger rows without a service: $($P -d $DB -Atc "select count(*) from pipeline.ai_spend_ledger where service_code is null")"
[ "$FAILS" = 0 ] || { echo "a writer failed:"; sort $OUT/*.err | uniq -c | head -5; exit 1; }
[ "$MAX" -lt 3000 ] || { echo "a writer waited $MAX ms"; exit 1; }
echo "concurrent writers: no deadlock, no lock time-out, no wait of 3 seconds"
