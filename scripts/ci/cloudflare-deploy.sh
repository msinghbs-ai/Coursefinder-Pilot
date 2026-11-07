#!/usr/bin/env bash
# CF-247 / D-382: the ONLY Deploy command of the Git-connected Cloudflare Workers Build (production branch main).
# Cloudflare field value: bash scripts/ci/cloudflare-deploy.sh
# It publishes only when the controller guard passes for this exact commit; every other outcome stops before wrangler.
set -euo pipefail
# fixed: the guard is fetched by commit and verified by digest so a later edit of the repository cannot weaken it unnoticed;
# fixed: change both only with the Platform Admin's decision recorded in Admin #382.
guard_commit=1e7eaabecf5e2ae2f644644c62e0e23ffe32e02d
guard_sha256=cfa06ba903d4849fba714e772b52e7e67b5ecf1c5a7d838ca8c2c46e61209cc9
commit="${WORKERS_CI_COMMIT_SHA:?BLOCKED: not a Cloudflare Workers Build commit}"
guard_file=$(mktemp)
trap 'rm -f "$guard_file"' EXIT
curl --fail --silent --show-error --max-time 30 \
  "https://raw.githubusercontent.com/msinghbs-ai/Coursefinder-Pilot/${guard_commit}/scripts/ci/controller-guard.py" > "$guard_file"
printf '%s  %s\n' "$guard_sha256" "$guard_file" | sha256sum --check --status || { echo 'BLOCKED: controller guard digest mismatch' >&2; exit 1; }
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then git fetch --no-tags --unshallow origin; fi
[ "$(git rev-parse HEAD)" = "$commit" ] || { echo 'BLOCKED: checked-out commit differs from the build commit' >&2; exit 1; }
python3 "$guard_file" --entry-point cloudflare-frontend --commit "$commit"
exec npx wrangler deploy
