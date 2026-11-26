#!/usr/bin/env bash
# CF-247 s880 (Platform Admin 20 Nov 2026 17:00; one-off checks report without failing, s881): merge a pull request labelled `automerge` once it is mergeable and every check is green,
# then delete its branch. Used by .github/workflows/auto-merge.yml in this repository and, byte for byte, in coursefinder-admin.
#
#   PR=<number> MODE=wait|once REPO=<owner/name> scripts/ci/auto-merge.sh
#
# "Green" (there is no branch protection, so the script decides): every latest check run on the head commit has finished as success,
# skipped or neutral (this workflow's own runs aside), the commit status is not failing or pending, and at least MIN_CHECKS checks exist.
# A pull request that adds a migration also needs the `live-dry-run` label and a successful `dry-run` check (merge on green CI plus a
# rolled-back live dry run). A cancelled check is re-run once and waited on; a failed one stops the wait with a comment.
#
# A merge made with the workflow's GITHUB_TOKEN does not start the push-to-main workflows, so POST_MERGE=pilot starts them here:
# Deploy on merge (with the exact before/after commits) when migrations or edge functions changed, Security gates, Deployed UAT, and
# Release Currentness Deployed when release files changed. POST_MERGE=admin starts Security gates.
#
# s1285 (Keep Main Green P0, SS-Programme-Control 26 Nov 2026 23:58 AEDT): REQUIRED_CHECKS names the checks that must have passed on the exact head
# (separated by ';', because check names hold commas; empty names none, MIN_CHECKS still applies). MAIN_UAT_WORKFLOW names the deployed UAT workflow of main: while its latest run on
# main is running, a merge waits (one release at a time, so each merge gets its own deployed verification); while it failed, only a pull request
# labelled MAIN_FIX_LABEL (main-green-fix) may merge, to restore main. Empty (as in coursefinder-admin) checks nothing.
set -euo pipefail

: "${REPO:?}" "${PR:?}"
MODE="${MODE:-wait}"
LABEL="${LABEL:-automerge}"
SELF="${SELF_CHECK:-auto-merge}"
MIN_CHECKS="${MIN_CHECKS:-3}"
WAIT_MINUTES="${WAIT_MINUTES:-120}"   # fixed: the longest CI path (test evidence with one re-run) is under two hours
POLL_SECONDS="${POLL_SECONDS:-60}"    # fixed: one poll a minute keeps several waiting pull requests inside the token's hourly API limit
POST_MERGE="${POST_MERGE:-none}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
RERUN=""
REQUIRED="${REQUIRED_CHECKS:-}"
MAIN_UAT="${MAIN_UAT_WORKFLOW:-}"
FIX_LABEL="${MAIN_FIX_LABEL:-main-green-fix}"

say() { echo "$1"; echo "- $1" >> "$SUMMARY"; }
comment() { gh api "repos/$REPO/issues/$PR/comments" -f body="$1" >/dev/null 2>&1 || true; }
# a stop: the waiting run (MODE=wait) comments once and fails; a one-off check (MODE=once, run on every finished check suite) only reports
stop() { say "$1"; if [ "$MODE" = wait ]; then comment "$2"; exit 1; fi; exit 0; }

deadline=$(( $(date +%s) + WAIT_MINUTES * 60 ))
[ "$MODE" = wait ] && sleep 30   # fixed: let the checks of a new push register before the first look

while :; do
  pr=$(gh api "repos/$REPO/pulls/$PR")
  if [ "$(jq -r .merged <<<"$pr")" = true ]; then say "#$PR is already merged."; exit 0; fi
  if [ "$(jq -r .state <<<"$pr")" != open ]; then say "#$PR is closed; nothing to do."; exit 0; fi
  if ! jq -e --arg l "$LABEL" '[.labels[].name] | index($l) != null' <<<"$pr" >/dev/null; then say "#$PR has no \`$LABEL\` label; nothing to do."; exit 0; fi
  if [ "$(jq -r '.head.repo.full_name == .base.repo.full_name' <<<"$pr")" != true ]; then say "#$PR comes from a fork; it is not merged automatically."; exit 0; fi
  if [ "$(jq -r .base.ref <<<"$pr")" != main ]; then say "#$PR does not target main; it is not merged automatically."; exit 0; fi
  head=$(jq -r .head.sha <<<"$pr"); ref=$(jq -r .head.ref <<<"$pr"); title=$(jq -r .title <<<"$pr")
  mergeable=$(jq -r .mergeable <<<"$pr"); mstate=$(jq -r .mergeable_state <<<"$pr")
  if [ "$mergeable" = false ] || [ "$mstate" = dirty ]; then
    stop "#$PR has merge conflicts with main." "Auto-merge stopped: this pull request conflicts with \`main\`. Update the branch; the next push starts the wait again." 
  fi

  runs=$(gh api "repos/$REPO/commits/$head/check-runs?per_page=100&filter=latest" --jq "[.check_runs[] | select(.name != \"$SELF\")]")
  total=$(jq length <<<"$runs")
  pending=$(jq -r '[.[] | select(.status != "completed") | .name] | join(", ")' <<<"$runs")
  failed=$(jq -r '[.[] | select(.status == "completed" and (.conclusion | IN("failure", "timed_out", "action_required", "startup_failure", "stale"))) | .name] | join(", ")' <<<"$runs")
  cancelled=$(jq -r '[.[] | select(.conclusion == "cancelled") | .name] | join(", ")' <<<"$runs")
  status=$(gh api "repos/$REPO/commits/$head/status" --jq '.state + " " + (.total_count | tostring)')
  sstate=${status% *}; scount=${status#* }

  need_dry=no
  if gh api "repos/$REPO/pulls/$PR/files?per_page=100" --paginate --jq '.[] | select(.status == "added") | .filename' | grep -qE '^supabase/migrations/[^/]+\.sql$'; then need_dry=yes; fi
  dry_ok=yes
  if [ "$need_dry" = yes ]; then
    if ! jq -e '[.labels[].name] | index("live-dry-run") != null' <<<"$pr" >/dev/null; then dry_ok="missing the live-dry-run label"
    elif [ "$(jq -r '[.[] | select(.name == "dry-run" and .conclusion == "success")] | length' <<<"$runs")" = 0 ]; then dry_ok="no successful rolled-back dry run yet"; fi
  fi

  missing=""
  if [ -n "$REQUIRED" ]; then
    IFS=';' read -ra req <<<"$REQUIRED"
    for n in "${req[@]}"; do
      [ "$(jq -r --arg n "$n" '[.[] | select(.name == $n and (.conclusion | IN("success", "neutral")))] | length' <<<"$runs")" = 0 ] && missing="${missing:+$missing, }$n"
    done
  fi
  main_ok=yes
  if [ -n "$MAIN_UAT" ]; then
    m=$(gh api "repos/$REPO/actions/workflows/$MAIN_UAT/runs?branch=main&per_page=10" \
          --jq '[.workflow_runs[] | select(.conclusion != "cancelled" and .conclusion != "skipped")] | first | if . == null then "" else (.status + " " + (.conclusion // "none")) end')
    case "$m" in
      ""|"completed success") ;;
      completed\ *) jq -e --arg l "$FIX_LABEL" '[.labels[].name] | index($l) != null' <<<"$pr" >/dev/null || main_ok="main is red (latest $MAIN_UAT on main: ${m#completed })" ;;
      *) main_ok="the deployed check of main is still running" ;;
    esac
  fi

  if [ -n "$failed" ] || [ "$sstate" = failure ] || [ "$sstate" = error ]; then
    stop "#$PR has failing checks: ${failed:-commit status $sstate}." "Auto-merge stopped: failing checks (${failed:-commit status $sstate}). Fix and push; the next push starts the wait again." 
  fi
  if [ -z "$pending" ] && [ -z "$cancelled" ] && [ "$total" -ge "$MIN_CHECKS" ] && { [ "$sstate" = success ] || [ "$scount" = 0 ]; } \
     && [ "$dry_ok" = yes ] && [ "$mergeable" = true ] && [ -z "$missing" ] && [ "$main_ok" = yes ]; then
    break
  fi
  # a cancelled check is usually a concurrency cancel (adding a label starts a run that cancels the running one, then skips): re-run, once each,
  # every workflow on this head whose latest real run was cancelled and that has nothing newer queued or running
  if [ -n "$cancelled" ] && [ "$MODE" = wait ]; then
    for id in $(gh api "repos/$REPO/actions/runs?head_sha=$head&per_page=100" --jq '.workflow_runs | group_by(.workflow_id)[]
                 | (map(select(.conclusion != "skipped")) | sort_by(.created_at) | last) as $l
                 | select($l != null and $l.conclusion == "cancelled" and (map(select(.status != "completed")) | length) == 0) | $l.id'); do
      case " $RERUN " in *" $id "*) continue ;; esac
      RERUN="$RERUN $id"
      if gh api -X POST "repos/$REPO/actions/runs/$id/rerun" >/dev/null 2>&1; then say "Re-ran cancelled run $id."; fi
    done
  fi
  why="checks $total (min $MIN_CHECKS); required missing: ${missing:-none}; main: $main_ok; pending: ${pending:-none}; cancelled: ${cancelled:-none}; status: $sstate/$scount; dry run: $dry_ok; mergeable: $mergeable"
  if [ "$MODE" = once ] || [ "$(date +%s)" -ge "$deadline" ]; then
    say "#$PR not merged yet ($why)."
    [ "$MODE" = wait ] && comment "Auto-merge waited ${WAIT_MINUTES} minutes and stopped: $why. Re-add the \`$LABEL\` label (or push) to wait again."
    exit 0
  fi
  echo "waiting: $why"; sleep "$POLL_SECONDS"
done

# merge (the head sha guard refuses a merge if a new commit arrived since the checks were read)
if ! res=$(gh api -X PUT "repos/$REPO/pulls/$PR/merge" -f merge_method=squash -f sha="$head" -f commit_title="$title (#$PR)" 2>&1); then
  if [ "$(gh api "repos/$REPO/pulls/$PR" --jq .merged)" = true ]; then say "#$PR was merged by another run."; exit 0; fi
  say "#$PR merge refused: $res"; exit 1
fi
msha=$(jq -r .sha <<<"$res")
say "#$PR squash-merged as ${msha:0:9}."
if gh api -X DELETE "repos/$REPO/git/refs/heads/$ref" >/dev/null 2>&1; then say "Branch \`$ref\` deleted."; else say "Branch \`$ref\` was already gone."; fi

# the push-to-main workflows do not start for a GITHUB_TOKEN merge; start them here
before=$(gh api "repos/$REPO/commits/$msha" --jq '.parents[0].sha')
files=$(gh api "repos/$REPO/compare/$before...$msha" --jq '.files[].filename')
dispatch() { if gh api -X POST "repos/$REPO/actions/workflows/$1/dispatches" -f ref=main "${@:2}" >/dev/null; then say "Started $1."; else say "Could not start $1."; fi; }
case "$POST_MERGE" in
  pilot)
    if grep -qE '^supabase/(migrations/[^/]+\.sql|functions/)' <<<"$files"; then
      dispatch deploy-on-merge.yml -f "inputs[before]=$before" -f "inputs[after]=$msha"
    else say "No migration or edge function changed; Deploy on merge not needed."; fi
    dispatch security-gates.yml
    sleep 120   # fixed: the Worker build of the merge commit settles before the deployed checks (the push runs waited the same way)
    if grep -qE '^(src/release-manifest\.js|src/ReleaseNotes\.jsx|src/release-history-legacy\.js|src/mature-main\.jsx|index\.html|package\.json|CHANGELOG\.md)$' <<<"$files"; then
      dispatch release-currentness-deployed.yml
    fi
    dispatch deployed-uat.yml
    ;;
  admin) dispatch security-gates.yml ;;
esac
