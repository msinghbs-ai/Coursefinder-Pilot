#!/usr/bin/env bash
# Guards: F-PDESC (Platform Admin decision 9 Nov 2026, all-provider autonomous description delivery): migrations 20261109020000 and 20261109030000 edit only the live definitions they record, add the machine admission
# path and the whole-platform queue behind default-off settings, change nothing else, and behave as the scenarios say. Consumer API objects are only called, never changed.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-self-driving harness (which builds on the retry-funnel and autonomy harnesses and applies
# 20261108140000 and 20261109010000), adds the production-shaped columns and the live admin_toolsets_write definition, then applies the two migrations, each twice. Drops the database at the end (PDM_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${PDM_DB:-g_pdesc_machine}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M2=supabase/migrations/20261109020000_cf247_pdesc_machine_admission.sql
M3=supabase/migrations/20261109030000_cf247_pdesc_whole_platform_queue.sql
F=tests/fixtures/pdesc-machine
q() { psql -X -d "$DB" -Atc "$1"; }
[ -n "${PDM_KEEP:-}" ] || trap 'dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
BASE=$(PDSD_KEEP=1 PDSD_DB=$DB bash tests/fixtures/pdesc-self-driving/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-self-driving harness built the database (20261108140000 and 20261109010000 applied)"
$P -f $F/schema.sql >/dev/null
$P -f $F/live/public.admin_toolsets_write.sql >/dev/null
[ "$(q "select md5(pg_get_functiondef('public.admin_toolsets_write(text,jsonb)'::regprocedure))")" = 1e511b25277897b870d185c2ea727ae0 ] || { echo "the loaded admin_toolsets_write differs from live"; exit 1; }
echo "loaded: production-shaped columns; admin_toolsets_write = live 1e511b25277897b870d185c2ea727ae0"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" > "$1.fn"; q "$SET" > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from catalogue.providers where nullif(btrim(description), '') is not null" > "$1.desc"; (q "select count(*) from cron.job" 2>/dev/null || echo none) > "$1.cron"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDM_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT

# apply one migration: the edited functions are the live ones before, at their recorded md5 after; nothing else changes; a second run is a no-op
apply() { # $1 migration, $2 label, then pairs "signature=before_md5" for the edited functions
  local mig=$1 label=$2; shift 2
  local sig before after
  for e in "$@"; do sig=${e%%=*}; before=${e##*=}
    [ "$(q "select md5(pg_get_functiondef('$sig'::regprocedure))")" = "$before" ] || { echo "$label: $sig before the change differs from the recorded $before"; exit 1; }
  done
  snap "$W/$label.0"
  OUT=$($P -1 -At -f $mig 2>&1) || { echo "$OUT" | tail -8; exit 1; }
  for e in "$@"; do sig=${e%%=*}
    grep -qF "$sig: applied" <<<"$OUT" || { echo "$label: $sig was not edited"; echo "$OUT" | tail -8; exit 1; }
    after=$(grep -F -- "--   $sig " $mig | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
    [ "$(q "select md5(pg_get_functiondef('$sig'::regprocedure))")" = "$after" ] || { echo "$label: $sig after the change differs from the recorded $after"; exit 1; }
  done
  snap "$W/$label.1"
  # functions: only the edited ones changed; the added ones are exactly those the migration creates
  local edited="" ; for e in "$@"; do edited="$edited|${e%%=*}"; done
  local changed; changed=$(comm -23 "$W/$label.0.fn" "$W/$label.1.fn" | sed 's/ [0-9a-f]*$//' | sort)
  local want; want=$(for e in "$@"; do echo "${e%%=*}"; done | sed 's/^public\.//' | sort) # fixed: regprocedure prints public functions without the schema
  [ "$changed" = "$want" ] || { echo "$label: the changed functions differ from the edited ones"; diff <(echo "$want") <(echo "$changed"); exit 1; }
  local added; added=$(comm -13 "$W/$label.0.fn" "$W/$label.1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))
  local made; made=$({ grep -oE "^create or replace function (security|public)\.[a-z_0-9]+\(" $mig || true; } | sed 's/create or replace function //; s/($//; s/^public\.//' | sort -u || true) # fixed: a migration that only edits creates none
  local addednames; addednames=$(echo "$added" | sed 's/(.*//' | sort -u)
  [ "$addednames" = "$made" ] || { echo "$label: the added functions differ from those the migration creates"; diff <(echo "$made") <(echo "$addednames"); exit 1; }
  # settings: every earlier value is unchanged; the new ones are listed and the switches are off
  local lost; lost=$(comm -23 "$W/$label.0.set" "$W/$label.1.set" | grep -vE '^pdesc\.(provider_keys|provider_types|countries)=' || true)
  [ -z "$lost" ] || { echo "$label: the migration changed setting values: $lost"; exit 1; }
  for f in l4 rd desc cron; do cmp -s "$W/$label.0.$f" "$W/$label.1.$f" || { echo "$label: the migration changed $f"; exit 1; }; done
  OUT=$($P -1 -At -f $mig 2>&1) || { echo "$OUT" | tail -8; exit 1; }
  for e in "$@"; do sig=${e%%=*}; grep -qF "$sig: already applied" <<<"$OUT" || { echo "$label: the second run was not a no-op for $sig"; exit 1; }; done
  snap "$W/$label.2"; for f in fn set l4 rd desc cron; do cmp -s "$W/$label.1.$f" "$W/$label.2.$f" || { echo "$label: the second run changed $f"; exit 1; }; done
  echo "$label: $# edit(s) from the recorded live md5 to the recorded after md5; $(echo "$addednames" | grep -c .) function(s) added; no other function, setting value, Layer 4 item, read, description or job changed; applied again: no change"
}
apply $M2 M2 'security.provider_description_scope_v1(uuid)=3f16959316449464576f5d77a951460a' 'public.admin_provider_description_funnel_v1()=b8ba600e9d7a67e9c493f062bfda0b99' 'public.admin_toolsets_write(text,jsonb)=1e511b25277897b870d185c2ea727ae0'
[ "$(q "select string_agg(key || '=' || value::text, ',' order by key) from pipeline.platform_toolset_settings where key in ('pdesc.machine_admit_on','pdesc.registry_factual_on','pdesc.machine_numbers_allowed')")" = 'pdesc.machine_admit_on=0,pdesc.machine_numbers_allowed=0,pdesc.registry_factual_on=0' ] || { echo "the switches are not off after M2"; exit 1; }
echo "M2: pdesc.machine_admit_on, pdesc.registry_factual_on and pdesc.machine_numbers_allowed are 0"
apply $M3 M3 'security.provider_description_selection_v1(jsonb)=eaebe3d0a6c188f0b4f6b6c3fcf659ba' 'security.provider_description_enqueue_v1()=0a1897bb7f56697a9f01d4ec3e8befc0' 'public.svc_provider_description_next(integer)=559407dc479753698b858231b2e7eb93' 'public.svc_provider_description_record(jsonb)=d95f0bafc894b662468a309254544444' 'security.provider_description_fire_v1()=b334fbefe8a7fb2b8cfd2feda570a616'

# the earlier harness still holds with the machine switch off
AFTERS=$($P -At < tests/fixtures/pdesc-self-driving/scenarios.sql | grep .)
grep -qx 'enqueued|lost_admitted,lost_verified,lost_past_recheck' <<<"$AFTERS" || { echo "the self-driving scenarios changed with the switch off"; echo "$AFTERS"; exit 1; }
echo "off: the earlier self-driving scenarios give the same result after both migrations"

OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the scenarios failed"; exit 1; }
if [ "$OUT" != "$(cat $F/expected.txt)" ]; then echo "the scenarios differ from $F/expected.txt:"; diff <(cat $F/expected.txt) <(echo "$OUT"); exit 1; fi
echo "scenarios: $(echo "$OUT" | wc -l) results match $F/expected.txt"
echo "pdesc-machine: done"
