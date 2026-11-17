#!/usr/bin/env bash
# Guards: Destination data › Bulk Approve Drafts (Platform Admin 18 Nov 2026 07:39) and G4 database-backed tests: migration 20261118090000 on top of the
# destination schema (20261115190000, 20261115230000, 20261117040000, 20261117131500) runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase
# project). It proves: the migration applies twice; the action is the Platform Admin's with a reason; only clean drafts of the named edition are approved;
# a draft without attribution, another edition, and rows in any other status are left; each approved row carries who, when and why; one control event.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (DBA_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${DBA_DB:-g_destination_bulk_approve}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=supabase/migrations/20261118090000_cf247_destination_localities_bulk_approve.sql
trap '[ -n "${DBA_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f tests/fixtures/destination-editions/stubs.sql -f tests/fixtures/destination-schema-pack/stubs.sql
$P -1 -f supabase/migrations/20261115190000_api_v3_additive_schema.sql >/dev/null
$P -1 -f supabase/migrations/20261115230000_cf247_destination_importer_guard.sql >/dev/null
$P -1 -f supabase/migrations/20261117040000_cf247_rm_destination_schema_pack.sql >/dev/null
$P -f tests/fixtures/destination-admin-ui/stubs.sql
$P -1 -f supabase/migrations/20261117131500_cf247_rm0f_destination_admin_ui.sql >/dev/null
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; n0 bigint; v_admin uuid := '66666666-6666-6666-6666-666666666666'; begin
  -- edition A: 100 clean drafts, 2 drafts without attribution, 1 in review, 1 withdrawn, 1 already approved; edition B: 3 clean drafts
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, status)
  select 'AU', 'Locality ' || i, 'SUA', 'A' || i, 'ASGS_2021_ED3', 'Edition A',
         case when i in (101, 102) then case when i = 101 then '' else '   ' end else 'Source: Australian Bureau of Statistics' end,
         case when i = 103 then 'in_review' when i = 104 then 'withdrawn' when i = 105 then 'approved' else 'draft' end from generate_series(1, 105) i;
  insert into destination.localities(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, status)
  select 'AU', 'Other ' || i, 'SUA', 'B' || i, 'ASGS_2021_ED3', 'Edition B', 'Source: Australian Bureau of Statistics', 'draft' from generate_series(1, 3) i;
  select count(*) into n0 from pipeline.admin_control_events;
  perform pg_temp.ok(pg_temp.err($$select public.admin_destination_localities_bulk_approve('Edition A', 'fixture reason')$$) = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', v_admin::text, true); perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('fixture.rank', '5', true);
  if coalesce(security.current_role_rank(), 0) <> 5 then raise exception 'FAIL: the fixture cannot set a rank (stubs changed)'; end if;
  perform pg_temp.ok(pg_temp.err($$select public.admin_destination_localities_bulk_approve('Edition A', 'fixture reason')$$) like 'Platform Admin (rank 6)%', 'a PIM Operator (rank 5) cannot bulk approve');
  perform set_config('fixture.rank', '6', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_destination_localities_bulk_approve('Edition A', '  ')$$) = 'a reason is required'
    and pg_temp.err($$select public.admin_destination_localities_bulk_approve(' ', 'fixture reason')$$) = 'the dataset edition is required'
    and pg_temp.err($$select public.admin_destination_localities_bulk_approve('Edition Z', 'fixture reason')$$) = 'no draft locality is held for edition Edition Z', 'a reason and a known edition with drafts are required');
  perform pg_temp.ok((select count(*) from destination.localities where status = 'approved') = 1 and (select count(*) from pipeline.admin_control_events) = n0, 'a refused call changes nothing and logs nothing');
  r := public.admin_destination_localities_bulk_approve(' Edition A ', '  ABS population edition checked against the release  ');
  perform pg_temp.ok((r->>'drafts')::int = 102 and (r->>'approved')::int = 100 and (r->>'left_without_attribution')::int = 2 and r->>'dataset_edition' = 'Edition A', 'the Platform Admin approves the 100 clean drafts; the 2 without attribution are counted and left');
  perform pg_temp.ok((select count(*) from destination.localities where dataset_edition = 'Edition A' and status = 'approved' and status_changed_by = v_admin and status_reason = 'ABS population edition checked against the release' and status_changed_at is not null) = 100,
    'each approved locality carries who, when and the reason');
  perform pg_temp.ok((select array_agg(status order by geography_code) from destination.localities where geography_code in ('A101', 'A102', 'A103', 'A104')) = array['draft', 'draft', 'in_review', 'withdrawn']
    and (select status_changed_by is null from destination.localities where geography_code = 'A105')
    and (select count(*) from destination.localities where dataset_edition = 'Edition B' and status = 'draft') = 3, 'drafts without attribution, rows in another status, the row already approved and the other edition are untouched');
  perform pg_temp.ok((select count(*) from pipeline.admin_control_events) = n0 + 1
    and (select detail from pipeline.admin_control_events where id = (r->>'event_id')::bigint) = jsonb_build_object('dataset_edition', 'Edition A', 'drafts', 102, 'approved', 100, 'left_without_attribution', 2, 'reason', 'ABS population edition checked against the release')
    and (select area || '/' || action || '/' || target from pipeline.admin_control_events where id = (r->>'event_id')::bigint) = 'destination/localities_bulk_approve/Edition A', 'one control event records the whole action');
  r := public.admin_destination_localities_bulk_approve('Edition A', 'second pass');
  perform pg_temp.ok((r->>'approved')::int = 0 and (r->>'left_without_attribution')::int = 2 and (select count(*) from destination.localities where status_reason = 'second pass') = 0, 'a second pass approves nothing more and rewrites no reason');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_destination_localities_bulk_approve(text, text)', 'execute'), 'anon cannot run it');
end $t$;
SQL
echo "destination bulk approve: all checks passed"
