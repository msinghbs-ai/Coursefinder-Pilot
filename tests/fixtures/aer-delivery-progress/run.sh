#!/usr/bin/env bash
# Guards: F-AER.04 delivery reported through the existing Data Delivery screen (Platform Admin decision delivery item 6, 11 Nov 2026) and G4 database-backed tests: migration
# 20261112133700 gives the Data Delivery AER panel its stage 4 (discovery campaign, machine admission, corrected reads, gains in 24 hours, failures) from one read-only function,
# Curator and above, counting only what the tables hold (24-hour windows, withdrawn admissions left out); idempotent; edits no existing function.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (ADP_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ADP_DB:-g_aer_delivery_progress}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/aer-delivery-progress; M=supabase/migrations/20261112133700_cf247_aer_delivery_progress.sql
q() { psql -X -d "$DB" -Atc "$1"; }
trap '[ -n "${ADP_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; end \$\$"
grep -v '^create role' $F/stubs.sql | $P
$P <<'SQL'
insert into pipeline.platform_toolset_settings values ('pipeline', 'aer.machine_mode', '2'), ('pipeline', 'aer.matrix_machine_mode', '1'), ('pipeline', 'aer.discovery_campaign_credit_cap', '10000');
insert into pipeline.aer_discovery_campaigns(state) values ('running');
insert into pipeline.aer_machine_admissions(provider_id, mode, outcome, withdrawn_at, created_at) values
 (gen_random_uuid(), 'admit', 'admitted', null, now() - interval '2 hours'), (gen_random_uuid(), 'admit', 'admitted', null, now() - interval '3 days'),
 (gen_random_uuid(), 'admit', 'admitted', now(), now() - interval '1 hour'), (gen_random_uuid(), 'shadow', 'would_admit', null, now());
insert into pipeline.aer_matrix_machine_admissions(provider_id, mode, outcome, reason, created_at) values
 ('a0000000-0000-0000-0000-00000000000a', 'admit', 'admitted', null, now()), ('a0000000-0000-0000-0000-00000000000a', 'admit', 'admitted', null, now()),
 ('b0000000-0000-0000-0000-00000000000b', 'admit', 'admitted', null, now() - interval '2 days'),
 (gen_random_uuid(), 'shadow', 'would_admit', null, now()), (gen_random_uuid(), 'shadow', 'declined', 'The read cannot be shown complete (D-R3).', now()),
 (gen_random_uuid(), 'shadow', 'declined', 'The read cannot be shown complete (D-R3).', now()), (gen_random_uuid(), 'shadow', 'declined', 'old', now() - interval '3 days');
insert into pipeline.aer_matrix_machine_validations(passed, validated_at) values (false, now() - interval '1 hour'), (true, now());
insert into pipeline.aer_read_supersessions(state, closed_at) values ('requested', null), ('refused', now()), ('refused', now() - interval '3 days'), ('superseded', now());
insert into catalogue.course_entry_requirements(status, updated_at) values ('active', now()), ('active', now() - interval '3 days'), ('proposed', now());
insert into catalogue.provider_entry_matrix(provider_id, status) values ('a0000000-0000-0000-0000-00000000000a', 'active'), ('a0000000-0000-0000-0000-00000000000a', 'active'), ('b0000000-0000-0000-0000-00000000000b', 'proposed');
insert into catalogue.provider_qualification_requirements(provider_id, status) values ('a0000000-0000-0000-0000-00000000000a', 'active');
insert into pipeline.entry_matrix_sources(status, error) values ('failed', 'blocked_pdf'), ('failed', 'blocked_pdf'), ('robots_disallowed', null), ('read', null);
insert into pipeline.entry_matrix_runs(state) values ('failed'), ('done');
SQL
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(p.prosrc), ',' order by 1)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public') and p.proname not in ('data_delivery_aer_progress_v1', 'admin_aer_delivery_progress')"
F0=$(q "$FNS")
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
OUT=$($P -1 -At -f $M 2>&1) || { echo "applied again: $OUT" | tail -8; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "an existing function was changed"; exit 1; }
echo "migration: two read-only functions added, no existing function changed; applied again: no change"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare p jsonb := public.admin_aer_delivery_progress(); e text; begin
  perform pg_temp.ok((p->'campaign'->>'providers_attempted')::int = 105 and (p->'campaign'->>'spare_room')::int = 946 and p->'campaign'->>'state' = 'running' and not (p->'campaign' ? 'spare'), 'campaign figures from the metrics read');
  perform pg_temp.ok((p->'machine'->'course'->>'admitted')::int = 2 and (p->'machine'->'course'->>'admitted_24h')::int = 1 and (p->'machine'->'course'->>'mode')::int = 2, 'course admissions: withdrawn left out; 24 hours');
  perform pg_temp.ok((p->'machine'->'matrix'->>'admitted')::int = 3 and (p->'machine'->'matrix'->>'admitted_24h')::int = 2 and (p->'machine'->'matrix'->>'providers')::int = 2
                     and (p->'machine'->'matrix'->>'shadow')::int = 4 and (p->'machine'->'matrix'->>'shadow_would_admit')::int = 1, 'matrix admissions, providers and shadow');
  perform pg_temp.ok((p->'machine'->'matrix'->'validation'->>'passed')::boolean and p->'machine'->'matrix'->'declines'->0->>'reason' = 'The read cannot be shown complete (D-R3).'
                     and (p->'machine'->'matrix'->'declines'->0->>'n')::int = 2 and jsonb_array_length(p->'machine'->'matrix'->'declines') = 1, 'latest validation; declines of the last 24 hours by reason');
  perform pg_temp.ok((p->'corrected_reads'->>'open')::int = 1 and (p->'corrected_reads'->>'refused_24h')::int = 1 and (p->'corrected_reads'->>'replaced_24h')::int = 1, 'corrected reads');
  perform pg_temp.ok((p->'gains_24h'->>'course_rows')::int = 1 and (p->'gains_24h'->>'matrix_rows')::int = 2 and (p->'gains_24h'->>'qualification_rows')::int = 1 and (p->'gains_24h'->>'providers_with_new_matrix')::int = 1, 'gains in 24 hours');
  perform pg_temp.ok((p->'failures'->>'sources_not_fetched')::int = 3 and (p->'failures'->'sources_blocked'->>'blocked_pdf')::int = 2 and (p->'failures'->>'reads_held_unreadable')::int = 1, 'failures');
  perform pg_temp.ok(p ? 'counted_at', 'stamped');
  update pipeline.fx_caller set rank = 2;
  begin perform public.admin_aer_delivery_progress(); e := null; exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e = 'Curator role or above required', 'below Curator: refused (the screen''s rank)');
end $$;
SQL
echo "behaviour: campaign, admissions (withdrawn left out), shadow and validation, declines, corrected reads, gains, failures; the screen's rank"
echo "PASS aer-delivery-progress"
