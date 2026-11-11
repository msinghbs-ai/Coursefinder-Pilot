#!/usr/bin/env bash
# Guards: F-AER.02 AER self-healing (Platform Admin decision delivery item 4, 11 Nov 2026: recover pending re-reads without duplicate Layer 4 items) and G4 database-backed tests:
# migration 20261112123700 on the scheduled AER tick as live after 20261111220000 (../aer-self-healing, b9616377...) with security.aer_read_supersession_close_v1 as live
# (de5a1165...): a corrected read skipped before reading, or whose read is gone, is closed as refused with the reader's reason by each non-preview tick and never by a preview;
# a read in progress or skipped minutes ago is left; no Layer 4 item is created or changed; md5-guarded, idempotent; the held forward recovery restores the tick byte for byte.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (ASS_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort, whatever the runner's locale
DB=${ASS_DB:-g_aer_supersession_settle}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
H=tests/fixtures/aer-self-healing; B=tests/fixtures/aer-source-recovery; F=tests/fixtures/aer-supersession-settle
M0=supabase/migrations/20261111220000_cf247_aer_self_healing_corrections.sql
M=supabase/migrations/20261112123700_cf247_aer_supersession_settle.sql; R=supabase/held/aer_supersession_settle_forward_recovery.sql
TICK='security.aer_schedule_tick_v1(boolean)'; T_B=b96163772b72f02b6c9956b1a263224a; T_A=${ASS_AFTER:-800af9161234c24387bff6a74d6acb99}
q() { psql -X -d "$DB" -Atc "$1"; }
trap '[ -n "${ASS_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
$P -f $B/stubs.sql
$P -c "alter table pipeline.platform_toolset_settings add column label text, add column help text, add column kind text, add column min_value numeric, add column max_value numeric, add column unit text, add column sort int, add column section text, add column used_by text, add column reason text, add column updated_at timestamptz"
$P -f $H/stubs.sql
for f in security.aer_schedule_held_v1 security.aer_schedule_tick_v1; do { echo "set check_function_bodies = off;"; cat $H/live/$f.sql; echo ";"; } | $P; done
$P -f $B/data.sql; $P -f $B/seed_l4.sql; $P -f $H/seed.sql
$P -1 -f $M0 >/dev/null 2>&1 || { echo "20261111220000 did not apply"; exit 1; }
# the live shape of the corrected-read record (the base stub has fewer columns), and the read's reason
$P <<'SQL'
drop table if exists pipeline.aer_read_supersessions;
create table pipeline.aer_read_supersessions (id uuid primary key default gen_random_uuid(), old_item_id uuid, course_id uuid, source_url text, old_evidence_id uuid, enrich_item_id uuid,
  job_id uuid, requested_by uuid, reason text, state text not null default 'requested', new_item_id uuid, outcome text, diff jsonb, requested_at timestamptz default now(), closed_at timestamptz);
alter table pipeline.field_enrich_items add column if not exists reason text;
SQL
{ cat $F/live/security.aer_read_supersession_close_v1.sql; echo ";"; } | $P
[ "$(q "select md5(prosrc) from pg_proc where oid = 'security.aer_read_supersession_close_v1(uuid,text,text,uuid,jsonb)'::regprocedure")" = de5a11655576a6c464c40021c4c1cfdb ] || { echo "the loaded close differs from live"; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = $T_B ] || { echo "the tick after 20261111220000 differs from live $T_B"; exit 1; }
echo "loaded: the tick as live after 20261111220000 ($T_B) and the close as live (de5a1165)"

# the defect, and what must be left: an old skipped read (closes), a read skipped 2 minutes ago (left), a read in progress (left), a read that is gone (closes)
$P <<'SQL'
insert into pipeline.field_enrich_items(id, field, state, reason, updated_at) values
 ('e0000000-0000-0000-0000-0000000000e1', 'entry_requirements', 'skipped', 'no proven course page: the page found is not proved to be this course''s (E16)', now() - interval '8 days'),
 ('e0000000-0000-0000-0000-0000000000e2', 'entry_requirements', 'skipped', 'no proven course page (E16)', now() - interval '2 minutes'),
 ('e0000000-0000-0000-0000-0000000000e3', 'entry_requirements', 'queued', null, now() - interval '3 hours');
insert into pipeline.aer_read_supersessions(id, old_item_id, enrich_item_id, state, requested_at) values
 ('50000000-0000-0000-0000-000000000001', gen_random_uuid(), 'e0000000-0000-0000-0000-0000000000e1', 'requested', now() - interval '8 days'),
 ('50000000-0000-0000-0000-000000000002', gen_random_uuid(), 'e0000000-0000-0000-0000-0000000000e2', 'requested', now() - interval '3 minutes'),
 ('50000000-0000-0000-0000-000000000003', gen_random_uuid(), 'e0000000-0000-0000-0000-0000000000e3', 'requested', now() - interval '3 hours'),
 ('50000000-0000-0000-0000-000000000004', gen_random_uuid(), 'e0000000-0000-0000-0000-0000000000e4', 'requested', now() - interval '1 day');
SQL
L4_0=$(q "select count(*) || ':' || md5(string_agg(id::text || status, ',' order by id)) from pipeline.layer4_review_items")

OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = "$T_A" ] || { echo "the tick did not reach $T_A: $(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")"; exit 1; }
grep -qF -- "--   $TICK $T_B -> $T_A" $M || { echo "header does not record the tick md5s"; exit 1; }
grep -qF "corrected reads settled now: 2" <<<"$OUT" || { echo "the run-once settle did not close 2: $OUT" | tail -3; exit 1; }
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = "$T_A" ] || { echo "applied again: changed"; exit 1; }
echo "migration: the tick goes to $T_A; run once: 2 settled; applied again: no change"

$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare t jsonb; begin
  perform pg_temp.ok((select state = 'refused' and outcome = 'the corrected read was not made: no proven course page: the page found is not proved to be this course''s (E16)' and closed_at is not null
                        from pipeline.aer_read_supersessions where id = '50000000-0000-0000-0000-000000000001'), 'a read skipped before reading closes as refused with the reader''s reason');
  perform pg_temp.ok((select state = 'refused' and outcome like '%no longer exists' from pipeline.aer_read_supersessions where id = '50000000-0000-0000-0000-000000000004'), 'a corrected read whose read is gone closes');
  perform pg_temp.ok((select state from pipeline.aer_read_supersessions where id = '50000000-0000-0000-0000-000000000002') = 'requested', 'a read skipped minutes ago is left (claim timer)');
  perform pg_temp.ok((select state from pipeline.aer_read_supersessions where id = '50000000-0000-0000-0000-000000000003') = 'requested', 'a read still queued is left');
  -- a new skip after the deploy: a preview never settles; the next real run does
  update pipeline.field_enrich_items set updated_at = now() - interval '1 hour' where id = 'e0000000-0000-0000-0000-0000000000e2';
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((select state from pipeline.aer_read_supersessions where id = '50000000-0000-0000-0000-000000000002') = 'requested', 'a preview tick settles nothing');
  t := security.aer_schedule_tick_v1(false);
  perform pg_temp.ok((select state from pipeline.aer_read_supersessions where id = '50000000-0000-0000-0000-000000000002') = 'refused', 'the next scheduled tick settles it');
  perform pg_temp.ok((select state from pipeline.aer_read_supersessions where id = '50000000-0000-0000-0000-000000000003') = 'requested', 'and still leaves the queued read');
end $$;
SQL
[ "$(q "select count(*) || ':' || md5(string_agg(id::text || status, ',' order by id)) from pipeline.layer4_review_items")" = "$L4_0" ] || { echo "Layer 4 items were created, removed or changed"; exit 1; }
echo "behaviour: skipped and gone reads close with the reason; recent and queued reads are left; a preview never settles; no Layer 4 item is created by a settle"

OUT=$($P -1 -At -f $R 2>&1) || { echo "$OUT" | tail -8; exit 1; }
[ "$(q "select md5(prosrc) from pg_proc where oid = '$TICK'::regprocedure")" = $T_B ] || { echo "recovery did not restore the tick"; exit 1; }
echo "recovery: the tick back to $T_B, nothing dropped"
echo "PASS aer-supersession-settle"
