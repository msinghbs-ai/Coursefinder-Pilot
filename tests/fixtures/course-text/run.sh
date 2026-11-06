#!/usr/bin/env bash
# CF-247 Workstream C: course description and application deadline on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes); the live definitions in live/ (read with
# pg_get_functiondef on 3 Nov 2026 10:12-10:35 AEDT and re-read 11:26 AEDT; admin_enrich_fields is the v2.15.419 definition), each checked against its live md5; seed.sql (the live register, source rules and page
# proofs this change reads); the 20261103110000 migration unchanged (its md5 guards and after-md5 checks run), then again (already applied,
# nothing added twice); then fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=${COURSETEXT_DB:-course_text_fixtures}
MIG=../../../supabase/migrations/20261103110000_cf247_course_description_deadline_fields.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
# Admin #382: the fixture is destructive only to its local throwaway database.
# Refuse a remote transport or a Supabase role before creating/dropping anything.
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database' >&2; exit 1;; esac
$P -d postgres -c "do \$local\$ begin
  if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1','::1') then raise exception 'local fixture transport required'; end if;
  if exists (select 1 from pg_roles where rolname='supabase_admin') then raise exception 'refusing a Supabase project'; end if;
end \$local\$;"
$P -At -d postgres -c "select 'ISOLATED_POSTGRES version=' || current_setting('server_version') || ' transport=' || coalesce(host(inet_server_addr()),'unix-socket')"

$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${COURSETEXT_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d $DB -f stubs.sql
# live definitions and their live md5 (3 Nov 2026): the eight edited, and the six read against
declare -A LIVE=(
  ["security.enrich_fields_v1()"]=0efc2f55d0f1e285225be7a10a28f4c1
  ["public.svc_enrich_ai_record(jsonb)"]=264ab812e37f4c1877bdafbdb43147b1
  ["security.field_gap_queue_tick_v1()"]=d909e54d6b6de0f8d2893fbb2d8553bd
  ["public.admin_enrich_fields(text,jsonb)"]=349584fc0e9b605e1067cbbd488e435a
  ["security.field_stalled_v1()"]=702dc1da52bd7272c913ad287b7c8b06
  ["security.enrich_coverage_snapshot_v1()"]=1f94cdee31ec466dc0e83e30728c5596
  ["security.layer4_review_decide_impl(uuid,text,text,jsonb)"]=073889b7c5319019b25212ce08705a37
  ["security.layer4_inbox_items_v1()"]=c31b009df674a4a6ff531f00b99a9a45
  ["security.pdesc_has_term_v1(text,text)"]=b2b8d6499c2ad619b68842258ca7e2e3
  ["security.pdesc_support_v1(text,text)"]=adedab4f5da6e6fec8a0d840fea15bde
  ["security.pdesc_similarity_v1(text,text)"]=357a9ebfde1c68a286ad4f685445cf9b
  ["security.coverage_identity_allowed(uuid,text,text)"]=8a46ead4d1582d57010a6e3854d99b94
  ["security.enrich_item_held_v1(uuid,text)"]=688da7aedbb7ee3f09f629b497c25579
  ["security.layer4_adapter_field_v1(text)"]=9fba6997bbe20728fe3c6017d9ff6c77
)
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -c "create trigger field_enrich_items_gate before insert on pipeline.field_enrich_items for each row execute function security.field_enrich_items_gate_v1()" \
          -c "create trigger field_enrich_items_flag after update of state on pipeline.field_enrich_items for each row execute function security.field_enrich_items_flag_v1()"
$P -d $DB -f seed.sql
OUT=$($P -d $DB -1 -At -f $MIG)
[ "$(grep -c ': applied' <<<"$OUT")" = 8 ] || { echo "the migration did not apply all eight guarded edits"; echo "$OUT"; exit 1; }
declare -A AFTER
for s in "security.enrich_fields_v1()" "public.svc_enrich_ai_record(jsonb)" "security.field_gap_queue_tick_v1()" "public.admin_enrich_fields(text,jsonb)" \
         "security.field_stalled_v1()" "security.enrich_coverage_snapshot_v1()" "security.layer4_review_decide_impl(uuid,text,text,jsonb)" "security.layer4_inbox_items_v1()"; do
  AFTER[$s]=$(md5of "$s"); echo "after: $s ${LIVE[$s]} -> ${AFTER[$s]}"
done
SET1=$($P -d $DB -Atc "select md5(string_agg(t::text, '|' order by t::text)) from (select toolset_key, key, value, used_by from pipeline.platform_toolset_settings) t")
REG1=$($P -d $DB -Atc "select md5(string_agg(t::text, '|' order by t::text)) from (select * from pipeline.field_register) t")
OUT2=$($P -d $DB -1 -At -f $MIG)
[ "$(grep -c 'already applied' <<<"$OUT2")" = 8 ] || { echo "a second run changed a guarded function"; echo "$OUT2"; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "second run changed $s"; exit 1; }; done
[ "$SET1" = "$($P -d $DB -Atc "select md5(string_agg(t::text, '|' order by t::text)) from (select toolset_key, key, value, used_by from pipeline.platform_toolset_settings) t")" ] || { echo "second run changed settings"; exit 1; }
[ "$REG1" = "$($P -d $DB -Atc "select md5(string_agg(t::text, '|' order by t::text)) from (select * from pipeline.field_register) t")" ] || { echo "second run changed the register"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pg_trigger where tgname = 'layer4_review_items_course_description'")" = 1 ] || { echo "trigger count"; exit 1; }
echo "second run: nothing changed"
# P0 Admin #382: exercise the actual CLI-created pure guard migration twice on
# the existing admission path. This is isolated fixture execution, not production.
P0=../../../supabase/migrations/20261106450000_cf247_deadline_closing_semantics.sql
$P -d "$DB" -1 -f "$P0"
$P -d "$DB" -1 -f "$P0"

# Exercise the ACTUAL review DO body, enabled only in a temporary local fixture
# copy with a conspicuously synthetic actor/approval. Never alter the source file.
REVIEW=../../../docs/paste/REVIEW-20261106-p0-deadline-three-values.sql
grep -qF 'v_approved boolean := false;' "$REVIEW"
grep -qF 'v_actor uuid := null;' "$REVIEW"
grep -qF 'v_decision text := null;' "$REVIEW"
T_REVIEW=$(mktemp -d)
trap 'rm -rf "$T_REVIEW"; if [ -z "${COURSETEXT_KEEP:-}" ]; then $P -d postgres -c "drop database if exists $DB" >/dev/null; fi' EXIT
{
  echo 'create function pg_temp.review_apply() returns void language plpgsql as $enabled_fixture$ begin execute $actual_review_body$'
  sed -n '/^do \$review_only\$/,/^end \$review_only\$;/p' "$REVIEW" | sed \
    -e 's/v_approved boolean := false;/v_approved boolean := true;/' \
    -e "s/v_actor uuid := null;/v_actor uuid := 'f0000000-0000-4000-8000-000000000001'::uuid;/" \
    -e "s/v_decision text := null;/v_decision text := 'ISOLATED FIXTURE ONLY - NOT A PRODUCTION APPROVAL';/"
  echo '$actual_review_body$; end $enabled_fixture$;'
} > "$T_REVIEW/enabled-review-fixture.sql"
echo 'ISOLATED REVIEW TEST: synthetic approval only; production proposal stays disabled'
$P -d "$DB" -f fixtures.sql -f "$T_REVIEW/enabled-review-fixture.sql" -f review-withdrawal.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'

echo "fixtures: all passed"
