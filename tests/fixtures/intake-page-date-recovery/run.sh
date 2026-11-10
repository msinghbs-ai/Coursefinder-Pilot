#!/usr/bin/env bash
# Guards: F-INT page-date recovery (Platform Admin directive 10 Nov 2026 14:02: admit verified exact intake dates faster, never invent a day, month, year or deadline): migration 20261110170000 edits only
# security.intake_dates_plan_v3(uuid[],integer) and security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) and adds the read-only security.intake_page_date_hint_v1(uuid,uuid,text), on an
# isolated PostgreSQL copy of the production-equivalent fixture (tests/fixtures/intake-self-driving/run.sh, kept: it applies 20261109040000, 20261109041000 and the D1 page route 20261109042000). The two edited
# definitions are checked by md5 against production (read 10 Nov 2026), the cases run in two phases (the defects on the production code, then the fix), the migration is applied twice, a hand-changed definition is refused,
# the held forward recovery returns the earlier text byte for byte and is repeatable, and the consumer API (G3), every other definition and every setting are compared before and after. Never targets a remote database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=${PR_BASE:-intake_self_driving_fixtures}; DB=${PR_DB:-intake_page_date_recovery_fixtures}; RF=${DB}_refuse; F=tests/fixtures/intake-page-date-recovery
M=supabase/migrations/20261110170000_cf247_intake_page_date_recovery.sql
R=supabase/held/intake_page_date_recovery_forward_recovery.sql
PLAN='security.intake_dates_plan_v3(uuid[],integer)'; PD='security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'; HINT='security.intake_page_date_hint_v1(uuid,uuid,text)'
PLAN_BEFORE=0d11bc5dfc4b0705f0722a1aa7905db6; PLAN_AFTER=06255497ef431b0ae0d9fca6460c6cb5
PD_BEFORE=80eb7b805fa1d68910623c46308c15da;   PD_AFTER=52bad9ded722b889b97c746b7209e63a
HINT_AFTER=6adf9102074633735e9f30ffe529072c
P=(psql -X -q -v ON_ERROR_STOP=1)
q() { psql -X -d "$DB" -Atc "$1"; }
if ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  SD_REUSE=1 SD_KEEP=1 SD_DB=$BASE bash tests/fixtures/intake-self-driving/run.sh > /dev/null
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PR_KEEP:-}" ] || "${P[@]}" -d postgres -c "drop database if exists $DB" -c "drop database if exists $RF" >/dev/null 2>&1' EXIT

# the two edited definitions are the production ones (md5 of the function body, pg_proc.prosrc, read 10 Nov 2026 UTC, project fxcwkweaxjtknorudmwp), and so are the ones the change calls
declare -A LIVE=( ["$PLAN"]=$PLAN_BEFORE ["$PD"]=$PD_BEFORE ['security.intake_inputs_fp_v1(text,uuid,text,text)']=$(q "select md5(prosrc) from pg_proc where oid = 'security.intake_inputs_fp_v1(text,uuid,text,text)'::regprocedure") )
for sig in "$PLAN" "$PD"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from production ${LIVE[$sig]}"; exit 1; }
done
[ -z "$(q "select to_regprocedure('$HINT')")" ] || { echo "the hint exists before the migration"; exit 1; }
echo 'PASS parity: security.intake_dates_plan_v3 and security.intake_page_date_v1 as loaded = production (body md5, read 10 Nov 2026); the hint does not exist yet'

OUT=$("${P[@]}" -d $DB -f $F/cases-before.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-before'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'

# the consumer API (G3): every function of schema api and public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1 as it is before the migration
API_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'api' or (n.nspname = 'public' and (p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'website\_api\_v2\_%' or p.proname like 'zoho\_edge\_%' or p.proname = 'svc_website_settings_v1')) order by 1"
FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue') and p.prokind = 'f' order by 1"
SET="select toolset_key || '.' || key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$API_SQL" > "$1.api"; q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select md5(string_agg(i::text, '|' order by i.id)) from catalogue.course_intakes i" > "$1.int"; q "select md5(string_agg(d::text, '|' order by d.intake_id)) from pipeline.course_intake_dates d" > "$1.dec"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a live function that differs from the recorded one: the migration raises, the forward recovery raises, and nothing at all is applied
for target in "$PLAN" "$PD"; do
  "${P[@]}" -d postgres -c "drop database if exists $RF" -c "create database $RF template $DB"
  "${P[@]}" -d $RF -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$target'::regprocedure), '\mbegin\M', 'begin /* changed by hand */'); end \$\$" >/dev/null
  [ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$target'::regprocedure")" != "${LIVE[$target]}" ] || { echo "the hand change did not change $target"; exit 1; }
  rb=$( (psql -X -d $RF -Atc "$FNS" | md5sum; psql -X -d $RF -Atc "$SET" | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$HINT') is null") )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "$M applied over a changed $target"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | md5sum; psql -X -d $RF -Atc "$SET" | md5sum; psql -X -d $RF -Atc "select to_regprocedure('$HINT') is null") )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something ($target)"; exit 1; }
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the forward recovery ran over a changed $target"; exit 1; }
  grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
done
"${P[@]}" -d postgres -c "drop database if exists $RF"
echo 'PASS refused: a hand-changed live plan and page route are each refused by the migration and by its forward recovery, and nothing is applied (no function, setting or hint)'

# the migration: the plan and the page route go from the recorded production md5 to the recorded after md5, one read-only function is added, nothing else changes; applying it twice changes nothing
snap "$W/0"
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$PLAN: applied" <<<"$OUT" || { echo "the plan was not edited"; echo "$OUT" | tail -8; exit 1; }
for x in "$PLAN $PLAN_AFTER" "$PD $PD_AFTER" "$HINT $HINT_AFTER"; do set -- $x; [ "$(q "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure")" = "$2" ] || { echo "$1 has not the recorded body md5 $2"; exit 1; }; done
for want in "$PLAN $PLAN_BEFORE -> $PLAN_AFTER" "$PD $PD_BEFORE -> $PD_AFTER" "$HINT (new) -> $HINT_AFTER"; do grep -qF -- "--   $want" $M || { echo "the migration header does not record: $want"; exit 1; }; done
snap "$W/1"
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$(printf '%s\n' "$PD" "$PLAN" | sort)" ] || { echo "the changed functions differ from the edited ones:"; echo "$changed"; exit 1; }
added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$changed"))
[ "$added" = "$HINT" ] || { echo "the added function is not just the hint: $added"; exit 1; }
same "$W/0" "$W/1" set int dec api
[ -n "$(q "select obj_description('$HINT'::regprocedure, 'pg_proc')")" ] || { echo "the new function has no comment"; exit 1; }
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$PLAN: already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/2"; same "$W/1" "$W/2" fn set int dec api
echo "PASS migration 20261110170000: the plan and the page route go from the production md5 to the recorded after md5, the hint (read only) is added, no setting value, intake or decision row changed, the consumer API ($(wc -l < "$W/2.api") functions of schema api, website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1 in this database) is identical (md5 of the definition) before and after; applied again: no change"

OUT=$("${P[@]}" -d $DB -f $F/cases-after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-after'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
q "$API_SQL" > "$W/api-after-cases"; cmp -s "$W/0.api" "$W/api-after-cases" || { echo 'FAIL consumer API changed by the cases (G3)'; exit 1; }

# the md5 of the three definitions as this change leaves them (the workflow log records them)
echo "md5 $PLAN $PLAN_AFTER"; echo "md5 $PD $PD_AFTER"; echo "md5 $HINT $HINT_AFTER"

# Data Delivery (20261110171000): the stream's intake counts. The fixture has no Data Delivery, so the live function (body md5 849453412a8b9a448118e7b87362752a, read 10 Nov 2026) is loaded from the text the earlier held recovery restores.
# Three streams edit security.data_delivery_v1 (pdesc, aer in #989, int here), so this edit is ONE ANCHORED LINE applied once to whatever body is live; it is proved on the live body, on the body #989 leaves, in both orders, and when the anchor is gone.
M2=supabase/migrations/20261110171000_cf247_dd_intake_delivery.sql; R2=supabase/held/dd_intake_delivery_forward_recovery.sql
DDV='security.data_delivery_v1()'; DDI='security.data_delivery_intake_v1()'
DD_LIVE=849453412a8b9a448118e7b87362752a; DD_AER=04b560cfb6b79758e2b694c96771be33; DD_AFTER=630f8696c18ff05703bb9798ed6fe8fa; DDI_AFTER=ed0361e1ab65cf4525836f4fdd055287
sed -n '/^CREATE OR REPLACE FUNCTION security.data_delivery_v1()/,/^\$function\$;$/p' supabase/held/dd_provider_ai_allowance_forward_recovery.sql > "$W/dd-b67.sql"
# the live body = the b67 text (the held recovery of 20261110150000) with its provider_ai line: build it as that migration did
(echo 'set check_function_bodies = off;'; cat "$W/dd-b67.sql") | "${P[@]}" -d $DB -o /dev/null
"${P[@]}" -d $DB -c "do \$x\$ declare d text := pg_get_functiondef('$DDV'::regprocedure); o text := \$o\$      'stages', case when s.stream = 'cdesc' then security.data_delivery_cdesc_stages_v1() end,\$o\$; begin execute replace(d, o, o || chr(10) || \$n\$      'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,\$n\$); end \$x\$" > /dev/null
[ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = $DD_LIVE ] || { echo "the loaded Data Delivery differs from production $DD_LIVE"; exit 1; }
echo 'PASS parity: security.data_delivery_v1 as loaded = production (body md5 849453412a8b9a448118e7b87362752a, read 10 Nov 2026)'
minus_md5() { psql -X -d "$1" -Atc "select md5(replace(prosrc, E'\n      ''intake_delivery'', case when s.stream = ''int'' then security.data_delivery_intake_v1() end,', '')) from pg_proc where oid = '$DDV'::regprocedure"; }
md5db() { psql -X -d "$1" -Atc "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure"; }
cnt() { psql -X -d "$1" -Atc "select (length(prosrc) - length(replace(prosrc, '$2', ''))) / length('$2') from pg_proc where oid = '$DDV'::regprocedure"; }
scen() { # name, base prep file or '-', then the order: mine-first (m) or aer-first (a)
  local name=$1 prep=$2 order=$3 D=${DB}_dd
  "${P[@]}" -d postgres -c "drop database if exists $D" -c "create database $D template $DB"
  [ "$prep" = "-" ] || "${P[@]}" -d $D -f "$prep" > /dev/null
  base=$(md5db $D)
  [ "$order" = "a" ] && "${P[@]}" -d $D -f $F/dd-aer-edit.sql > /dev/null
  OUT=$("${P[@]}" -d $D -At -1 -f $M2 2>&1) || { echo "$name: the Data Delivery migration failed: $OUT" | tail -5; exit 1; }
  grep -qF "security.data_delivery_v1(): applied" <<<"$OUT" || { echo "$name: not applied: $OUT" | tail -3; exit 1; }
  [ "$(md5db $D)" != "$base" ] || { echo "$name: the body did not change"; exit 1; }
  [ "$(psql -X -d $D -Atc "select md5(prosrc) from pg_proc where oid = '$DDI'::regprocedure")" = $DDI_AFTER ] || { echo "$name: the intake counts have not the recorded body md5"; exit 1; }
  for k in 'data_delivery_intake_v1' 'data_delivery_pdesc_v1' 'data_delivery_cdesc_stages_v1'; do [ "$(cnt $D "$k")" = 1 ] || { echo "$name: $k is not in the body exactly once"; exit 1; }; done
  # the one added line only: taking it out returns the base byte for byte
  [ "$(minus_md5 $D)" = "$base" ] || { echo "$name: taking our line out does not return the base byte for byte"; exit 1; }
  OUT=$("${P[@]}" -d $D -At -1 -f $M2 2>&1) || { echo "$name: second run failed"; exit 1; }
  grep -qF "already carries the intake key" <<<"$OUT" || { echo "$name: the second run was not a no-op"; exit 1; }
  # the other stream's line arrives after ours: both keys, each once
  "${P[@]}" -d $D -f $F/dd-aer-edit.sql > /dev/null
  [ "$(cnt $D 'data_delivery_aer_v1')" = 1 ] && [ "$(cnt $D 'data_delivery_intake_v1')" = 1 ] || { echo "$name: the two keys are not both there exactly once"; exit 1; }
  # the forward recovery removes only our line: with the AER line in, the body is the AER body (or the live body when the AER line is not wanted)
  "${P[@]}" -d $D -At -1 -f $R2 > /dev/null || { echo "$name: the forward recovery failed"; exit 1; }
  [ "$(cnt $D 'data_delivery_intake_v1')" = 0 ] && [ "$(cnt $D 'data_delivery_aer_v1')" = 1 ] || { echo "$name: the recovery did not remove only our line"; exit 1; }
  [ "$(md5db $D)" = $DD_AER ] || { echo "$name: after the recovery the body is not the AER body ($(md5db $D))"; exit 1; }
  OUT=$("${P[@]}" -d $D -At -1 -f $R2 2>&1) || { echo "$name: the recovery is not repeatable"; exit 1; }
  grep -qF "nothing to remove" <<<"$OUT" || { echo "$name: the second recovery was not a no-op"; exit 1; }
  "${P[@]}" -d $D -At -1 -f $M2 > /dev/null && [ "$(cnt $D 'data_delivery_intake_v1')" = 1 ] || { echo "$name: the migration did not apply again after the recovery"; exit 1; }
  "${P[@]}" -d postgres -c "drop database if exists $D"
}
# a: our edit on the live body; then the AER line arrives
scen live - m
# b: our edit on the body #989 leaves (its anchored line applied first)
scen aer_first $F/dd-aer-edit.sql m
# c: the body #989 leaves is the md5 recorded in its migration
"${P[@]}" -d postgres -c "drop database if exists ${DB}_dd" -c "create database ${DB}_dd template $DB"
"${P[@]}" -d ${DB}_dd -f $F/dd-aer-edit.sql > /dev/null
[ "$(md5db ${DB}_dd)" = $DD_AER ] || { echo "the body with the AER line is not the one #989 records ($(md5db ${DB}_dd))"; exit 1; }
# d: the anchor is gone: refused, nothing applied
"${P[@]}" -d postgres -c "drop database if exists ${DB}_dd" -c "create database ${DB}_dd template $DB"
"${P[@]}" -d ${DB}_dd -f $F/dd-no-anchor.sql > /dev/null
b4=$(md5db ${DB}_dd)
OUT=$("${P[@]}" -d ${DB}_dd -At -1 -f $M2 2>&1) && { echo "the migration applied without its anchor"; exit 1; }
grep -qF "the anchor line (the provider_ai key) must be found exactly once" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(md5db ${DB}_dd)" = "$b4" ] && [ -z "$(psql -X -d ${DB}_dd -Atc "select to_regprocedure('$DDI')")" ] || { echo "the refused migration changed something"; exit 1; }
"${P[@]}" -d postgres -c "drop database if exists ${DB}_dd"
echo "PASS migration 20261110171000 anchored edit: on the live body (849453...) it adds one line and the intake counts; on the body #989 leaves (04b560cf...) the same; the AER line applied after ours leaves both keys once; applied again: a no-op; the forward recovery removes only our line (the AER body 04b560cf... returns byte for byte), is repeatable, and the migration applies again after it; without its anchor it is refused and applies nothing"

# the main database: our edit on the live body, for the count cases (and the consumer API, definitions and settings compared)
snap "$W/d0"
"${P[@]}" -d $DB -At -1 -f $M2 > /dev/null || { echo 'the Data Delivery migration failed'; exit 1; }
[ "$(md5db $DB)" = $DD_AFTER ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$DDI'::regprocedure")" = $DDI_AFTER ] || { echo 'Data Delivery or the intake counts have not the recorded body md5'; exit 1; }
grep -qF -- "--   security.data_delivery_intake_v1() (new) -> $DDI_AFTER" $M2 || { echo 'the migration header does not record the intake counts md5'; exit 1; }
snap "$W/d1"
[ "$(comm -23 "$W/d0.fn" "$W/d1.fn" | sed 's/ [0-9a-f]*$//')" = "$DDV" ] && [ "$(comm -13 "$W/d0.fn" "$W/d1.fn" | sed 's/ [0-9a-f]*$//' | grep -vxF "$DDV")" = "$DDI" ] || { echo 'the Data Delivery migration changed more than Data Delivery and added more than the intake counts'; exit 1; }
same "$W/d0" "$W/d1" set int dec api
[ "$(minus_md5 $DB)" = $DD_LIVE ] || { echo 'taking our line out does not return the production text byte for byte'; exit 1; }
echo "PASS migration 20261110171000: the intake counts are added (1 function, comment, no grant to anon or authenticated), Data Delivery gains one line, nothing else changes, the consumer API is identical"
OUT=$("${P[@]}" -d $DB -f $F/dd-cases.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL dd-cases'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
echo "md5 $DDV $DD_AFTER"; echo "md5 $DDI $DDI_AFTER"

# forward recovery: the earlier bodies return byte for byte, the decisions and dates are untouched, it is repeatable, and the migration applies again afterwards
snap "$W/pre"
"${P[@]}" -d $DB -At -1 -f $R >/dev/null || { echo "the forward recovery failed"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$PLAN'::regprocedure")" = $PLAN_BEFORE ] && [ "$(q "select md5(prosrc) from pg_proc where oid = '$PD'::regprocedure")" = $PD_BEFORE ] || { echo "the recovery did not restore the plan and the page route byte for byte"; exit 1; }
snap "$W/rec"; same "$W/pre" "$W/rec" set int dec api
"${P[@]}" -d $DB -At -1 -f $R >/dev/null || { echo "the forward recovery is not repeatable"; exit 1; }
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$PLAN: applied" <<<"$OUT" || { echo "after the recovery the migration did not apply"; exit 1; }
echo 'PASS recovery: the forward recovery returns the plan and the page route to the production md5 byte for byte (settings, intakes, decisions and the consumer API untouched; the hint stays, unused); repeatable; the migration applies again afterwards'
echo 'intake-page-date-recovery: done'
