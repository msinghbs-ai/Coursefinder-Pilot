#!/usr/bin/env bash
# CF-247 Phase 3 (19 Oct 2026): apply ONE migration file to the project in $REF, with its history row, in one transaction through the
# Supabase Management API (exactly as a paste in the SQL editor). Shared by db-apply-migration (by hand) and deploy-on-merge (on merge).
# Refuses: a bad file name, a file that drops, deletes or truncates at top level (the Platform Admin pastes those), the history quote
# marker. Skips (exit 0) a version already in the history. After applying, the history row's md5 must equal the file's.
# Needs: SUPABASE_ACCESS_TOKEN, REF; argument: the file name under supabase/migrations.
set -euo pipefail
FILE="$1"
f="supabase/migrations/$FILE"
if ! [[ "$FILE" =~ ^[0-9]{14}_[a-z0-9_]+\.sql$ ]] || [ ! -f "$f" ]; then echo "::error::Refused file: $FILE"; exit 1; fi
if grep -nEi '^(drop|delete|truncate)\b|^alter table .* drop ' "$f"; then echo "::error::Refused: $FILE drops, deletes or truncates at top level; the Platform Admin pastes those"; exit 1; fi
if grep -q '\$mig\$' "$f"; then echo "::error::Refused: $FILE contains the history quote marker"; exit 1; fi
ver="${FILE:0:14}"; name="${FILE:15}"; name="${name%.sql}"
q() { jq -n --arg q "$1" '{query:$q}' > q.json; curl -sS -o r.json -w '%{http_code}' -X POST -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" --data @q.json "https://api.supabase.com/v1/projects/$REF/database/query"; }
code=$(q "select count(*)::int as n from supabase_migrations.schema_migrations where version='$ver'")
n=$(jq -r '.[0].n // "error"' r.json)
if [ "$code" -ge 300 ] || [ "$n" = "error" ]; then echo "::error::History unreadable ($code $(head -c 200 r.json))"; exit 1; fi
if [ "$n" != "0" ]; then echo "::notice::$FILE already applied (version $ver in the history); skipped"; exit 0; fi
{ printf 'begin;\n'; cat "$f"; printf '\n\ninsert into supabase_migrations.schema_migrations(version, name, statements) values (%s, %s, array[$mig$' "'$ver'" "'$name'"; cat "$f"; printf '$mig$]);\ncommit;\n'; } > apply.sql
jq -n --rawfile q apply.sql '{query:$q}' > q.json
code=$(curl -sS -o r.json -w '%{http_code}' -X POST -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" --data @q.json "https://api.supabase.com/v1/projects/$REF/database/query")
if [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then echo "::error::$FILE failed (HTTP $code): $(head -c 800 r.json | tr -d '\n')"; exit 1; fi
want=$(md5sum < "$f" | cut -c1-32)
q "select md5(replace(statements[1],E'\r','')) as m from supabase_migrations.schema_migrations where version='$ver'" > /dev/null
got=$(jq -r '.[0].m // "none"' r.json)
if [ "$got" != "$want" ]; then echo "::error::History md5 $got does not match the file $want"; exit 1; fi
echo "::notice::$FILE applied; history md5 ${want:0:8} matches the file"
echo "$FILE applied; history md5 ${want:0:8} matches the file" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
