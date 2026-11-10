#!/usr/bin/env bash
# Guards: F-INT calendar re-read for every eligible provider (Platform Admin 10 Nov 2026 ~23:40, "Re-read and column fix first"; Decisions 273, 274): the migration adds
# security.calendar_reread_relevant_v2() and edits only public.svc_calendar_reread_next_v2(integer,text), on an isolated PostgreSQL copy of the database
# tests/fixtures/intake-page-date-recovery/run.sh leaves (kept). The edited definition is checked by md5 against production (read 10 Nov 2026), the cases run before and after,
# a hand-changed definition is refused, the migration is applied twice, the held forward recovery returns the earlier text byte for byte and is repeatable, and the consumer API
# (G3), every other definition and every setting value (calendar.countries aside, which the cases set as production holds it) are compared. Never targets a remote database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=${CR_BASE:-intake_page_date_recovery_fixtures}; DB=${CR_DB:-calendar_reread_all_fixtures}; RF=${DB}_refuse; F=tests/fixtures/calendar-reread-all-providers
M=$(ls supabase/migrations/*_cf247_calendar_reread_all_providers.sql | head -1)
R=supabase/held/calendar_reread_all_providers_forward_recovery.sql
NEXT='public.svc_calendar_reread_next_v2(integer,text)'; REL='security.calendar_reread_relevant_v2()'
NEXT_BEFORE=755ef3b77c797c89fa2caa215e33d4ee; NEXT_AFTER=6bede79de2f656b4bc9de6ea783696b6; REL_AFTER=42e2c5a73dbfbf6cacc333ffb92a9b61
P=(psql -X -q -v ON_ERROR_STOP=1)
q() { psql -X -d "$DB" -Atc "$1"; }
body() { psql -X -d "$1" -Atc "select md5(prosrc) from pg_proc where oid = to_regprocedure('$2')"; }
if ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  PR_KEEP=1 bash tests/fixtures/intake-page-date-recovery/run.sh > /dev/null
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${CR_KEEP:-}" ] || "${P[@]}" -d postgres -c "drop database if exists $DB" -c "drop database if exists $RF" >/dev/null 2>&1' EXIT

[ "$(body $DB "$NEXT")" = $NEXT_BEFORE ] || { echo "the loaded picker differs from production $NEXT_BEFORE"; exit 1; }
[ "$(body $DB 'security.calendar_reread_relevant_v1()')" = 7d63f344a425d9a2c302d47ba45430b4 ] || { echo "the loaded pilot-scope relevance differs from production"; exit 1; }
[ -z "$(q "select to_regprocedure('$REL')")" ] || { echo "v2 exists before the migration"; exit 1; }
echo 'PASS parity: the re-read picker and the pilot-scope relevance as loaded = production (body md5, read 10 Nov 2026); v2 does not exist yet'
OUT=$("${P[@]}" -d $DB -f $F/cases-before.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-before'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
q "create table public.cr_refresh_before as select md5(prosrc) md5 from pg_proc where oid = to_regprocedure('public.svc_calendar_refresh_v1(text)')" >/dev/null

API_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'api' or (n.nspname = 'public' and (p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'website\_api\_v2\_%' or p.proname like 'zoho\_edge\_%' or p.proname = 'svc_website_settings_v1')) order by 1"
FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue') and p.prokind = 'f' order by 1"
SET="select toolset_key || '.' || key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
INT="select md5(string_agg(i::text, '|' order by i.id)) from catalogue.course_intakes i"
snap() { q "$API_SQL" > "$1.api"; q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "$INT" > "$1.int"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a hand-changed picker: the migration and the forward recovery both refuse, and nothing is applied
"${P[@]}" -d postgres -c "drop database if exists $RF" -c "create database $RF template $DB"
"${P[@]}" -d $RF -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$NEXT'::regprocedure), '\mbegin\M', 'begin /* changed by hand */'); end \$\$" >/dev/null
rb=$(psql -X -d $RF -Atc "$FNS" | md5sum)
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "$M applied over a changed picker"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$rb" = "$(psql -X -d $RF -Atc "$FNS" | md5sum)" ] || { echo "the refused migration changed something"; exit 1; }
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the forward recovery ran over a changed picker"; exit 1; }
grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one: $OUT" | tail -3; exit 1; }
"${P[@]}" -d postgres -c "drop database if exists $RF"
echo 'PASS refused: a hand-changed picker is refused by the migration and by its forward recovery, and nothing is applied (v2 is not created either)'

snap "$W/0"
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$NEXT: applied" <<<"$OUT" || { echo "the picker was not edited"; echo "$OUT" | tail -5; exit 1; }
[ "$(body $DB "$NEXT")" = $NEXT_AFTER ] && [ "$(body $DB "$REL")" = $REL_AFTER ] || { echo "the recorded after md5 does not hold"; exit 1; }
grep -qF -- "--   $NEXT $NEXT_BEFORE -> $NEXT_AFTER" $M && grep -qF -- "--   $REL (new) -> $REL_AFTER" $M || { echo "the migration header does not record the md5s"; exit 1; }
snap "$W/1"
NEXT_TXT=$(q "select '$NEXT'::regprocedure::text"); REL_TXT=$(q "select '$REL'::regprocedure::text")
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//')
[ "$changed" = "$NEXT_TXT" ] || { echo "the changed functions differ from the edited one: $changed"; exit 1; }
[ "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | grep -vxF "$NEXT_TXT")" = "$REL_TXT" ] || { echo "the migration added more than v2"; exit 1; }
same "$W/0" "$W/1" api set int
[ -n "$(q "select obj_description('$REL'::regprocedure, 'pg_proc')")" ] || { echo "v2 has no comment"; exit 1; }
[ "$(q "select has_function_privilege('anon', '$REL', 'execute') or has_function_privilege('authenticated', '$REL', 'execute')")" = f ] || { echo "v2 is executable by anon or authenticated"; exit 1; }
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
grep -qF "$NEXT: already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/2"; same "$W/1" "$W/2" fn api set int
echo "PASS migration: the picker goes from the production md5 to the recorded after md5; v2 is added (read only, comment, no grant to anon or authenticated); no other definition, setting or intake changed; the consumer API ($(wc -l < "$W/2.api") functions) is identical; applied again: a no-op"

OUT=$("${P[@]}" -d $DB -f $F/cases-after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-after'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'

snap "$W/pre"
"${P[@]}" -d $DB -At -1 -f $R >/dev/null || { echo "the forward recovery failed"; exit 1; }
[ "$(body $DB "$NEXT")" = $NEXT_BEFORE ] || { echo "the recovery did not restore the picker byte for byte"; exit 1; }
snap "$W/rec"; same "$W/pre" "$W/rec" api set int
OUT=$("${P[@]}" -d $DB -At -1 -f $R 2>&1) || { echo "the forward recovery is not repeatable"; exit 1; }
grep -qF ": nothing to restore" <<<"$OUT" || { echo "the second recovery was not a no-op"; exit 1; }
OUT=$("${P[@]}" -d $DB -At -1 -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(body $DB "$NEXT")" = $NEXT_AFTER ] || { echo "after the recovery the migration did not apply"; exit 1; }
echo 'PASS recovery: the forward recovery returns the picker to the production md5 byte for byte (settings, intakes and the consumer API untouched; v2 stays, unused); repeatable; the migration applies again afterwards'
echo "md5 $NEXT $NEXT_AFTER"; echo "md5 $REL $REL_AFTER"
echo 'calendar-reread-all-providers: done'
