#!/usr/bin/env bash
# Guards: F-INT intake dates, hyphenated day-month-year (Platform Admin, 10 Nov 2026 22:01: "Go ahead 1 and 4", Group 1, Swinburne): migration 20261110110523 edits only
# security.intake_page_date_hint_v1(uuid,uuid,text), security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) and security.intake_dates_plan_v3(uuid[],integer),
# on an isolated PostgreSQL copy of the database tests/fixtures/intake-page-date-recovery/run.sh leaves (kept: it applies 20261110170000, whose bodies are this change's before bodies). The three
# definitions are checked by md5 against production (read 10 Nov 2026), the cases run in two phases (the defect on the production code, then the fix), a hand-changed definition is refused,
# the migration is applied twice, the held forward recovery returns the earlier text byte for byte and is repeatable, and the consumer API (G3), every other definition and every setting are
# compared before and after. Never targets a remote database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=${HD_BASE:-intake_page_date_recovery_fixtures}; DB=${HD_DB:-intake_hyphen_dates_fixtures}; RF=${DB}_refuse; F=tests/fixtures/intake-hyphen-dates
M=supabase/migrations/20261110110523_cf247_intake_hyphen_dates.sql
R=supabase/held/intake_hyphen_dates_forward_recovery.sql
HINT='security.intake_page_date_hint_v1(uuid,uuid,text)'; PD='security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'; PLAN='security.intake_dates_plan_v3(uuid[],integer)'
declare -A BEFORE=( ["$HINT"]=6adf9102074633735e9f30ffe529072c ["$PD"]=52bad9ded722b889b97c746b7209e63a ["$PLAN"]=06255497ef431b0ae0d9fca6460c6cb5 )
declare -A AFTER=(  ["$HINT"]=7e008fa7981cf32ab89765829b7a3439 ["$PD"]=de956842ab53e842c7b4baaf578ff0f0 ["$PLAN"]=33e3fef045dbcfa8a0406c64402d4d29 )
P=(psql -X -q -v ON_ERROR_STOP=1)
q() { psql -X -d "$DB" -Atc "$1"; }
body() { psql -X -d "$1" -Atc "select md5(prosrc) from pg_proc where oid = '$2'::regprocedure"; }
if ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  PR_KEEP=1 bash tests/fixtures/intake-page-date-recovery/run.sh > /dev/null
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${HD_KEEP:-}" ] || "${P[@]}" -d postgres -c "drop database if exists $DB" -c "drop database if exists $RF" >/dev/null 2>&1' EXIT

# the three edited definitions are the production ones (md5 of the function body, pg_proc.prosrc, read 10 Nov 2026 AEDT, project fxcwkweaxjtknorudmwp)
for sig in "$HINT" "$PD" "$PLAN"; do [ "$(body $DB "$sig")" = "${BEFORE[$sig]}" ] || { echo "the loaded $sig differs from production ${BEFORE[$sig]} ($(body $DB "$sig"))"; exit 1; }; done
echo 'PASS parity: the hint, the page route and the plan as loaded = production before 20261110110523 (body md5, read 10 Nov 2026)'

OUT=$("${P[@]}" -d $DB -f $F/cases-before.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-before'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'

API_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'api' or (n.nspname = 'public' and (p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'website\_api\_v2\_%' or p.proname like 'zoho\_edge\_%' or p.proname = 'svc_website_settings_v1')) order by 1"
FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue') and p.prokind = 'f' order by 1"
SET="select toolset_key || '.' || key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
INT="select md5(string_agg(i::text, '|' order by i.id)) from catalogue.course_intakes i"
DEC="select md5(string_agg(d::text, '|' order by d.intake_id)) from pipeline.course_intake_dates d"
snap() { q "$API_SQL" > "$1.api"; q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "$INT" > "$1.int"; q "$DEC" > "$1.dec"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a live function that differs from the recorded one: the migration raises, the forward recovery raises, and nothing at all is applied
for target in "$HINT" "$PD" "$PLAN"; do
  "${P[@]}" -d postgres -c "drop database if exists $RF" -c "create database $RF template $DB"
  "${P[@]}" -d $RF -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$target'::regprocedure), '\mbegin\M', 'begin /* changed by hand */'); end \$\$" >/dev/null
  [ "$(body $RF "$target")" != "${BEFORE[$target]}" ] || { echo "the hand change did not change $target"; exit 1; }
  rb=$(psql -X -d $RF -Atc "$FNS" | md5sum)
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "$M applied over a changed $target"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  [ "$rb" = "$(psql -X -d $RF -Atc "$FNS" | md5sum)" ] || { echo "the refused migration changed something ($target)"; exit 1; }
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the forward recovery ran over a changed $target"; exit 1; }
  grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
done
"${P[@]}" -d postgres -c "drop database if exists $RF"
echo 'PASS refused: a hand-changed hint, page route or plan is refused by the migration and by its forward recovery, and nothing is applied'

# the migration: the three bodies go from the production md5 to the recorded after md5, nothing else changes; applying it twice changes nothing
snap "$W/0"
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$HINT" "$PD" "$PLAN"; do
  grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }
  [ "$(body $DB "$sig")" = "${AFTER[$sig]}" ] || { echo "$sig has not the recorded body md5 ${AFTER[$sig]}"; exit 1; }
  grep -qF -- "--   $sig ${BEFORE[$sig]} -> ${AFTER[$sig]}" $M || { echo "the migration header does not record $sig"; exit 1; }
done
snap "$W/1"
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$(printf '%s\n' "$HINT" "$PD" "$PLAN" | sort)" ] || { echo "the changed functions differ from the edited ones:"; echo "$changed"; exit 1; }
[ -z "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$changed"))" ] || { echo "the migration added a function"; exit 1; }
same "$W/0" "$W/1" api set int dec
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(grep -cF ': already applied' <<<"$OUT")" -ge 3 ] || { echo "the second run was not a no-op"; echo "$OUT" | tail -5; exit 1; }
snap "$W/2"; same "$W/1" "$W/2" fn api set int dec
echo "PASS migration 20261110110523: the hint, the page route and the plan go from the production md5 to the recorded after md5; no other definition, setting, intake or decision changed; the consumer API ($(wc -l < "$W/2.api") functions) is identical; applied again: a no-op"

OUT=$("${P[@]}" -d $DB -f $F/cases-after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-after'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
snap "$W/3"; same "$W/2" "$W/3" api set fn
for sig in "$HINT" "$PD" "$PLAN"; do echo "md5 $sig ${AFTER[$sig]}"; done

# forward recovery: the earlier bodies return byte for byte, intakes, decisions, settings and the consumer API are untouched, it is repeatable, and the migration applies again afterwards
snap "$W/pre"
OUT=$("${P[@]}" -d $DB -At -1 -f $R 2>&1) || { echo "the forward recovery failed: $OUT" | tail -5; exit 1; }
for sig in "$HINT" "$PD" "$PLAN"; do [ "$(body $DB "$sig")" = "${BEFORE[$sig]}" ] || { echo "the recovery did not restore $sig byte for byte"; exit 1; }; done
snap "$W/rec"; same "$W/pre" "$W/rec" api set int dec
OUT=$("${P[@]}" -d $DB -At -1 -f $R 2>&1) || { echo "the forward recovery is not repeatable"; exit 1; }
[ "$(grep -cF ': nothing to restore' <<<"$OUT")" -ge 3 ] || { echo "the second recovery was not a no-op"; exit 1; }
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "$HINT" "$PD" "$PLAN"; do [ "$(body $DB "$sig")" = "${AFTER[$sig]}" ] || { echo "after the recovery the migration did not apply $sig"; exit 1; }; done
echo 'PASS recovery: the forward recovery returns the hint, the page route and the plan to the production md5 byte for byte (intakes, decisions, settings and the consumer API untouched); repeatable; the migration applies again afterwards'
echo 'intake-hyphen-dates: done'
