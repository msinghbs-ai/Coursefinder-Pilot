#!/usr/bin/env bash
# Guards: F-PDESC (Platform Admin decision 9 Nov 2026, all-provider autonomous description delivery): migrations 20261109020000 and 20261109030000 edit only the live definitions they record (checked by the md5 of the function
# body, the same text on PostgreSQL 16 and 17, and they refuse and change nothing when a live function differs), add the machine admission path and the whole-platform queue behind default-off settings, change nothing else,
# behave as the scenarios say against production-shaped constraints and triggers, and stay inside the statement time-outs at the live catalogue size (3,103 providers, 766 stored pages). Consumer API objects are only called, never changed.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-self-driving harness (which builds on the retry-funnel and autonomy harnesses and applies
# 20261108140000 and 20261109010000), adds the production-shaped columns, constraints, trigger and the live admin_toolsets_write definition, then applies the two migrations, each twice. Drops the databases at the end (PDM_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDM_DB:-g_pdesc_machine}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M2=supabase/migrations/20261109020000_cf247_pdesc_machine_admission.sql
M3=supabase/migrations/20261109030000_cf247_pdesc_whole_platform_queue.sql
F=tests/fixtures/pdesc-machine
q() { psql -X -d "$DB" -Atc "$1"; }
[ -n "${PDM_KEEP:-}" ] || trap 'dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; dropdb --if-exists '${DB}_scale' >/dev/null 2>&1' EXIT
BASE=$(PDSD_KEEP=1 PDSD_DB=$DB bash tests/fixtures/pdesc-self-driving/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-self-driving harness built the database (20261108140000 and 20261109010000 applied)"
$P -f $F/schema.sql >/dev/null
$P -f $F/live/public.admin_toolsets_write.sql >/dev/null
[ "$(q "select md5(pg_get_functiondef('public.admin_toolsets_write(text,jsonb)'::regprocedure))")" = 1e511b25277897b870d185c2ea727ae0 ] || { echo "the loaded admin_toolsets_write differs from live"; exit 1; }
echo "loaded: production-shaped columns; admin_toolsets_write = live (definition 1e511b25277897b870d185c2ea727ae0, body 50aaa7aeb76353c3f8d02cef552462ed)"
# the constraints and trigger production has on the tables the withdrawal and admission write (read 9 Nov 2026): one refresh signal for each decision, the decision and status lists, the manual-lock guard
[ "$(q "select count(*) from pg_constraint where conname in ('search_refresh_signals_review_decision_id_key', 'search_refresh_signals_review_decision_id_fkey', 'search_refresh_signals_status_check', 'layer4_decisions_action_check', 'layer4_review_items_status_check', 'provider_description_reads_state_check', 'provider_description_reads_read_via_check', 'provider_description_reads_review_item_id_fkey')")" = 8 ] || { echo "the harness is missing a production constraint"; exit 1; }
[ "$(q "select count(*) from pg_trigger where tgname = 'manual_lock_guard' and tgrelid = 'catalogue.providers'::regclass")" = 1 ] || { echo "the harness is missing the manual lock guard"; exit 1; }
echo "production shape: UNIQUE review_decision_id, FK and status check on search_refresh_signals; action, status, state and read_via checks; the manual lock guard on providers"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from catalogue.providers where nullif(btrim(description), '') is not null" > "$1.desc"; (q "select count(*) from cron.job" 2>/dev/null || echo none) > "$1.cron"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDM_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT

# apply one migration: the edited functions are the live ones before (body md5), at their recorded body md5 after; nothing else changes; a second run is a no-op
apply() { # $1 migration, $2 label, then pairs "signature=before_md5" for the edited functions
  local mig=$1 label=$2; shift 2
  local sig before after
  for e in "$@"; do sig=${e%%=*}; before=${e##*=}
    [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$before" ] || { echo "$label: $sig before the change differs from the recorded $before"; exit 1; }
  done
  snap "$W/$label.0"
  OUT=$($P -1 -At -f $mig 2>&1) || { echo "$OUT" | tail -8; exit 1; }
  for e in "$@"; do sig=${e%%=*}
    grep -qF "$sig: applied" <<<"$OUT" || { echo "$label: $sig was not edited"; echo "$OUT" | tail -8; exit 1; }
    after=$(grep -F -- "--   $sig " $mig | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
    [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$after" ] || { echo "$label: $sig after the change differs from the recorded $after"; exit 1; }
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
# a live function that differs from the recorded one: the migration raises, and nothing at all is applied (the whole migration is one transaction)
refuse() { # $1 migration, $2 label, $3 signature to change by hand
  local RF=${DB}_refuse before after
  dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$3'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$" >/dev/null
  before=$(psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regclass('pipeline.provider_description_machine_admissions') is null, to_regclass('pipeline.provider_description_scan_marks') is null")
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $1 2>&1) && { echo "$2: the migration applied over a changed live function"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "$2: the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  after=$(psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regclass('pipeline.provider_description_machine_admissions') is null, to_regclass('pipeline.provider_description_scan_marks') is null")
  [ "$before" = "$after" ] || { echo "$2: the refused migration changed something"; exit 1; }
  dropdb --if-exists $RF >/dev/null 2>&1
  echo "$2: a hand-changed live $3 is refused ('differs from the definition this change edits') and nothing is applied"
}
refuse $M2 M2 'public.admin_provider_description_funnel_v1()'
apply $M2 M2 'security.provider_description_scope_v1(uuid)=71075d22096ac3f28306aa7544a04ad0' 'public.admin_provider_description_funnel_v1()=0db4ef39b72f23454a668b6c9a2d37d9' 'public.admin_toolsets_write(text,jsonb)=50aaa7aeb76353c3f8d02cef552462ed'
[ "$(q "select string_agg(key || '=' || value::text, ',' order by key) from pipeline.platform_toolset_settings where key in ('pdesc.machine_admit_on','pdesc.registry_factual_on','pdesc.machine_numbers_allowed')")" = 'pdesc.machine_admit_on=0,pdesc.machine_numbers_allowed=0,pdesc.registry_factual_on=0' ] || { echo "the switches are not off after M2"; exit 1; }
echo "M2: pdesc.machine_admit_on, pdesc.registry_factual_on and pdesc.machine_numbers_allowed are 0"
refuse $M3 M3 'public.svc_provider_description_next(integer)'
apply $M3 M3 'security.provider_description_selection_v1(jsonb)=1fa6c1c9fa9200eb644fcabf8c85dcf0' 'security.provider_description_enqueue_v1()=c25746895368b9320a1e5fc4222b14d1' 'public.svc_provider_description_next(integer)=3d6eb1eb35b80f54c72eb160c63aac82' 'public.svc_provider_description_record(jsonb)=1b7fec4fb287277e31fa4fbcc2a101ef' 'security.provider_description_fire_v1()=92e445408c50883e301088b9ba0d8b9c'

# the earlier harness still holds with the machine switch off
AFTERS=$($P -At < tests/fixtures/pdesc-self-driving/scenarios.sql | grep .)
grep -qx 'enqueued|lost_admitted,lost_verified,lost_past_recheck' <<<"$AFTERS" || { echo "the self-driving scenarios changed with the switch off"; echo "$AFTERS"; exit 1; }
echo "off: the earlier self-driving scenarios give the same result after both migrations"

OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the scenarios failed"; exit 1; }
if [ "$OUT" != "$(cat $F/expected.txt)" ]; then echo "the scenarios differ from $F/expected.txt:"; diff <(cat $F/expected.txt) <(echo "$OUT"); exit 1; fi
echo "scenarios: $(echo "$OUT" | wc -l) results match $F/expected.txt"

# performance at the live catalogue size (QA B2): 3,103 providers, 766 stored About pages, all three countries, automatic admission on. The budgets are seconds on this scratch database, against the live limits: 8 s for a screen (authenticated) and 120 s for a job (server).
# The budgets allow for the CI runner, which measured about twice as slow as the development machine (first CI run: funnel 1.29 s against 0.66 s); the earlier unbounded evaluation took 10 to 12 s here, so any return of the O(N) work fails them.
# Calibration (read only on the live project, 9 Nov 2026): the live database is NOT faster than this one. scope_v1 over all 3,103 providers took 0.25 s here and 1.4 s on live at a quiet moment and 7.4 s on live straight after (a busy moment), so the live cost of a per-provider check varies 5 to 30 times with load. The budgets are therefore set well under the limits and the number of per-provider calls (stored page, identity, scope) is bounded below as well: the call counts, not the seconds, are what carry over to live.
SC=${DB}_scale
dropdb --if-exists $SC >/dev/null 2>&1; createdb -T $DB $SC
psql -X -q -d $SC -v ON_ERROR_STOP=1 -f $F/scale.sql >/dev/null
PERF=$(psql -X -d $SC -f $F/scale-measure.sql 2>&1 | grep -E '^(time|calls)\|') || { echo "the scale measurement failed"; exit 1; }
echo "$PERF" | grep '^time|' | sed 's/^time|//; s/|/  /g' | awk -F'  ' '{printf "  %-62s %6.2f s  %s\n", $1, $2, $3}'
secs() { echo "$PERF" | grep -F "time|$1|" | head -1 | cut -d'|' -f3; }
calls() { echo "$PERF" | grep -F "calls|$1|$2|" | head -1 | cut -d'|' -f4; }
within() { # $1 step, $2 budget seconds
  local v; v=$(secs "$1"); [ -n "$v" ] || { echo "no timing for $1"; exit 1; }
  awk -v v="$v" -v b="$2" 'BEGIN { exit !(v + 0 <= b + 0) }' || { echo "scale: $1 took $v s, over the budget of $2 s"; exit 1; }
}
within 'selection_v1 default list, size 60' 3.5
within 'throughput_v1' 2.0
within 'funnel (rank 6 caller, 3,000 in scope)' 3.0
within 'enqueue_v1, stored mode, run 1' 3.5
within 'enqueue_v1, stored mode, run 2' 3.0
within 'enqueue_v1, stored mode, run 3' 3.5
within 'enqueue_v1, direct mode' 3.5
within 'lease: svc_provider_description_next' 2.5
within 'registry tier run' 8.0
within 'machine report' 2.5
within 'fire_v1 (whole run)' 12.0
# bounded work: the page and identity checks run for a slice, not for the 766 providers with a stored page or the 3,000 in scope
[ "$(calls 'enqueue_v1, stored mode, run 1' provider_description_stored_v1)" -le 200 ] || { echo "scale: enqueue ran the stored page check for too many providers"; exit 1; }
[ "$(calls 'funnel (rank 6 caller, 3,000 in scope)' provider_description_stored_v1)" -le 60 ] || { echo "scale: the funnel ran the stored page check for too many providers"; exit 1; }
[ "$(calls 'funnel (rank 6 caller, 3,000 in scope)' provider_description_identity_v1)" -le 240 ] || { echo "scale: the funnel ran the identity check for too many providers"; exit 1; }
[ "$(calls 'selection_v1 default list, size 60' provider_description_stored_v1)" -le 200 ] || { echo "scale: the default list ran the stored page check for too many providers"; exit 1; }
[ "$(calls 'enqueue_v1, stored mode, run 1' provider_description_scope_v1)" -le 5000 ] || { echo "scale: enqueue ran the scope check for too many providers"; exit 1; }
[ "$(calls 'funnel (rank 6 caller, 3,000 in scope)' provider_description_scope_v1)" -le 1200 ] || { echo "scale: the funnel ran the scope check for too many providers"; exit 1; }
[ "$(calls 'selection_v1 default list, size 60' provider_description_scope_v1)" -le 1200 ] || { echo "scale: the default list ran the scope check for too many providers"; exit 1; }
# rotation: the third run reaches providers not looked at before, and queues new ones
A=$(echo "$PERF" | grep -F 'time|distinct providers looked at|' | cut -d'|' -f4); B=$(echo "$PERF" | grep -F 'time|distinct providers looked at after run 3|' | cut -d'|' -f4); N=$(echo "$PERF" | grep -F 'time|queued after run 3 that were not queued before|' | cut -d'|' -f4)
[ "$B" -gt "$A" ] && [ "$N" -gt 0 ] || { echo "scale: the rotation did not reach new providers ($A, $B, $N)"; exit 1; }
echo "scale: every step within its budget; checks run for a slice (stored page $(calls 'enqueue_v1, stored mode, run 1' provider_description_stored_v1) of 766 in an enqueue, $(calls 'funnel (rank 6 caller, 3,000 in scope)' provider_description_stored_v1) in the funnel); the rotation reached new providers ($A to $B looked at)"
echo "pdesc-machine: done"
