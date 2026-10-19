#!/usr/bin/env bash
# CF-247 Phase 3 (19 Oct 2026): deploy ONE edge function from this repository to the project in $REF, with the verify_jwt recorded in
# .github/edge-functions.json. Refuses a function that is not listed there or has no index.ts. Shared by deploy-edge-functions (by
# hand) and deploy-on-merge (on merge). Needs: SUPABASE_ACCESS_TOKEN, REF, the supabase CLI; argument: the function name.
set -euo pipefail
fn="$1"
if ! [[ "$fn" =~ ^[a-z0-9-]+$ ]]; then echo "::error::Refused: $fn"; exit 1; fi
# 19 Oct 2026: "has" not "//": jq's // treats false as missing, which refused every function deployed with verify_jwt false
v=$(jq -r --arg f "$fn" 'if (.functions | has($f)) then (.functions[$f] | tostring) else "missing" end' .github/edge-functions.json)
if [ "$v" = "missing" ]; then echo "::error::Refused: $fn is not in .github/edge-functions.json"; exit 1; fi
if [ ! -f "supabase/functions/$fn/index.ts" ]; then echo "::error::Missing supabase/functions/$fn/index.ts"; exit 1; fi
flag=""; [ "$v" = "false" ] && flag="--no-verify-jwt"
echo "Deploying $fn (verify_jwt=$v)"
supabase functions deploy "$fn" --project-ref "$REF" $flag
echo "$fn deployed (verify_jwt=$v)" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
