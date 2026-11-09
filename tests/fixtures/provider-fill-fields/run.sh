#!/usr/bin/env bash
# Guards: Fill fields (Platform Admin 9-10 Nov 2026) and G4 database-backed tests: migration 20261110030000 on an isolated PostgreSQL (fixtures only, never a Supabase project).
# Needs a scratch PostgreSQL 16 reachable with PGHOST/PGPORT/PGUSER (a unix socket or 127.0.0.1). Builds a throwaway database: the stub schema, the LIVE text of the facts function, the earlier page function
# and the earlier Run & Validate service (extracted from the migrations that wrote them, so the md5 guards of the new migration are checked against the real text), the earlier registry rows, the seed,
# then the migration, then the migration again (idempotent: same rows, same function bodies), then fixtures.sql (behaviour). Drops the database at the end (FILL_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/lib/postgresql/*) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
DB=${FILL_DB:-g_provider_fill_fields}
FX=tests/fixtures/provider-fill-fields
MIG=supabase/migrations/20261110030000_cf247_provider_fill_fields.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; [ -n "${FILL_KEEP:-}" ] || $P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d $DB -f $FX/schema.sql >/dev/null
python3 $FX/extract.py $TMP >/dev/null
for f in facts page_live page_before run_live run_before; do PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $TMP/$f.sql >/dev/null; done
# the registry rows of the Provider Catalogue's earlier columns change (32 of 34 columns), exactly as written by the earlier migration
python3 - "$TMP/columns.sql" <<'PY'
import sys
t = open('supabase/migrations/20261109200000_cf247_provider_catalogue_columns.sql').read()
i = t.index('insert into pipeline.admin_table_columns')
j = t.index('on conflict (screen, key) do nothing;', i) + len('on conflict (screen, key) do nothing;')
open(sys.argv[1], 'w').write(t[i:j] + '\n')
PY
$P -d $DB -f $TMP/columns.sql >/dev/null
echo "earlier registry rows: $($P -d $DB -Atc "select count(*) from pipeline.admin_table_columns where screen = 'providers'") (32 expected)"
$P -d $DB -f $FX/seed.sql >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $MIG >/dev/null
snap="select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from pipeline.admin_table_columns) || '/' || (select count(*) from pipeline.component_register) || '/' || (select md5(prosrc) from pg_proc where oid = 'security.admin_providers_page_v3(jsonb)'::regprocedure) || '/' || (select md5(prosrc) from pg_proc where oid = 'public.admin_provider_description_run_v1(text,jsonb)'::regprocedure)"
before=$($P -d $DB -Atc "$snap")
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $MIG >/dev/null
after=$($P -d $DB -Atc "$snap")
[ "$before" = "$after" ] || { echo "re-run changed rows or bodies: $before -> $after"; exit 1; }
echo "migration applied twice: settings/columns/register/page/run $after (unchanged on re-run)"
# the guard refuses a body it does not know
$P -d $DB -c "update pg_proc set prosrc = prosrc || ' ' where oid = 'security.provider_catalogue_facts_v1(uuid[],boolean)'::regprocedure" >/dev/null
if PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $MIG >/dev/null 2>$TMP/guard.err; then echo 'FAILED: the migration ran over a facts function it does not know'; exit 1; fi
grep -q 'differs from the definition this change reads' $TMP/guard.err || { cat $TMP/guard.err; echo 'FAILED: the guard did not name the facts function'; exit 1; }
echo "guard: refused to run over an unknown facts function"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $TMP/facts.sql >/dev/null
out=$($P -d $DB -f $FX/fixtures.sql 2>&1) || { echo "$out" | grep -E 'FAILED|ERROR' ; exit 1; }
echo "$out" | grep 'NOTICE:  ok:' | sed 's/^[^N]*NOTICE:  //'
echo "assertions passed: $(echo "$out" | grep -c 'NOTICE:  ok:')"
# forward recovery (held, not a migration): puts the two earlier bodies back byte for byte, is repeatable, and the migration can then be applied again
REC=supabase/held/provider_fill_fields_forward_recovery.sql
md5s="select (select md5(prosrc) from pg_proc where oid = 'security.admin_providers_page_v3(jsonb)'::regprocedure) || '/' || (select md5(prosrc) from pg_proc where oid = 'public.admin_provider_description_run_v1(text,jsonb)'::regprocedure)"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $REC >/dev/null
[ "$($P -d $DB -Atc "$md5s")" = "f3eb9fc6f8efa37566c36ac5ef2e8f0e/b397cf320a689b6e981aa6747e7156b8" ] || { echo 'FAILED: the recovery did not restore the earlier bodies'; exit 1; }
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $REC >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $MIG >/dev/null
echo "forward recovery: earlier bodies restored byte for byte, repeatable, and the migration applies again ($($P -d $DB -Atc "$md5s"))"
