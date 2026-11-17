#!/usr/bin/env bash
# CF-247 S1-Build (Platform Admin 17 Nov 2026 18:25): the rolled-back live dry run of ONE migration file, run by GitHub Actions through the
# Supabase Management API so no person has to answer a confirmation prompt. The file runs inside BEGIN on the project in $REF, then an
# exception (CF-DRYRUN-ROLLED-BACK) ends the transaction, so nothing it did is kept: no history row, no object, no row. The dry run passes only
# when the reply carries that exception (the file and its own post-checks ran to the end); any other error fails it.
# Refuses: a bad file name, a file with its own BEGIN, COMMIT or ROLLBACK, or with CONCURRENTLY (cannot run in a transaction).
# Needs: SUPABASE_ACCESS_TOKEN, REF; argument: the file name under supabase/migrations. Optional: PROBE, one SQL expression whose value is
# printed with the result (it runs after the file, inside the same rolled-back transaction).
set -euo pipefail
FILE="$1"
f="supabase/migrations/$FILE"
if ! [[ "$FILE" =~ ^[0-9]{14}_[a-z0-9_]+\.sql$ ]] || [ ! -f "$f" ]; then echo "::error::Refused file: $FILE"; exit 1; fi
# outside dollar-quoted bodies (a procedure may COMMIT inside its own body)
outside=$(perl -0777 -pe 's/(\$[A-Za-z_]*\$).*?\1//gs' "$f")
if grep -nEi '^\s*(begin|commit|rollback|end)\s*;' <<< "$outside"; then echo "::error::Refused: $FILE ends or opens its own transaction"; exit 1; fi
if grep -nEi '\bconcurrently\b' "$f"; then echo "::error::Refused: $FILE uses CONCURRENTLY, which cannot run in the dry run's transaction"; exit 1; fi
if grep -q 'cf_dryrun' "$f"; then echo "::error::Refused: $FILE contains the dry run's marker"; exit 1; fi
probe="${PROBE:-}"
[ -n "$probe" ] || probe="'no probe'"
{
  printf "begin;\nset local statement_timeout = '%s';\n" "${DRYRUN_STATEMENT_TIMEOUT:-60s}"
  cat "$f"
  printf "\n\ndo \$cf_dryrun\$ begin raise exception 'CF-DRYRUN-ROLLED-BACK %%', (%s)::text; end \$cf_dryrun\$;\nrollback;\n" "$probe"
} > dryrun.sql
jq -n --rawfile q dryrun.sql '{query:$q}' > q.json
code=$(curl -sS -o r.json -w '%{http_code}' -X POST -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
  --data @q.json "https://api.supabase.com/v1/projects/$REF/database/query")
msg=$(head -c 4000 r.json | tr -d '\n')
if grep -q 'CF-DRYRUN-ROLLED-BACK' r.json; then
  echo "::notice::$FILE dry run passed and was rolled back (md5 $(md5sum < "$f" | cut -c1-8))"
  printf '%s dry run passed, rolled back (md5 %s)\n\n```\n%s\n```\n' "$FILE" "$(md5sum < "$f" | cut -c1-8)" "$msg" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  echo "$msg"
  exit 0
fi
echo "::error::$FILE dry run failed (HTTP $code): ${msg:0:800}"
printf '%s dry run FAILED (HTTP %s)\n\n```\n%s\n```\n' "$FILE" "$code" "$msg" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit 1
