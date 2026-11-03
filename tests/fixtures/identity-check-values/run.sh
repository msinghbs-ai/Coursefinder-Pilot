#!/usr/bin/env bash
# CF-247 SS-021 F2 (IQ-00077): provider-identity-check issue values, on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase project).
# Builds the workstream G fixture database (its live definitions are checked against their live md5s there), adds the live check constraints of
# pipeline.integration_issues (read 3 Nov 2026 22:10 AEDT), then: R1 the live definition fails the run on its own issue write; the migration
# applies (after-md5 checked by the migration) and a second run changes nothing; R2 the run succeeds and writes issues with accepted values;
# R3 a refused issue write is recorded in the result and the run's findings stay. Drops its database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=identity_check_values_fixtures
MIG=../../../supabase/migrations/20261104180000_cf247_identity_check_issue_values.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
q() { $P -d $DB -Atc "$1"; }
OPSG_KEEP=1 OPSG_DB=$DB bash ../ops-provider-lifecycle/run.sh >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
q "update pipeline.integration_issues set workstream = null where workstream is not null and workstream not in ('A1','A2','A3','A4','A5','A6','A7','A8','A9','A10')"
q "alter table pipeline.integration_issues add constraint integration_issues_workstream_check check (workstream = any (array['A1','A2','A3','A4','A5','A6','A7','A8','A9','A10']))"
q "update pipeline.platform_toolset_settings set value = to_jsonb(1) where key in ('identity.check_on', 'identity.issue_on')"
q "delete from pipeline.integration_issues where fingerprint like 'provider_identity:%'"
[ "$(q "select count(*) from pipeline.provider_identity_findings")" -gt 0 ] || { echo "the fixture holds no findings to report"; exit 1; }
# R1: before, the run's own issue write is refused and the whole run rolls back
if q "select security.provider_identity_check_v1()" >/dev/null 2>&1; then echo "R1: the live definition did not fail"; exit 1; fi
echo "R1 ok: the live definition fails the run on its issue write"
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -3; exit 1; }
echo "$OUT" | grep -q ': applied$' || { echo "$OUT" | tail -3; exit 1; }
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -3; exit 1; }
echo "$OUT" | grep -q ': already applied$' || { echo "second run: $OUT" | tail -3; exit 1; }
echo "migration: applied, second run changes nothing"
R=$(q "select security.provider_identity_check_v1()")
N=$(q "select count(*) from pipeline.integration_issues where fingerprint like 'provider_identity:%' and workstream = 'A10'")
[ "$N" -gt 0 ] || { echo "R2: no issue written ($R)"; exit 1; }
echo "R2 ok: run succeeds; $N issues written with workstream A10"
q "delete from pipeline.integration_issues where fingerprint like 'provider_identity:%'"
q "alter table pipeline.integration_issues drop constraint integration_issues_workstream_check"
q "alter table pipeline.integration_issues add constraint integration_issues_workstream_check check (workstream <> 'A10')"
R=$(q "select security.provider_identity_check_v1()")
echo "$R" | grep -q 'issue not written' || { echo "R3: refused write not recorded ($R)"; exit 1; }
[ "$(q "select count(*) from pipeline.provider_identity_findings where state = 'open'")" -gt 0 ] || { echo "R3: findings rolled back"; exit 1; }
echo "R3 ok: a refused issue write is recorded and the run's findings stay"
echo "all identity check value fixtures passed"
