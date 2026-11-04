#!/usr/bin/env bash
# Guards: PR #872 production preview timeout regression, isolated database only.
set -euo pipefail
cd "$(dirname "$0")/../../.."
bash tests/fixtures/intake-ui/run.sh
node tests/fixtures/intake-preview-timeout/regression.mjs
