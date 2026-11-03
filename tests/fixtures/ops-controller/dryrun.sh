#!/usr/bin/env bash
# CF-247 P0 workstream A: the controller's dry run on the live integration queue snapshot (see dryrun.sql). Scratch PostgreSQL only.
# Checks every snapshot row against the md5 read live with it, and the job map against its live md5, then builds a throwaway database the same
# way as run.sh and runs dryrun.sql. OPS_DRY_KEEP=1 keeps the database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
FX=tests/fixtures/ops-controller
DB=${OPS_DRY_DB:-ops_controller_dryrun}
P="psql -v ON_ERROR_STOP=1 -q -X"
python3 -I - "$FX/live/issues-20261103-1556.jsonl" <<'PY'
import json, hashlib, sys
keys = ['id','fp','title','sub','src','vl','rcc','sev','st','rc','reg','det','obs','clr','cls','msg','fail']
rows = [json.loads(l) for l in open(sys.argv[1])]
bad = [r['id'] for r in rows if hashlib.md5('|'.join(str(r[k]) for k in keys if r[k] is not None).encode()).hexdigest() != r['h']]
if bad or len(rows) != 68: sys.exit(f'snapshot rows differ from live: {bad} ({len(rows)} rows)')
print('snapshot: 68 rows, each = its live md5')
PY
[ "$(printf '%s' "$(cat $FX/live/cron-jobs-20261103-1607.txt)" | md5sum | cut -c1-32)" = 23bce9d864d4926cc6f2de6bb1c45fa4 ] || { echo "job map differs from live"; exit 1; }
echo "job map: 157 jobs = live md5"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPS_DRY_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>/dev/null
$P -d $DB -f $FX/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>/dev/null
$P -d $DB -f $FX/dryrun.sql
