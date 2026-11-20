#!/usr/bin/env bash
# CF-247 s880 (Platform Admin 20 Nov 2026 17:00): no throwaway probe branch is left behind.
#  1 After a rolled-back dry run started by hand (workflow_dispatch) finishes on a branch whose name ends in -probe or -diag, that branch is
#    deleted, unless a pull request is open from it or a newer commit arrived after the run started (then the next run cleans it).
#  2 Sweep: any other branch whose name ends in -probe, with no open pull request and no commit for SWEEP_HOURS, is deleted.
# Every deleted branch is listed with its last commit in the run summary, so it can be restored (git push origin <sha>:refs/heads/<name>).
#   REPO=<owner/name> BRANCH=<run branch> RUN_SHA=<run head sha> scripts/ci/probe-branch-cleanup.sh
set -euo pipefail
: "${REPO:?}"
BRANCH="${BRANCH:-}"; RUN_SHA="${RUN_SHA:-}"
SWEEP_HOURS="${SWEEP_HOURS:-24}"   # fixed: a probe branch idle for a day is finished with
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
owner=${REPO%%/*}
say() { echo "$1"; echo "- $1" >> "$SUMMARY"; }
open_pr() { [ "$(gh api "repos/$REPO/pulls?state=open&head=$owner:$1" --jq length)" != 0 ]; }
delete() { if gh api -X DELETE "repos/$REPO/git/refs/heads/$1" >/dev/null 2>&1; then say "Deleted \`$1\` (last commit $2)."; else say "Could not delete \`$1\`."; fi; }

if [ -n "$BRANCH" ] && [ "$BRANCH" != main ] && [[ "$BRANCH" =~ -(probe|diag)$ ]]; then
  cur=$(gh api "repos/$REPO/branches/$BRANCH" --jq .commit.sha 2>/dev/null || true)
  if [ -z "$cur" ]; then say "\`$BRANCH\` is already gone."
  elif open_pr "$BRANCH"; then say "\`$BRANCH\` has an open pull request; kept."
  elif [ -n "$RUN_SHA" ] && [ "$cur" != "$RUN_SHA" ]; then say "\`$BRANCH\` has a newer commit than the run; kept for its next run."
  else delete "$BRANCH" "$cur"; fi
fi

cutoff=$(date -u -d "-$SWEEP_HOURS hours" +%s)
gh api "repos/$REPO/branches?per_page=100" --paginate --jq '.[] | select(.name | test("-probe$")) | "\(.name) \(.commit.sha)"' | while read -r name sha; do
  [ "$name" = "$BRANCH" ] && continue
  when=$(gh api "repos/$REPO/commits/$sha" --jq '.commit.committer.date')
  [ "$(date -u -d "$when" +%s)" -gt "$cutoff" ] && continue
  if open_pr "$name"; then say "\`$name\` has an open pull request; kept."; continue; fi
  delete "$name" "$sha"
done
