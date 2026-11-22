#!/usr/bin/env bash
# CF-247 s980: prints the live migration head (max version in supabase_migrations.schema_migrations) of the project in $REF, read through the
# Supabase Management API. Read only. Needs SUPABASE_ACCESS_TOKEN and REF.
set -euo pipefail
r=$(curl -sS -X POST -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
  --data '{"query":"select max(version)::text as v from supabase_migrations.schema_migrations"}' \
  "https://api.supabase.com/v1/projects/$REF/database/query")
v=$(jq -r '.[0].v // empty' <<<"$r" 2>/dev/null || true)
if ! [[ "$v" =~ ^[0-9]{14}$ ]]; then echo "live-migration-head: could not read the head: ${r:0:200}" >&2; exit 1; fi
echo "$v"
