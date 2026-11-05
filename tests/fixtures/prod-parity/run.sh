#!/usr/bin/env bash
# Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026): production-representative fixtures; the parity tool must catch what simplified fixtures missed.
# Round trip of scripts/prod-parity-capture.mjs on isolated local PostgreSQL only (never a Supabase project):
#   1 a local stand-in for production (sample-source.sql) -> capture-sql -> save (md5-verified manifest);
#   2 fixture from the manifest into an empty database -> check-sql lists no difference (and runs inside a READ ONLY transaction);
#   3 production behaviour is reproduced: the outcome foreign key, the lock mode check, the composite primary key, RLS and grants refuse;
#   4 a simplified fixture (the intake releases' kind: no outcome foreign key, no manual_locks primary key) is caught, fact by fact;
#   5 a lookup table with a personal-data column is refused (no rows copied);
#   6 every committed production manifest still verifies and still builds a fixture that checks clean.
# Databases use agent E's prefix and are dropped at the end (PP_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
PFX=${PP_PREFIX:-e_pp}
SRC=${PFX}_src DST=${PFX}_dst SIMPLE=${PFX}_simple PRODFX=${PFX}_prodfx
T=$(mktemp -d); TOOL=scripts/prod-parity-capture.mjs FX=tests/fixtures/prod-parity
P="psql -X -q -v ON_ERROR_STOP=1"
cleanup() { [ -n "${PP_KEEP:-}" ] || for d in $SRC $DST $SIMPLE $PRODFX; do dropdb --if-exists "$d" 2>/dev/null || true; done; rm -rf "$T"; }
trap cleanup EXIT
for d in $SRC $DST $SIMPLE $PRODFX; do dropdb --if-exists "$d" 2>/dev/null || true; createdb "$d"; done
fail() { echo "FAIL $*"; exit 1; }
rows() { $P -At -d "$1" -f "$2" | grep -c . || true; }
refuses() { local db=$1 sql=$2 what=$3; if $P -d "$db" -c "$sql" >/dev/null 2>&1; then fail "$what was accepted"; fi; echo "PASS refuses: $what"; }

# 1 capture from the stand-in
$P -d $SRC -f $FX/sample-source.sql >/dev/null
SCOPE=(--tables pipeline.admin_jobs,pipeline.manual_locks --functions 'security.pp_job_count(text)' --lookups pipeline.ops_outcome_codes,pipeline.pp_operators)
node $TOOL capture-sql "${SCOPE[@]}" > $T/capture.sql
$P -At -d $SRC -f $T/capture.sql > $T/raw.json
node $TOOL save $T/raw.json $T/manifest.json 2>&1
node -e "
const m=require('$T/manifest.json'); const f=m.facts; const need=['constraint|pipeline.admin_jobs|admin_jobs_outcome_fkey','constraint|pipeline.manual_locks|manual_locks_pkey',
'constraint|pipeline.manual_locks|manual_locks_mode_ck','trigger|pipeline.manual_locks|manual_locks_touch','policy|pipeline.admin_jobs|admin_jobs_read','grant|pipeline.manual_locks|service_role',
'execute|security.pp_job_count(text)','function|security.pp_guard_active()','type|pipeline.pp_lock_mode','lookup_rows|pipeline.ops_outcome_codes','role|authenticated','table|pipeline.ops_outcome_codes'];
for (const k of need) if(!(k in f)) { console.error('manifest lacks '+k); process.exit(1) }
if (f['lookup_rows|pipeline.pp_operators']!=='refused: a column looks like personal data') { console.error('personal-data lookup not refused'); process.exit(1) }
if (JSON.stringify(m).includes('someone@example.invalid')) { console.error('personal data copied'); process.exit(1) }
console.log('PASS manifest: '+Object.keys(f).length+' facts, every production shape present, personal-data lookup refused and not copied')"
# a transcription error in a definition is refused
node -e "const m=require('$T/manifest.json'); m.functions[0].def+=' '; require('fs').writeFileSync('$T/bad.json', JSON.stringify(m))"
if node $TOOL verify $T/bad.json >/dev/null 2>&1; then fail 'a definition differing from its md5 was accepted'; fi
echo 'PASS a definition that differs from its captured md5 is refused'

# 2 fixture -> check clean (read only)
node $TOOL fixture $T/manifest.json > $T/fixture.sql
$P -d $DST -f $T/fixture.sql 2>&1 | grep -v '^NOTICE' || true
node $TOOL check-sql $T/manifest.json > $T/check.sql
{ echo 'begin transaction read only;'; cat $T/check.sql | sed '$ s/$/;/'; echo 'commit;'; } > $T/check-ro.sql
N=$($P -At -d $DST -f $T/check-ro.sql | grep -vc '^\(BEGIN\|COMMIT\)$' || true)
[ "$N" = 0 ] || { $P -d $DST -f $T/check.sql; fail "fixture differs from the manifest in $N fact(s)"; }
echo 'PASS fixture reproduces every captured fact; the check runs in a read-only transaction and lists no difference'
# the stand-in itself checks clean too (the same query is what runs on production)
[ "$(rows $SRC $T/check.sql)" = 0 ] || fail 'source differs from its own manifest'
echo 'PASS the check against the source lists no difference'
node $TOOL check-sql $T/manifest.json --digest > $T/digest.sql
[ "$($P -At -d $DST -f $T/digest.sql | cut -d'|' -f3)" = t ] || fail 'digest check on the fixture'
echo 'PASS the one-row digest check matches the manifest on the fixture'
node $TOOL check-sql $T/manifest.json --compact > $T/compact.sql
[ "$(rows $DST $T/compact.sql)" = 0 ] || fail 'compact check on the fixture'
echo 'PASS the compact (md5) check lists no difference on the fixture'

# 3 production behaviour reproduced
refuses $DST "insert into pipeline.admin_jobs(kind, outcome) values ('x', 'not_a_code')" 'admin_jobs outcome outside the code table (admin_jobs_outcome_fkey)'
$P -d $DST -c "insert into pipeline.admin_jobs(kind, outcome) values ('x', 'run_now_queued')" >/dev/null || fail 'a production outcome code was refused'
echo 'PASS accepts: admin_jobs outcome run_now_queued (seeded production code value)'
refuses $DST "insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', gen_random_uuid(), 'x', 'other')" 'manual_locks mode outside the enum'
$P -d $DST -c "insert into pipeline.manual_locks(entity, entity_id, field) values ('course', '00000000-0000-0000-0000-000000000009', 'year')" >/dev/null
refuses $DST "insert into pipeline.manual_locks(entity, entity_id, field) values ('course', '00000000-0000-0000-0000-000000000009', 'year')" 'a second manual lock on the same key (manual_locks_pkey)'
refuses $DST "set role anon; select count(*) from pipeline.admin_jobs" 'anon reading admin_jobs (grants)'
[ "$($P -At -d $DST -c "set role authenticated; select count(*) from pipeline.admin_jobs")" = 1 ] || fail 'authenticated read under RLS'
refuses $DST "set role anon; select security.pp_job_count('x')" 'anon executing security.pp_job_count (function grant)'
[ "$($P -At -d $DST -c "select md5(pg_get_functiondef('security.pp_job_count(text)'::regprocedure))")" = "$(node -e "console.log(require('$T/manifest.json').functions.find(f=>f.sig==='security.pp_job_count(text)').md5)")" ] || fail 'function md5'
echo 'PASS function definition md5 identical to the captured one'

# 4 the simplified fixture the intake releases used is caught
$P -d $SIMPLE >/dev/null <<'SQL'
create schema pipeline; create schema catalogue; create schema security;
create table pipeline.ops_outcome_codes (code text primary key, title text, counts_as_movement boolean);
create table pipeline.pp_operators (id uuid primary key, email text not null);
create table pipeline.admin_jobs (id bigint primary key, kind text not null, outcome text, requested_by uuid, created_at timestamptz not null default now(), attempts int not null default 0);
create table pipeline.manual_locks (entity text, entity_id uuid, field text, mode text, value jsonb, locked_at timestamptz default now());
create function security.pp_job_count(p_kind text) returns bigint language sql as $f$ select 0::bigint $f$;
SQL
$P -At -d $SIMPLE -f $T/check.sql > $T/simple.txt || true
for want in 'constraint|pipeline.admin_jobs|admin_jobs_outcome_fkey|missing' 'constraint|pipeline.manual_locks|manual_locks_pkey|missing' 'column|pipeline.manual_locks|mode|different' \
            'trigger|pipeline.manual_locks|manual_locks_touch|missing' 'policy|pipeline.admin_jobs|admin_jobs_read|missing' 'function|security.pp_job_count(text)|different' \
            'execute|security.pp_job_count(text)|different' 'table|pipeline.admin_jobs|different' 'lookup_rows|pipeline.ops_outcome_codes|different'; do
  grep -qF "$want" $T/simple.txt || { cat $T/simple.txt; fail "simplified fixture: $want not reported"; }
done
echo "PASS a simplified fixture is caught: $(grep -c . $T/simple.txt) differences, including admin_jobs_outcome_fkey and manual_locks_pkey"
[ "$($P -At -d $SIMPLE -f $T/digest.sql | cut -d'|' -f3)" = f ] || fail 'digest check did not flag the simplified fixture'
echo 'PASS the digest check flags the simplified fixture'
[ "$(rows $SIMPLE $T/compact.sql)" = "$(grep -c . $T/simple.txt)" ] || fail 'compact check does not list the same differences as the full check'
echo 'PASS the compact check lists the same differences as the full check'

# 6 committed production manifests
for m in $FX/manifests/*.json; do
  [ -e "$m" ] || continue
  node $TOOL verify "$m" >/dev/null || fail "$m does not verify"
  db=${PRODFX}; dropdb --if-exists $db; createdb $db
  node $TOOL fixture "$m" > $T/prod-fixture.sql
  $P -d $db -f $T/prod-fixture.sql 2>&1 | grep -v '^NOTICE' || true
  node $TOOL check-sql "$m" > $T/prod-check.sql
  $P -At -d $db -f $T/prod-check.sql > $T/prod-diff.txt
  # the local server cannot hold what only production has (PostgreSQL 17 MAINTAIN on 16, role-wide settings of other databases): listed as allowed
  allowed=$(node -e "const m=require('./$m'); console.log((m.local_allowed_differences||[]).join('\n'))")
  bad=$(grep -v -F -f <(printf '%s\n' "$allowed" | sed '/^$/d'; echo '__none__') $T/prod-diff.txt || true)
  [ -z "$bad" ] || { echo "$bad"; fail "$(basename $m): fixture differs from production"; }
  echo "PASS $(basename $m): verified, fixture built, check lists no unexpected difference ($(grep -c . $T/prod-diff.txt || true) allowed)"
  if [ "$(basename $m)" = intake-lessons-admin-jobs-manual-locks.json ]; then
    # the two operations production rejected in the intake releases are rejected here too
    refuses $db "insert into pipeline.admin_jobs(kind, title, requested_by, reason, outcome) values ('job_run_now', 't', gen_random_uuid(), 'r', 'run_now_queued')" \
      'production intake lesson: admin_jobs outcome run_now_queued is not a production outcome code (admin_jobs_outcome_fkey)'
    refuses $db "insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', gen_random_uuid(), 'year', 'hold')" \
      'production intake lesson: manual_locks mode must be value or removed (manual_locks_mode_check)'
    $P -d $db -c "insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', '00000000-0000-0000-0000-000000000009', 'year', 'value')" >/dev/null
    refuses $db "insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', '00000000-0000-0000-0000-000000000009', 'year', 'removed')" \
      'production intake lesson: one manual lock per entity, id and field (manual_locks_pkey)'
    $P -d $db -c "insert into pipeline.admin_jobs(kind, title, requested_by, reason, outcome) values ('job_run_now', 't', gen_random_uuid(), 'r', 'succeeded_with_result')" >/dev/null \
      || fail 'a production outcome code was refused'
    echo 'PASS accepts: admin_jobs job_run_now with production outcome succeeded_with_result'
  fi
done
echo 'prod-parity round trip: passed'
