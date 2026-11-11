#!/usr/bin/env bash
# Guards: F-AER.04 discovery campaign spare capacity (Platform Admin decision D2, 11 Nov 2026) and G4 database-backed tests: migration 20261112103900 edits
# security.aer_discovery_campaign_used_v1, public.svc_fc_spend and public.admin_aer_discovery only from their live bodies (2b1e2ec8..., c9d616fa..., 2f26aa26...), leaves the
# recorded after md5s, is refused on a changed body, is idempotent; the credit count is unchanged; the campaign takes spare credits only inside the daily total, after other
# groups' projected need, above the vendor floor and within the daily maximum, never past its ceiling; the held forward recovery takes it back byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Drops its databases at the end (ADC_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ADC_DB:-g_aer_discovery_spare}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
C=tests/fixtures/aer-discovery-campaign
F=tests/fixtures/aer-discovery-spare
M0=supabase/migrations/20261112040000_cf247_aer_discovery_campaign.sql
M=${ADS_MIG:-supabase/migrations/20261112103900_cf247_aer_discovery_spare.sql}
R=${ADS_REC:-supabase/held/aer_discovery_spare_forward_recovery.sql}
U='security.aer_discovery_campaign_used_v1(bigint)'; SP='public.svc_fc_spend(numeric,text,uuid,text)'; AD='public.admin_aer_discovery(jsonb)'
B="2b1e2ec802e29f873fe0a77c85fe7150 c9d616fa35a278103121416ce73e0295 2f26aa2679d98904bb310bc97857857c"
A="${ADS_AFTER:-a1635da2b5eb53b4539518cb65ba7198 07972f712be389e84d49f33a0852f534 8a84d58d70e1c7f31606af2b4199363b}"
q() { psql -X -d "$DB" -Atc "$1"; }
md5s() { echo "$(q "select md5(prosrc) from pg_proc where oid = '$U'::regprocedure") $(q "select md5(prosrc) from pg_proc where oid = '$SP'::regprocedure") $(q "select md5(prosrc) from pg_proc where oid = '$AD'::regprocedure")"; }
trap '[ -n "${ADC_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; }' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; end \$\$"
grep -v '^create role' $C/stubs.sql | $P
for f in public.svc_fc_spend security.aer_source_discover_v1; do { echo "set check_function_bodies = off;"; cat $C/live/$f.sql; echo ";"; } | $P; done
$P -1 -f $M0 >/dev/null 2>&1 || { echo "the campaign migration did not apply"; exit 1; }
$P -f $F/stubs.sql
[ "$(md5s)" = "$B" ] || { echo "the bodies before this change differ from live: $(md5s)"; exit 1; }
echo "loaded: the three bodies as live ($B)"

RF=${DB}_refuse; dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "do \$\$ begin execute replace(pg_get_functiondef('$AD'::regprocedure), 'v_off int', 'v_off  int'); end \$\$" >/dev/null
OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "applied over a changed body"; exit 1; }
grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "unexpected refusal: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d $RF -Atc "select count(*) from pg_tables where tablename = 'aer_discovery_spare_spends'")" = 0 ] || { echo "the refused migration left a table"; exit 1; }
echo "refused: a hand-changed live body is refused and nothing is applied"; dropdb --if-exists $RF >/dev/null 2>&1

# the credit count before the change, on a dataset with two requests for one provider and spends before and after
$P <<'SQL'
insert into catalogue.providers(id, canonical_name, website) values ('a0000000-0000-0000-0000-00000000000a','A','https://a.edu.au'),('b0000000-0000-0000-0000-00000000000b','B','https://b.edu.au'),
 ('c0000000-0000-0000-0000-00000000000c','C','https://c.edu.au'),('d0000000-0000-0000-0000-00000000000d','D','https://d.edu.au');
insert into pipeline.aer_source_discover_requests(provider_id, campaign_id, requested_at, outcome) values
 ('a0000000-0000-0000-0000-00000000000a', 1, now() - interval '5 hours', 'refused'), ('a0000000-0000-0000-0000-00000000000a', 1, now() - interval '2 hours', null),
 ('b0000000-0000-0000-0000-00000000000b', 1, now() - interval '4 hours', null), ('c0000000-0000-0000-0000-00000000000c', 1, now() - interval '4 hours', 'no_entry_page');
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id, at) values
 (7, 'central_map', 'a0000000-0000-0000-0000-00000000000a', now() - interval '6 hours'), (3, 'central_map', 'a0000000-0000-0000-0000-00000000000a', now() - interval '3 hours'),
 (2, 'central_entry_search', 'a0000000-0000-0000-0000-00000000000a', now() - interval '1 hour'), (5, 'scrape', 'b0000000-0000-0000-0000-00000000000b', now() - interval '1 hour'),
 (4, 'central_map', 'b0000000-0000-0000-0000-00000000000b', now() - interval '3 hours'), (9, 'central_map', 'd0000000-0000-0000-0000-00000000000d', now() - interval '1 hour');
insert into pipeline.entry_matrix_sources(provider_id, url, status, created_at) values ('b0000000-0000-0000-0000-00000000000b', 'https://b.edu.au/entry', 'read', now() - interval '1 hour');
SQL
USED_B=$(q "select security.aer_discovery_campaign_used_v1(1)")

OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$A" ] || { echo "after md5s differ: $(md5s)"; exit 1; }
for f in "$U" "$SP" "$AD"; do grep -qF -- "--   $f " $M || { echo "header does not record $f"; exit 1; }; done
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$A" ] || { echo "applied again: something changed"; exit 1; }
[ "$(q "select security.aer_discovery_campaign_used_v1(1)")" = "$USED_B" ] && [ "$USED_B" = 9 ] || { echo "the credit count changed: $USED_B -> $(q "select security.aer_discovery_campaign_used_v1(1)")"; exit 1; }
echo "migration: the three bodies go to the recorded after md5s; applied again: no change; credit count unchanged ($USED_B)"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare r jsonb; v boolean; n numeric; begin
  -- today: central 9+2+... (share 20) ; use up the central share so the share would refuse
  insert into pipeline.coverage_vendor_usage(units, purpose, provider_id) values (20, 'central_map', 'd0000000-0000-0000-0000-00000000000d');
  perform pg_temp.ok(security.fc_budget_left_v1('central_entry_search') = 0, 'the central share is used up');
  r := security.aer_discovery_spare_room_v1();
  perform pg_temp.ok((r->>'room')::numeric = 0 and r->>'why' = 'no vendor balance read in the last 2 hours', 'no fresh vendor balance: no spare room');
  perform pg_temp.ok(not public.svc_fc_spend(4, 'central_entry_search', 'b0000000-0000-0000-0000-00000000000b', 'https://b.edu.au'), 'without spare room the share refuses');
  update pipeline.fx_vendor set room = 5000;
  r := security.aer_discovery_spare_room_v1();
  n := (r->>'day_total')::numeric - (r->>'billed_automatic')::numeric - (r->>'kept_for_others')::numeric - (r->>'central_unused')::numeric;
  perform pg_temp.ok((r->>'room')::numeric = greatest(0, floor(least(1000, n, 5000))) and (r->>'room')::numeric > 0, 'room is the day total less billed, less other groups'' projected need, less unused central share');
  perform pg_temp.ok((r->'groups'->'reads'->>'kept')::numeric > 0, 'a group spending now keeps its projected need');
  -- a campaign provider with an open request may take it; a provider the campaign did not ask may not
  perform pg_temp.ok(public.svc_fc_spend(4, 'central_entry_search', 'b0000000-0000-0000-0000-00000000000b', 'https://b.edu.au'), 'an open campaign request takes a spare spend');
  perform pg_temp.ok((select count(*) = 1 and sum(units) = 4 from pipeline.aer_discovery_spare_spends), 'the spare spend is recorded');
  perform pg_temp.ok(not public.svc_fc_spend(4, 'central_map', 'd0000000-0000-0000-0000-00000000000d', 'https://d.edu.au'), 'a provider the campaign did not ask is refused by the share');
  perform pg_temp.ok(not public.svc_fc_spend(4, 'central_map', 'c0000000-0000-0000-0000-00000000000c', 'https://c.edu.au'), 'a provider whose request has an outcome is refused by the share');
  -- the daily maximum
  update pipeline.platform_toolset_settings set value = '6' where key = 'aer.discovery_spare_daily_max';
  perform pg_temp.ok(not public.svc_fc_spend(4, 'central_entry_search', 'a0000000-0000-0000-0000-00000000000a', 'https://a.edu.au'), 'past the daily maximum (4 taken of 6): refused');
  perform pg_temp.ok(public.svc_fc_spend(2, 'central_entry_search', 'a0000000-0000-0000-0000-00000000000a', 'https://a.edu.au'), 'within the daily maximum: allowed');
  update pipeline.platform_toolset_settings set value = '5000' where key = 'aer.discovery_spare_daily_max';
  perform pg_temp.ok((security.aer_discovery_spare_room_v1()->>'daily_max')::numeric = 1000, 'the daily maximum never passes 1,000 (decision D2)');
  -- the vendor floor
  update pipeline.fx_vendor set room = 3;
  perform pg_temp.ok(not public.svc_fc_spend(4, 'central_entry_search', 'b0000000-0000-0000-0000-00000000000b', 'https://b.edu.au'), 'the vendor floor holds: refused');
  update pipeline.fx_vendor set room = 5000;
  -- the campaign ceiling still applies to spare spends
  update pipeline.platform_toolset_settings set value = '16' where key = 'aer.discovery_campaign_credit_cap';
  perform pg_temp.ok(not public.svc_fc_spend(4, 'central_entry_search', 'b0000000-0000-0000-0000-00000000000b', 'https://b.edu.au'), 'the campaign ceiling still refuses a spare spend');
  perform pg_temp.ok((select x.n from pipeline.firecrawl_budget_refusals x where x.reason = 'campaign_cap') >= 1, 'refused as campaign_cap');
  update pipeline.platform_toolset_settings set value = '10000' where key = 'aer.discovery_campaign_credit_cap';
  -- the day total: other groups' need fills the day
  insert into pipeline.coverage_vendor_usage(units, purpose, provider_id) values (80, 'scrape', null);
  perform pg_temp.ok((security.aer_discovery_spare_room_v1()->>'room')::numeric = 0, 'no spare capacity when the day total is spoken for: room 0');
  perform pg_temp.ok(not public.svc_fc_spend(1, 'central_entry_search', 'b0000000-0000-0000-0000-00000000000b', 'https://b.edu.au'), 'and the spend is refused');
  -- switched off
  delete from pipeline.coverage_vendor_usage where units = 80;
  update pipeline.platform_toolset_settings set value = '0' where key = 'aer.discovery_spare_daily_max';
  perform pg_temp.ok((security.aer_discovery_spare_room_v1()->>'room')::numeric = 0, 'aer.discovery_spare_daily_max 0: no spare room');
  -- metrics
  r := security.aer_discovery_metrics_v1();
  perform pg_temp.ok((r->>'providers_attempted')::int = 3 and (r->>'usable_sources')::int = 1 and (r->>'not_found')::int = 1 and (r->>'spare_credits_total')::numeric = 6
                     and (r->>'cost_per_usable_source')::numeric = (r->>'credits')::numeric, 'metrics: attempted, usable sources, not found, spare credits, cost per usable source');
  perform pg_temp.ok(public.admin_aer_discovery('{}'::jsonb) ? 'metrics', 'the discovery screen read carries the metrics');
end $$;
SQL
echo "behaviour: no vendor balance, room arithmetic, campaign-only, daily maximum and its 1,000 limit, vendor floor, campaign ceiling, day total, switch, metrics"

OUT=$($P -1 -At -f $R 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(md5s)" = "$B" ] || { echo "recovery did not restore the live md5s: $(md5s)"; exit 1; }
[ "$(q "select value from pipeline.platform_toolset_settings where key = 'aer.discovery_spare_daily_max'")" = 0 ] && [ "$(q "select count(*) from pg_tables where tablename = 'aer_discovery_spare_spends'")" = 1 ] || { echo "recovery state wrong"; exit 1; }
echo "recovery: bodies back to $B, spare off, nothing dropped"
echo "PASS aer-discovery-spare"
