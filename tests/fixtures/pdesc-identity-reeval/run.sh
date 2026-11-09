#!/usr/bin/env bash
# Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): migration 20261109185000 (stacked on 20261109182000) edits only the two live definitions it records (checked by the md5 of the function body, the same text on PostgreSQL 16 and 17, and it refuses and changes nothing when a live function differs),
# keeps the running reader as one stored row (two triggers on the reads) and offers a held identity read made by another reader than the one running to the current reader once more, in the picker and in the lease (same stored page), without touching the evidence signature, keeps every other hold parked, keeps every later check (manual lock, identity findings, recovery knowledge by signature, budget),
# adds one setting (the identity rules, default the three identity rules) and changes no other setting, ceiling, job, Layer 4 item, read or description by itself.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the database with the pdesc-claim-context harness (which builds on pdesc-machine and applies 20261109020000, 20261109030000 and 20261109120000), applies 20261109182000 and then the migration twice, runs the scenarios. PDIR_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${PDIR_DB:-g_pdesc_idreeval}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
MIG=supabase/migrations/20261109185000_cf247_pdesc_identity_reeval.sql
PRE=supabase/migrations/20261109182000_cf247_pdesc_lease_one_pass.sql
F=tests/fixtures/pdesc-identity-reeval
q() { psql -X -d "$DB" -Atc "$1"; }
BASE=$(PDCC_KEEP=1 PDCC_DB=$DB bash tests/fixtures/pdesc-claim-context/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the base harness failed"; exit 1; }
echo "base: pdesc-claim-context harness built the database (20261109020000, 20261109030000 and 20261109120000 applied)"
# the prerequisite: the lease as 20261109182000 leaves it (this change edits that text); a clone without it is kept to show the refusal
dropdb --if-exists ${DB}_pre >/dev/null 2>&1; createdb -T $DB ${DB}_pre
$P -1 -At -f $PRE >/dev/null || { echo "the prerequisite migration failed"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = 'public.svc_provider_description_next(integer)'::regprocedure")" = 2783d0a82e9f472b38b179c07add38ac ] || { echo "the lease after 20261109182000 is not the recorded one"; exit 1; }
echo "prerequisite: 20261109182000 applied (lease body md5 2783d0a82e9f472b38b179c07add38ac)"
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${PDIR_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; dropdb --if-exists '${DB}_pre' >/dev/null 2>&1; }' EXIT

# the edited functions are the live ones (md5 of the function body, pg_proc.prosrc, read 9 Nov 2026, project fxcwkweaxjtknorudmwp)
declare -A LIVE=( ['security.provider_description_selection_v1(jsonb)']=c8dd7882a5a6c5b174a829972d475d40 ['public.svc_provider_description_next(integer)']=2783d0a82e9f472b38b179c07add38ac )
SIG0=$(q "select md5(pg_get_functiondef('security.provider_description_signature_v1(text,text,text)'::regprocedure))") # the evidence signature is read, not edited
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the picker = live and the lease = live after 20261109182000 (body md5 recorded in the migration header)"

# before: a held identity read of an earlier reader on the same stored page is parked, as live
BEFORE=$(psql -X -d "$DB" -Atq <<'SQL'
begin;
update pipeline.platform_toolset_settings set value = (select jsonb_agg(stable_key) from catalogue.providers where stable_key like 'fixture:provider:%') where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
delete from pipeline.provider_description_reads where provider_id in (select id from catalogue.providers where stable_key = 'fixture:provider:2');
insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries, checks)
select p.id, 'held', 'provider_name_conflict', coalesce(a.content_hash, a.id::text), 'https://p2.example.edu/about', now() - interval '2 days', now() - interval '2 days', 1, '{"identity":{"reader_behavior_version":"provider-description-source-guard-v1"}}'::jsonb
  from catalogue.providers p join pipeline.evidence_artifacts a on a.id = security.provider_description_stored_v1(p.id) where p.stable_key = 'fixture:provider:2';
select x->>'eligibility_reason' from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 1, 'mode', 'stored', 'provider_id', (select id from catalogue.providers where stable_key = 'fixture:provider:2')))->'providers') x;
rollback;
SQL
)
[ "$BEFORE" = "unchanged_unsuitable_evidence" ] || { echo "before the change the identity hold was expected to be parked: $BEFORE"; exit 1; }
echo "before: a held provider_name_conflict read on the same stored page is parked (unchanged_unsuitable_evidence), as live"
# before: the lease does not hand out a provider whose earlier read was held on an identity rule when the recovery knowledge holds that failure, as live
BEFORE_L=$(psql -X -d "$DB" -Atq <<'SQL'
begin;
update pipeline.platform_toolset_settings set value = (select jsonb_agg(stable_key) from catalogue.providers where stable_key like 'fixture:provider:%') where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
update pipeline.platform_toolset_settings set value = '8'::jsonb where toolset_key = 'pipeline' and key = 'batch.provider_description';
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.machine_admit_on';
do $$ declare v_p uuid := (select id from catalogue.providers where stable_key = 'fixture:provider:2'); v_h text := (select coalesce(a.content_hash, a.id::text) from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1((select id from catalogue.providers where stable_key = 'fixture:provider:2')));
begin
  delete from pipeline.provider_description_reads where provider_id = v_p;
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries, checks)
    values (v_p, 'held', 'provider_name_conflict', v_h, 'https://p2.example.edu/about', now() - interval '2 days', now() - interval '2 days', 1, '{"identity":{"reader_behavior_version":"provider-description-source-guard-v1"}}'::jsonb);
  perform security.ops_learning_record_v1(jsonb_build_object('code', 'provider_description:official_about', 'entity', v_p::text, 'evidence_signature', security.provider_description_signature_v1(v_h, (select model_identifier from pipeline.central_ai_settings where id = 1), 'provider-description-v2'),
    'performed_by', 'platform', 'success', false, 'stage_advanced', false, 'cost_usd', 0, 'expected', 'fixture', 'observed', '{}'::jsonb, 'evidence', '{}'::jsonb));
  insert into pipeline.provider_description_reads(provider_id, state, next_try_at) values (v_p, 'queued', now() - interval '1 hour');
end $$;
select coalesce(string_agg(e->>'provider_id', ','), '(none)') from jsonb_array_elements(coalesce(public.svc_provider_description_lease_v1(10, null, 'provider-description-reserve-v1')->'items', '[]'::jsonb)) e;
rollback;
SQL
)
[ "$BEFORE_L" = "(none)" ] || { echo "before the change the lease was expected to hand out nothing for the identity hold with a recorded failure: $BEFORE_L"; exit 1; }
echo "before: the lease does not hand out a provider whose identity hold of an earlier reader has a recorded failure for its signature (recovery knowledge), as live"

FNS="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.provider_description_reads" > "$1.rd"; q "select count(*) from catalogue.providers where nullif(btrim(description), '') is not null" > "$1.desc"; q "select count(*) from pipeline.provider_description_machine_admissions" > "$1.adm"; (q "select count(*) from cron.job" 2>/dev/null || echo none) > "$1.cron"; }

# a live function that differs from the recorded one: the migration raises, and nothing at all is applied (the whole migration is one transaction)
RF=${DB}_refuse
dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('security.provider_description_selection_v1(jsonb)'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$" >/dev/null
rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.pdesc_reader_behaviour_v1()') is null") )
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied over a changed live function"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum; psql -X -d $RF -Atc "$SET" | sort | md5sum; psql -X -d $RF -Atc "select to_regprocedure('security.pdesc_reader_behaviour_v1()') is null") )
[ "$rb" = "$ra" ] || { echo "the refused migration changed something"; exit 1; }
dropdb --if-exists $RF >/dev/null 2>&1
# the prerequisite not applied: refused, nothing applied
OUT=$(psql -X -d ${DB}_pre -q -At -v ON_ERROR_STOP=1 -1 -f $MIG 2>&1) && { echo "the migration applied without 20261109182000"; exit 1; }
grep -qF "apply 20261109182000 first" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d ${DB}_pre -Atc "select to_regclass('pipeline.pdesc_reader_state') is null")" = t ] || { echo "the refused migration created the reader state"; exit 1; }
echo "refused: without 20261109182000 the migration is refused ('apply 20261109182000 first') and nothing is applied"
echo "refused: a hand-changed live picker is refused ('differs from the definition this change edits') and nothing is applied (no function, setting, table or new function)"

# apply: the two edited functions go from the recorded live md5 to the recorded after md5; one function and one setting are added; nothing else changes; a second run is a no-op
snap "$W/0"
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do
  grep -qF "$sig: applied" <<<"$OUT" || { echo "$sig was not edited"; echo "$OUT" | tail -8; exit 1; }
  after=$(grep -F -- "--   $sig " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/')
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "$after" ] || { echo "$sig after the change differs from the recorded $after"; exit 1; }
done
snap "$W/1"
want=$(for sig in "${!LIVE[@]}"; do echo "${sig#public.}"; done | sort) # regprocedure prints a public function without its schema
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$want" ] || { echo "the changed functions differ from the edited ones"; diff <(echo "$want") <(echo "$changed"); exit 1; }
added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort | comm -23 - <(echo "$want"))
[ "$added" = "$(printf '%s\n' 'security.pdesc_reader_behaviour_v1()' 'security.pdesc_reader_stamp_v1()')" ] || { echo "the added functions are not just the reader behaviour and its stamp trigger: $added"; exit 1; }
[ "$(q "select md5(pg_get_functiondef('security.provider_description_signature_v1(text,text,text)'::regprocedure))")" = "$SIG0" ] || { echo "the evidence signature changed"; exit 1; }
lost=$(comm -23 "$W/0.set" "$W/1.set" || true)
[ -z "$lost" ] || { echo "the migration changed setting values: $lost"; exit 1; }
newset=$(comm -13 "$W/0.set" "$W/1.set")
[ "$newset" = 'pdesc.identity_reeval_rules=["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]' ] || { echo "the only new setting should be pdesc.identity_reeval_rules: $newset"; exit 1; }
for f in l4 rd desc adm cron; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
[ "$(q "select count(*) from pg_trigger where tgrelid = 'pipeline.provider_description_reads'::regclass and tgname in ('pdesc_reader_stamp_ins', 'pdesc_reader_stamp_upd') and not tgisinternal")" = 2 ] || { echo "the two reader triggers are missing"; exit 1; }
[ "$(q "select count(*) from pipeline.pdesc_reader_state")" -le 1 ] || { echo "the reader state is not a single row"; exit 1; }
[ "$(q "select count(*) from pg_indexes where indexname = 'provider_description_reads_reader_version_idx'")" = 0 ] || { echo "the old reader scan index was created"; exit 1; }
OUT=$($P -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for sig in "${!LIVE[@]}"; do grep -qF "$sig: already applied" <<<"$OUT" || { echo "the second run was not a no-op for $sig"; exit 1; }; done
snap "$W/2"; for f in fn set l4 rd desc adm cron; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: 2 edit(s) from the recorded live md5 to the recorded after md5; the evidence signature unchanged; 2 functions, 1 table with 2 triggers and 1 setting (pdesc.identity_reeval_rules) added, no value changed; no Layer 4 item, read, admission, description or job changed; applied again: no change"
[ -n "$(q "select obj_description('security.pdesc_reader_behaviour_v1()'::regprocedure, 'pg_proc')")" ] && [ -n "$(q "select obj_description('security.pdesc_reader_stamp_v1()'::regprocedure, 'pg_proc')")" ] && [ -n "$(q "select obj_description('pipeline.pdesc_reader_state'::regclass, 'pg_class')")" ] || { echo "a new function or the new table has no comment"; exit 1; }

OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the scenarios failed"; psql -X -d "$DB" -v ON_ERROR_STOP=1 -f $F/scenarios.sql 2>&1 | tail -8; exit 1; }
if [ "$OUT" != "$(cat $F/expected.txt)" ]; then echo "the scenarios differ from $F/expected.txt:"; diff <(cat $F/expected.txt) <(echo "$OUT"); exit 1; fi
echo "scenarios: $(echo "$OUT" | wc -l) results match $F/expected.txt"

# the earlier scenarios (held reads retried on a changed copy, machine admission, claim-word context) still give the same result with the migration applied
for S in pdesc-machine pdesc-claim-context; do
  OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/$S/scenarios.sql 2>&1 | grep -E '^[a-z0-9_]+\|') || { echo "the earlier $S scenarios failed"; exit 1; }
  if [ "$OUT" != "$(cat tests/fixtures/$S/expected.txt)" ]; then echo "the earlier $S scenarios differ after the migration:"; diff <(cat tests/fixtures/$S/expected.txt) <(echo "$OUT"); exit 1; fi
  echo "earlier: the $(echo "$OUT" | wc -l) $S scenarios give the same result after the migration"
done
OUT=$(psql -X -d "$DB" -v ON_ERROR_STOP=1 -f tests/fixtures/pdesc-retry-funnel/scenarios.sql 2>&1 | grep -E '\|') || { echo "the retry-funnel scenarios failed"; exit 1; }
echo "$OUT" | grep -q 'held_same_copy|unchanged_unsuitable_evidence' && echo "$OUT" | grep -q 'held_new_copy|eligible' || { echo "the retry-funnel behaviour changed: $OUT"; exit 1; }
echo "earlier: a held read on the same copy stays parked and one on a changed copy is retried (pdesc-retry-funnel)"
echo "pdesc-identity-reeval: done"
