#!/usr/bin/env bash
# Guards: Platform Admin 6 Nov 2026 09:44 (English requirements automation) and the AER precedent 29 Oct 2026 ("a budget refusal is not the page failing"): a refused provider-page or scholarship read keeps its tries.
# Database round trip on isolated local PostgreSQL only (never a Supabase project):
#   1 the md5-verified production manifest of the English path builds the fixture (real provider_fact_sources constraints, settings table, pipeline_num_v1);
#   2 the three LIVE function definitions (read on 7 Nov 2026, unedited) are installed and their md5 equals the one the migration guards;
#   3 BEFORE the migration: the live behaviour that closes a refused source after three refusals is shown;
#   4 the migration 20261107060000 applies, then the behaviour tests run; a changed live definition makes the migration refuse.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
DB=${RF_DB:-h2_refusal_fixture}; FX=tests/fixtures/english-refusal; M=tests/fixtures/english-requirements/manifests/english-path.json
MIG=supabase/migrations/20261107060000_cf247_refusal_is_not_a_try.sql
P="psql -X -q -At -v ON_ERROR_STOP=1 -d $DB"
cleanup() { [ -n "${RF_KEEP:-}" ] || dropdb --if-exists "$DB" 2>/dev/null || true; }
trap cleanup EXIT
fail() { echo "FAIL $*"; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: got '$1', want '$2'"; echo "PASS $3"; }
dropdb --if-exists "$DB"; createdb "$DB"
$P -f tests/fixtures/english-requirements/prelude.sql >/dev/null
node scripts/prod-parity-capture.mjs fixture $M | $P >/dev/null 2>&1 || fail 'the production-manifest fixture did not apply'
$P -f $FX/harness.sql >/dev/null
$P -f $FX/live-functions.sql >/dev/null; $P -f $FX/live-scholarship-ai-record.sql >/dev/null
for pair in 'public.svc_provider_facts_read_next(integer)' 'public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb)' 'public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)'; do
  got=$($P -c "select md5(pg_get_functiondef('$pair'::regprocedure))"); grep -qF "$got" $MIG || fail "$pair md5 $got is not guarded by the migration"
done; echo 'PASS the installed live definitions carry the md5 the migration guards'
S="set request.jwt.claim.role = 'service_role';"
$P >/dev/null <<'SQL'
insert into catalogue.providers(id, stable_key) values ('00000000-0000-0000-0000-00000000a001','rf-1'),('00000000-0000-0000-0000-00000000a002','rf-2'),('00000000-0000-0000-0000-00000000a003','rf-3');
SQL
src() { $P -c "insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, attempts, parse_summary) values ('$1','$2','english_policy','https://example.invalid/$1','t',5,'search','$3',$4,$5)"; }
st() { $P -c "select status||'/'||attempts from pipeline.provider_fact_sources where id='$1'"; }
rec() { $P -c "$S select (public.svc_provider_facts_read_record('$1','failed',null,null,null,null,'[]'::jsonb,'{\"error\":\"$2\"}'::jsonb))->>'status'" | tail -1; }
A=00000000-0000-0000-0000-0000000000a1; B=00000000-0000-0000-0000-0000000000a2; C=00000000-0000-0000-0000-0000000000a3
PA=00000000-0000-0000-0000-00000000a001; PB=00000000-0000-0000-0000-00000000a002; PC=00000000-0000-0000-0000-00000000a003
# 3 live behaviour before the migration: the third refusal closes the source for good
src $A $PA reading 3 "null"; rec $A budget >/dev/null; eq "$(st $A)" 'failed/3' 'BEFORE: a source refused for budget on its third lease is closed failed (the live bug)'
# scholarship BEFORE: the live function closes an item refused for credits on its third try
$P >/dev/null <<'SQL'
insert into pipeline.scholarship_read_requests(id) values (7000);
insert into pipeline.scholarship_ai_queue(id, state, attempts, read_request_id) values (900, 'leased', 3, 7000);
SQL
$P -c "$S select public.svc_scholarship_ai_record(900, null, null, null, 0, null, null, 0, null, null, null, null, null, true)" >/dev/null
eq "$($P -c "select state||'/'||skip_reason from pipeline.scholarship_ai_queue where id=900")" 'failed/no scraper credit after 3 tries' 'BEFORE: a scholarship read refused for credits on its third try is closed (the live bug)'
# 4 migration
$P -f $MIG >/dev/null 2>"/tmp/rf-mig.err" || { cat /tmp/rf-mig.err; fail 'the migration did not apply'; }; echo 'PASS the migration applies on the fixture'
src $B $PA reading 3 "null"; eq "$(rec $B budget)" 'refused' 'a refused read is reported as refused'; eq "$(st $B)" 'found/2' 'a source refused for budget keeps its tries and stays found'
src 00000000-0000-0000-0000-0000000000b1 $PB reading 3 "null"; rec 00000000-0000-0000-0000-0000000000b1 target_list_refused >/dev/null; eq "$(st 00000000-0000-0000-0000-0000000000b1)" 'found/2' 'a target-list refusal keeps its tries'
src 00000000-0000-0000-0000-0000000000b2 $PB reading 3 "null"; rec 00000000-0000-0000-0000-0000000000b2 'time budget' >/dev/null; eq "$(st 00000000-0000-0000-0000-0000000000b2)" 'found/2' 'a run-time refusal keeps its tries'
src 00000000-0000-0000-0000-0000000000b3 $PB reading 3 "null"; rec 00000000-0000-0000-0000-0000000000b3 'no content' >/dev/null; eq "$(st 00000000-0000-0000-0000-0000000000b3)" 'failed/3' 'a page that gave no content still fails on its third try'
src 00000000-0000-0000-0000-0000000000b4 $PB reading 1 "null"; rec 00000000-0000-0000-0000-0000000000b4 'no content' >/dev/null; eq "$(st 00000000-0000-0000-0000-0000000000b4)" 'found/1' 'a page that gave no content is tried again while it has tries (unchanged)'
src 00000000-0000-0000-0000-0000000000b5 $PB reading 3 "null"; rec 00000000-0000-0000-0000-0000000000b5 'budget exceeded for this page' >/dev/null; eq "$(st 00000000-0000-0000-0000-0000000000b5)" 'failed/3' 'only the worker refusal names count (a longer text is a real error)'
src 00000000-0000-0000-0000-0000000000b6 $PB reading 0 "null"; rec 00000000-0000-0000-0000-0000000000b6 budget >/dev/null; eq "$(st 00000000-0000-0000-0000-0000000000b6)" 'found/0' 'a refusal never takes the tries below zero'
# the picker: refused pages wait; others are not starved by them
$P >/dev/null <<SQL
update pipeline.provider_fact_sources set status = 'failed' where id <> '$B';
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, attempts, parse_summary)
values ('00000000-0000-0000-0000-0000000000c1','$PC','english_policy','https://example.invalid/new','t',5,'search','found',0,null);
SQL
ids() { $P -c "$S select coalesce(string_agg(x->>'id', ',' order by x->>'id'), '') from jsonb_array_elements(public.svc_provider_facts_read_next(10)) x" | tail -1; }
eq "$(ids)" '00000000-0000-0000-0000-0000000000c1' 'the picker offers the new page and not the one just refused (it waits)'
$P >/dev/null <<SQL
update pipeline.provider_fact_sources set status = 'found' where id = '00000000-0000-0000-0000-0000000000c1';
update pipeline.provider_fact_sources set updated_at = now() - interval '7 hours' where id = '$B';
SQL
eq "$(ids)" "$B,00000000-0000-0000-0000-0000000000c1" 'after retry.provider_facts_refusal_hours (6) the refused page is offered again with its tries intact'
eq "$($P -c "select attempts from pipeline.provider_fact_sources where id='$B'")" '3' 'leasing it again uses one try (2 -> 3)'
$P -c "update pipeline.platform_toolset_settings set value = to_jsonb(12) where key = 'retry.provider_facts_refusal_hours'" >/dev/null
$P >/dev/null <<SQL
update pipeline.provider_fact_sources set status = 'found', attempts = 1, parse_summary = '{"error":"budget"}'::jsonb, updated_at = now() - interval '7 hours' where id = '$B';
SQL
eq "$(ids)" '' 'the waiting time is the setting (12 hours: a page refused 7 hours ago still waits)'
# scholarship queue: BEFORE is shown by the installed live function in a second database
SQ=$P
sq() { $P -c "insert into pipeline.scholarship_ai_queue(id, state, attempts, created_at, read_request_id) values ($1,'leased',$2,now() - interval '$3',${4:-null})"; }
sqs() { $P -c "select state||'/'||attempts||'/'||coalesce(skip_reason,'-') from pipeline.scholarship_ai_queue where id=$1"; }
retry() { $P -c "$S select public.svc_scholarship_ai_record($1, null, null, null, 0, null, null, 0, null, null, null, null, null, true)" >/dev/null; }
$P >/dev/null <<'SQL'
insert into pipeline.scholarship_read_requests(id) values (7001);
SQL
sq 1 2 '1 day'; retry 1; eq "$(sqs 1)" 'queued/1/-' 'scholarship: a read refused for credits keeps its tries (attempts 2 -> 1) and waits'
eq "$($P -c "select (next_try_at > now() + interval '29 minutes' and next_try_at < now() + interval '31 minutes')::text from pipeline.scholarship_ai_queue where id=1")" 'true' 'scholarship: it waits retry.sch_ai_wait_minutes (30)'
$P -c "update pipeline.platform_toolset_settings set value = to_jsonb(90) where key = 'retry.sch_ai_wait_minutes'" >/dev/null; sq 2 1 '1 day'; retry 2
eq "$($P -c "select (next_try_at > now() + interval '89 minutes' and next_try_at < now() + interval '91 minutes')::text from pipeline.scholarship_ai_queue where id=2")" 'true' 'scholarship: the wait is the setting (90 minutes)'
sq 3 3 '1 day' 7001; retry 3; eq "$(sqs 3)" 'queued/2/-' 'scholarship: the third refused try no longer closes the item (BEFORE: failed after 3 tries)'
eq "$($P -c "select state from pipeline.scholarship_read_requests where id=7001")" 'queued' 'scholarship: an approved single read is not ended by refusals inside the waiting time'
sq 4 3 '15 days' 7001; retry 4; eq "$(sqs 4)" 'failed/2/no scraper credit within the waiting time' 'scholarship: an item that has waited longer than sch_ai.wait_max_days (14) is closed with that reason'
eq "$($P -c "select state from pipeline.scholarship_read_requests where id=7001")" 'refused' 'scholarship: and its approved single read ends'
# settings
eq "$($P -c "select string_agg(key||'='||value||' ['||min_value||'-'||max_value||' '||unit||']', '; ' order by key) from pipeline.platform_toolset_settings where key in ('retry.provider_facts_refusal_hours','retry.sch_ai_wait_minutes','sch_ai.wait_max_days')")" 'retry.provider_facts_refusal_hours=12 [1-168 hours]; retry.sch_ai_wait_minutes=90 [5-1440 minutes]; sch_ai.wait_max_days=14 [1-90 days]' 'the three settings carry a range and a unit (values here are the ones the tests changed)'
# the migration refuses a live definition that has changed
$P -c "create or replace function public.svc_provider_facts_read_next(p_limit integer) returns jsonb language sql as \$f\$ select '[]'::jsonb \$f\$" >/dev/null
if $P -f $MIG >/dev/null 2>/tmp/rf-guard.err; then fail 'the migration applied over a changed live definition'; fi
grep -q 'differs from the definition this change was written against' /tmp/rf-guard.err || fail "the migration failed for another reason: $(cat /tmp/rf-guard.err)"; echo 'PASS the migration refuses a live definition that differs from the one it was written against'
echo 'ALL PASS'
