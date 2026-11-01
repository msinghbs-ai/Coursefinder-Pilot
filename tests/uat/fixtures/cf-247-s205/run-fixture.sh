#!/usr/bin/env bash
# CF-247 UR-18 slice 1: runs the isolated fixture on a LOCAL throwaway Postgres (never a Supabase project).
# Usage: PGHOST=<socket dir or host> PGPORT=<port> PGUSER=postgres tests/uat/fixtures/cf-247-s205/run-fixture.sh
# Creates database ur18_fixture, loads schema.sql, the live "before" definitions, the migration and cases.sql, and writes result.txt
# (migration md5, after md5s of the two edited functions, each case's PASS line). It refuses a host that looks like Supabase.
set -euo pipefail
cd "$(dirname "$0")/../../../.."
case "${PGHOST:-}" in *supabase*|*pooler*) echo "refused: run the fixture on a local Postgres only" >&2; exit 1;; esac
F=tests/uat/fixtures/cf-247-s205
M=supabase/migrations/20261102020000_cf247_ur18_bulk_review_slice1.sql
P="psql -X -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists ur18_fixture" -c "create database ur18_fixture"
$P -d ur18_fixture -f $F/schema.sql -f $F/layer4_review_decide_impl.before.sql -f $F/admin_layer4_inbox.before.sql
before=$($P -d ur18_fixture -Atc "select md5(pg_get_functiondef('security.layer4_review_decide_impl(uuid,text,text,jsonb)'::regprocedure))||' '||md5(pg_get_functiondef('public.admin_layer4_inbox(text,jsonb)'::regprocedure))")
$P -d ur18_fixture -f $M >/dev/null 2>&1
$P -d ur18_fixture -f $M >/dev/null   2>&1  # a second run changes nothing (already applied)
after=$($P -d ur18_fixture -Atc "select md5(pg_get_functiondef('security.layer4_review_decide_impl(uuid,text,text,jsonb)'::regprocedure))||' '||md5(pg_get_functiondef('public.admin_layer4_inbox(text,jsonb)'::regprocedure))")
if ! log=$($P -d ur18_fixture -f $F/cases.sql 2>&1); then echo "$log" | grep -E 'ERROR|FAIL|PASS' >&2; exit 1; fi
out=$(echo "$log" | grep -E '^(seed|PASS|ALL)')
{
  echo "migration md5: $(md5sum < $M | cut -c1-32)"
  echo "before md5 (decide_impl, inbox): $before"
  echo "after md5 (decide_impl, inbox): $after"
  echo "postgres: $($P -d postgres -Atc 'show server_version')"
  echo "$out"
} | tee $F/result.txt
$P -d postgres -c "drop database ur18_fixture"
