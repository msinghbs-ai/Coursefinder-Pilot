#!/usr/bin/env bash
# Guards: F-AER.04 AER source discovery campaign (Platform Admin 11 Nov 2026 16:24 decisions) and G4 database-backed tests: migration 20261112040000 edits public.svc_fc_spend
# and security.aer_source_discover_v1 only from their live bodies (captured by the read-only Database function snapshot run 42974996927: 39075b66..., f818e6bb...), leaves the
# recorded after md5s, is refused on a changed body, is idempotent, and its campaign step asks every eligible provider without a source within the batch and the ceiling,
# never re-settles a request from evidence older than the request, and is taken back byte for byte by the held forward recovery.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Drops its databases at the end (ADC_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ADC_DB:-g_aer_discovery_campaign}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/aer-discovery-campaign
M=supabase/migrations/20261112040000_cf247_aer_discovery_campaign.sql
R=supabase/held/aer_discovery_campaign_forward_recovery.sql
SP='public.svc_fc_spend(numeric,text,uuid,text)'; DI='security.aer_source_discover_v1(boolean)'
SP_B=39075b66a1d8ff15246b8c82ffa0c590; DI_B=f818e6bb2500c5cc63c361970c73d1e3; SP_A=c9d616fa35a278103121416ce73e0295; DI_A=16e04c3ffe38a38f3b6f23df7bd0e0a1
q() { psql -X -d "$DB" -Atc "$1"; }
md5s() { echo "$(q "select md5(prosrc) from pg_proc where oid = '$SP'::regprocedure") $(q "select md5(prosrc) from pg_proc where oid = '$DI'::regprocedure")"; }
trap '[ -n "${ADC_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; end \$\$"
grep -v '^create role' $F/stubs.sql | $P
for f in public.svc_fc_spend security.aer_source_discover_v1; do { echo "set check_function_bodies = off;"; cat $F/live/$f.sql; echo ";"; } | $P; done
[ "$(md5s)" = "$SP_B $DI_B" ] || { echo "the loaded bodies differ from live ($SP_B $DI_B)"; exit 1; }
echo "loaded: svc_fc_spend and aer_source_discover_v1 as live ($SP_B, $DI_B)"

# refused on a changed body; nothing applied
RF=${DB}_refuse; dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute replace(pg_get_functiondef('$DI'::regprocedure), 'v_settled int := 0;', 'v_settled int := 0 + 0;'); end \$\$" >/dev/null
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "applied over a changed body"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "unexpected refusal: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d $RF -Atc "select count(*) from pg_tables where tablename = 'aer_discovery_campaigns'")" = 0 ] || { echo "the refused migration left a table"; exit 1; }
echo "refused: a hand-changed live body is refused and nothing is applied"; dropdb --if-exists $RF >/dev/null 2>&1

# the migration, then again
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$SP_A $DI_A" ] || { echo "after md5s differ: $(md5s)"; exit 1; }
for want in "$SP $SP_B -> $SP_A" "$DI $DI_B -> $DI_A"; do grep -qF -- "--   $want" $M || { echo "header does not record: $want"; exit 1; }; done
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$SP_A $DI_A" ] && [ "$(q "select count(*) from pipeline.aer_discovery_campaigns")" = 1 ] || { echo "applied again: something changed"; exit 1; }
echo "migration: both bodies go to the recorded after md5s; one running campaign; applied again: no change"

# behaviour
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
-- 5 eligible providers: A,B,C no source (A biggest), D has a source, E has no website
insert into catalogue.providers(id, canonical_name, website) values
 ('a0000000-0000-0000-0000-00000000000a','A','https://a.edu.au'),('b0000000-0000-0000-0000-00000000000b','B','https://b.edu.au'),('c0000000-0000-0000-0000-00000000000c','C','https://c.edu.au'),
 ('d0000000-0000-0000-0000-00000000000d','D','https://d.edu.au'),('e0000000-0000-0000-0000-00000000000e','E',null);
insert into catalogue.courses(provider_id) select 'a0000000-0000-0000-0000-00000000000a' from generate_series(1,3);
insert into catalogue.courses(provider_id) select 'b0000000-0000-0000-0000-00000000000b' from generate_series(1,2);
insert into pipeline.entry_matrix_sources(provider_id, url, status) values ('d0000000-0000-0000-0000-00000000000d','https://d.edu.au/entry.pdf','read');
-- the 22 Oct defect: an open (pre-campaign) request for C whose central row carries an OLD refusal
insert into pipeline.aer_source_discover_requests(provider_id, requested_at) values ('c0000000-0000-0000-0000-00000000000c', now() - interval '1 hour');
insert into pipeline.provider_central_search(provider_id, state, requested_at, searched_at, updated_at, evidence) values ('c0000000-0000-0000-0000-00000000000c','queued',null, now() - interval '20 days', now() - interval '20 days', '{"refusal":"credits_refused"}');
update pipeline.platform_toolset_settings set value = '2' where key = 'aer.discovery_campaign_batch';
do $$ declare r jsonb; o record; begin
  r := security.aer_source_discover_v1(false);
  perform pg_temp.ok((select outcome from pipeline.aer_source_discover_requests where provider_id = 'c0000000-0000-0000-0000-00000000000c' and campaign_id is null) is null,
    'an open request is not settled refused from evidence recorded before it (the 22 Oct defect)');
  perform pg_temp.ok((r->'campaign'->>'asked')::int = 2 and (select count(*) from pipeline.aer_source_discover_requests where campaign_id is not null) = 2,
    'the campaign asks up to its batch (2), biggest first');
  perform pg_temp.ok(exists (select 1 from pipeline.aer_source_discover_requests where campaign_id is not null and provider_id = 'a0000000-0000-0000-0000-00000000000a'), 'A (most courses) asked first');
  perform pg_temp.ok(not exists (select 1 from pipeline.aer_source_discover_requests where campaign_id is not null and provider_id in ('d0000000-0000-0000-0000-00000000000d','e0000000-0000-0000-0000-00000000000e')),
    'a provider with a source, or with no website, is never asked');
  perform pg_temp.ok((select outcome from security.aer_discovery_outcomes_v1() where provider_id = 'e0000000-0000-0000-0000-00000000000e') = 'no_website'
    and (select outcome from security.aer_discovery_outcomes_v1() where provider_id = 'd0000000-0000-0000-0000-00000000000d') = 'source_read'
    and (select source_type from security.aer_discovery_outcomes_v1() where provider_id = 'd0000000-0000-0000-0000-00000000000d') = 'pdf', 'outcomes: no website, source read (pdf)');
  perform pg_temp.ok((select count(*) from security.aer_discovery_outcomes_v1()) = 5, 'every eligible provider has an outcome row');
  -- the ceiling: 10 used of 12, a 4-credit spend for an asked provider is refused campaign_cap; a provider not asked is not
  update pipeline.platform_toolset_settings set value = '12' where key = 'aer.discovery_campaign_credit_cap';
  insert into pipeline.coverage_vendor_usage(units, purpose, provider_id) values (10, 'central_map', 'a0000000-0000-0000-0000-00000000000a');
  perform pg_temp.ok(security.aer_discovery_campaign_over_v1('a0000000-0000-0000-0000-00000000000a', 4), 'a spend past the ceiling is over');
  perform pg_temp.ok(not security.aer_discovery_campaign_over_v1('a0000000-0000-0000-0000-00000000000a', 2), 'a spend within the ceiling is not');
  perform pg_temp.ok(not security.aer_discovery_campaign_over_v1('d0000000-0000-0000-0000-00000000000d', 400), 'a provider the campaign did not ask is never held by its ceiling');
  -- settled outcomes, then completion
  update pipeline.aer_source_discover_requests set outcome = 'no_entry_page', outcome_at = now() where outcome is null;
  update pipeline.platform_toolset_settings set value = '10000' where key = 'aer.discovery_campaign_credit_cap';
  update pipeline.platform_toolset_settings set value = '10' where key = 'aer.discovery_campaign_batch';
  r := security.aer_discovery_campaign_ask_v1(false);
  perform pg_temp.ok((r->>'asked')::int = 1, 'the next run asks the remaining provider (C)');
  update pipeline.aer_source_discover_requests set outcome = 'no_entry_page', outcome_at = now() where outcome is null;
  r := security.aer_discovery_campaign_ask_v1(false);
  perform pg_temp.ok((r->>'left_without_outcome')::int = 0 and (select state from pipeline.aer_discovery_campaigns) = 'complete', 'every provider has an outcome: the campaign is complete');
  perform pg_temp.ok((select (public.admin_aer_discovery('{}'::jsonb)->>'providers')::int) = 5, 'the screen read returns every provider');
end $$;
SQL
echo "behaviour: stale refusals ignored, batch and order, skips, ceiling, outcomes for all, completion, screen read"

# recovery: both bodies back byte for byte, campaign off, nothing dropped
OUT=$($P -1 -At -f $R 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$SP_B $DI_B" ] || { echo "recovery did not restore the live md5s"; exit 1; }
[ "$(q "select value from pipeline.platform_toolset_settings where key = 'aer.discovery_campaign_on'")" = 0 ] && [ "$(q "select count(*) from pg_tables where tablename = 'aer_discovery_campaigns'")" = 1 ] || { echo "recovery state wrong"; exit 1; }
echo "recovery: bodies back to $SP_B and $DI_B, campaign off, nothing dropped"
echo "PASS aer-discovery-campaign"
