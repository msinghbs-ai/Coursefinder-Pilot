// Guards: CF-247 s870 (Platform Admin 20 Nov 2026 17:00, chat S1-Build): a pull request labelled `automerge` merges itself on green checks
// (and, for a migration, a passing rolled-back dry run), its branch is deleted, the push-to-main workflows are started for it, and throwaway
// probe branches are cleaned up; CLAUDE.md tells every session to merge this way and never ask a person to merge
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const wf = fs.readFileSync('.github/workflows/auto-merge.yml', 'utf8')
const merge = fs.readFileSync('scripts/ci/auto-merge.sh', 'utf8')
const probe = fs.readFileSync('scripts/ci/probe-branch-cleanup.sh', 'utf8')
const deploy = fs.readFileSync('.github/workflows/deploy-on-merge.yml', 'utf8')
const rules = fs.readFileSync('CLAUDE.md', 'utf8')

test('the workflow runs on the label, new pushes, finished check suites and hand-started dry runs', () => {
  expect(wf).toContain('    types: [labeled, synchronize, reopened]')
  expect(wf).toContain('  check_suite:\n    types: [completed]')
  expect(wf).toContain('    workflows: ["Database migration dry run (rolled back)"]')
  expect(wf).toContain("contains(github.event.pull_request.labels.*.name, 'automerge')")
  expect(wf).toContain('github.event.pull_request.head.repo.full_name == github.repository')
  for (const p of ['contents: write', 'pull-requests: write', 'actions: write']) expect(wf).toContain(p)
  expect(wf).toContain('POST_MERGE: pilot')
  expect(wf).toContain('run: bash scripts/ci/probe-branch-cleanup.sh')
})

test('green means every check finished well, the dry run passed for a migration, and the branch is mergeable', () => {
  expect(merge).toContain('select(.status == "completed" and (.conclusion | IN("failure", "timed_out", "action_required", "startup_failure", "stale")))')
  expect(merge).toContain("grep -qE '^supabase/migrations/[^/]+\\.sql$'")
  expect(merge).toContain('select(.name == "dry-run" and .conclusion == "success")')
  expect(merge).toContain('[ "$total" -ge "$MIN_CHECKS" ]')
  expect(merge).toContain('if [ "$mergeable" = false ] || [ "$mstate" = dirty ]; then')
  expect(merge).toContain('-f merge_method=squash -f sha="$head"')
  expect(merge).toContain('gh api -X DELETE "repos/$REPO/git/refs/heads/$ref"')
})

test('after a merge the push-to-main workflows are started, Deploy on merge with the exact commits', () => {
  expect(merge).toContain('dispatch deploy-on-merge.yml -f "inputs[before]=$before" -f "inputs[after]=$msha"')
  for (const w of ['security-gates.yml', 'deployed-uat.yml', 'release-currentness-deployed.yml']) expect(merge).toContain(`dispatch ${w}`)
  expect(deploy).toMatch(/on:\n  push:\n    branches: \[main\]/)
  expect(deploy).toContain("BEFORE: ${{ github.event_name == 'workflow_dispatch' && inputs.before || github.event.before }}")
  expect(deploy).toContain("AFTER: ${{ github.event_name == 'workflow_dispatch' && inputs.after || github.sha }}")
  expect(deploy).toContain('if ! git merge-base --is-ancestor "$AFTER" HEAD; then')
  expect(deploy).toContain("if: github.ref == 'refs/heads/main'")
})

test('probe branches: deleted after their dry run, idle ones swept, never one with an open pull request or a newer commit', () => {
  expect(probe).toContain('[[ "$BRANCH" =~ -(probe|diag)$ ]]')
  expect(probe).toContain('select(.name | test("-probe$"))')
  expect(probe).toContain('elif open_pr "$BRANCH"; then')
  expect(probe).toContain('elif [ -n "$RUN_SHA" ] && [ "$cur" != "$RUN_SHA" ]; then')
  // a real branch that only contains the word is not a probe
  expect('cf247-drop-probe-fix-specs').not.toMatch(/-probe$/)
})

test('both scripts parse', () => {
  for (const f of ['scripts/ci/auto-merge.sh', 'scripts/ci/probe-branch-cleanup.sh']) execFileSync('bash', ['-n', f])
})

test('CLAUDE.md: never ask a person to merge; admin first, then Pilot, by the automerge label', () => {
  expect(rules).toContain('Never stop and ask the user to merge a pull request or delete a branch.')
  expect(rules).toContain('Merge the `coursefinder-admin` pull request before the Pilot one.')
  expect(rules).toContain('gh pr merge <n> --auto --squash --delete-branch')
  expect(rules).toContain('gh pr edit <n> --add-label automerge')
  expect(rules).toContain('wait until it is `MERGED` before the post-merge live checks and the Drive `Monitoring` sync')
})
