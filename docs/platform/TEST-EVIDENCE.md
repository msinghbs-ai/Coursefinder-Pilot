# Authoritative test evidence and faster PR release gates

Platform Admin mandate, 6 Nov 2026 11:00 (admin repo `docs/platform/2026-11-06-authoritative-test-evidence-release-gates-1100.md`). This file records the audit (mandate section 1), the baseline (section 6) and how the implementation works. It is a bounded CI and release-engineering change, not a new test framework: the suite, the register and the release contract are the existing ones.

## 1. Audit: what runs, and why it ran more than once

Measured on PR #889 (branch `cf247-intake-progress-ui`, 9 commits, 34 files) from the GitHub REST API (`actions/runs`, 1 to 6 Nov 2026) and from the local runs of that release.

| Finding | Measured |
|---|---|
| Default suite (`npx playwright test --grep-invert @deployed`) | 1927 tests across 452 specs (register, 6 Nov 2026); 14 to 15 minutes on the shared 2 CPU machine |
| Where the full suite ran | **Only on the agent machine.** No GitHub workflow runs the default suite. CI runs `pim-build.yml` (build, two static contracts, smoke), `release-history-contract.yml`, and the isolated-PostgreSQL integration workflows (each with its own config and `tests/integration` specs) |
| Full-suite executions for #889 | 3 local runs of the same 1927 tests after one rebase: list reporter, JSON-only reporter, then the CI checks. About 43 minutes of machine time for one verification |
| Why the second run existed | `--reporter=list` on the command line replaces the reporters in `playwright.config.mjs`, so `uat-artifacts/results.json` (needed by `scripts/test-register.mjs` for the Status column) was not written. The JSON run repeated every test only to change the output format |
| Register appendices | `intake-integration.json` and `course-columns-integration.json` were copied by hand from other worktrees. `tests/fixtures/intake-progress/register.mjs` writes "passing" without reading a report |
| CI runs for #889 | 28 pull_request runs on 9 head commits; 165.9 run-minutes in total; 2 failed runs (both Intake Run and Validate; one defect of the intake config picking up another spec cost a full CI cycle of about 5 minutes per commit it affected) |
| CI run-minutes by workflow for #889 | Intake Run and Validate integration 107.3; Pilot Frontend Build 37.0; Intake Automation Progress integration 21.2; Release History Contract 0.4 |
| CI over the 300 most recent runs (since 1 Nov) | Intake Run and Validate (pull_request) 24 runs, mean 8.8 min, 2 failures; Pilot Frontend Build 62 runs, mean 1.6 min; Course Catalogue columns 11 runs, mean 3.7 min, 2 failures |
| Repository | Public, so GitHub-hosted minutes are not billed; the cost that matters is elapsed time, agent machine time and manual intervention |

Which repeated runs gave new verification and which did not:

| Run | New verification? |
|---|---|
| Full suite on a new head that changed code, tests, fixtures, migrations, dependencies, build or workflow configuration | Yes |
| Isolated-PostgreSQL integration workflows when their path filters match | Yes (production-representative constraints; not duplicated by the suite) |
| Re-running the full suite after a release-notes, CHANGELOG or docs-only commit | No: nothing executable changed. The release contract, governance specs and build still need to run on the final candidate |
| Re-running the full suite only to obtain JSON for the register | No: a different output format of the same execution |
| Running the full suite again in CI "to be sure" after a local pass | No for the same fingerprint; the CI run becomes the one authoritative run |
| Hand-copying integration reports into the register | No: the report is an artifact of the workflow that ran it |

## 2. What was built

One workflow, `.github/workflows/test-evidence.yml` (check `test-evidence`; no existing workflow or required check name changed), and four scripts:

| File | Role |
|---|---|
| `scripts/test-evidence-classes.json` | The classification: reusable non-executable metadata, overrides, what the final candidate must still pass, the required check names, retention |
| `scripts/test-evidence-lib.mjs` | Pure functions: classification, dependency fingerprint, reuse decision, bundle validation, results summary, readiness report |
| `scripts/test-evidence.mjs` | CLI: `fingerprint`, `plan`, `bundle`, `verify`, `register`, `final-from-results` |
| `scripts/test-evidence-readiness.mjs` | GitHub side (REST only): `parity` and `report` |
| `scripts/test-register.mjs` | Now accepts `--results`, `--source`, `--generated`, so the register is generated from the retained results of the authoritative run |

### The bundle

One bundle per validated commit, uploaded as the normal artifact `test-evidence-<head sha>` (retention 90 days; the name carries the commit, a later bundle never replaces an earlier commit's). Contents: `evidence.json`, `results.json` (Playwright JSON of the same run), `junit.xml`, `TEST-REGISTER.md` (generated from that `results.json`). `evidence.json` holds: source sha, PR, base and repository; the dependency fingerprint; test suite and environment versions (node, OS, Playwright, Vite, React); every test with its title, spec, `// Guards:` reference, status and retries; totals (passed, failed, skipped, flaky); suite start and completion timestamps; the database schema-parity outcome with the per-workflow tracks; build result and a digest of `dist/`; release-contract result; final-candidate check result; CI workflow, run id, attempt and URL; a SHA-256 digest of every other file in the bundle. `complete` is true only when nothing is missing, failed or skipped without a reason (a skip is explained only for a test tagged `@deployed`) and the results cover every test the suite command collects.

### The fingerprint and reuse

The fingerprint is a SHA-256 over every tracked file, as `path` and git blob sha read from the commit (`git ls-tree`, no checkout), plus the runtime contract (node major version, operating system). The only files left out are those matching `reusableMetadata` in the classification: `CHANGELOG.md`, `README.md`, `docs/release-notes/*.md`, `docs/platform/*.md`, `docs/*.md`. Everything else is an input, including anything not yet classified (fail closed): application and Worker code, edge functions, SQL migrations, tests and fixtures, `package.json`, build configuration, workflow files, security and deployment configuration. Two refinements keep this honest: `docs/sops/**` and `docs/paste/**` are always inputs (specs read them), and a metadata file that any spec names is promoted to an input unless the final-candidate checks re-read it (CHANGELOG, release notes and the register). Today that promotes `README.md` and `docs/intake-automation-progress.md`.

The workflow looks, newest first, through the pull request's own commits and its base for an executed bundle that is whole and passing. The evidence is reused only when its fingerprint equals the candidate's; evidence from any other branch, a different schema, a reused bundle, or one whose files do not match their digests is refused. If reused, the candidate still runs on its own commit: the release contract (`scripts/verify-release-contract.mjs`), the governance specs (s32, s42, s57, s120, s70, m245 release history) and the build, and it writes its own bundle (`kind: reused`) that carries the earlier `results.json` and says where it came from. The package version bump and `src/release-manifest.js` are executable (they change the build and runtime) so a release-ceremony commit that bumps them runs the full suite; classifying a manifest-text-only change would need a Platform Admin decision.

### When the full suite runs

On a pull request that is ready for review, that carries the label `full-suite-evidence`, or by `workflow_dispatch` with the PR number. A draft gets the reuse path where valid and otherwise a report saying the full suite was deferred. A push cancels the earlier run for the same PR.

### How the full suite is split across runners (CF-247, CI wall-clock only)

The full suite is the same command, `npx playwright test --grep-invert @deployed`, run as a matrix of shards and merged. The evidence contract does not change.

| Job | Role |
|---|---|
| `test-evidence-plan` | Resolves the pull request, looks for earlier evidence, picks `full`, `reuse` or `deferred`, and the shard list. Carries the label filter the single job had. |
| `test-evidence-shard (i/N)` | Only in `full` mode. `npx playwright test --grep-invert @deployed --shard=i/N --reporter=list,blob`; uploads its blob report. `fail-fast` is off, so every shard reports. |
| `test-evidence` | The required check, the same single name as before. Needs the plan and every shard. Merges the blobs with `npx playwright merge-reports --reporter=json,junit` into the same `uat-artifacts/results.json` and `junit.xml`, then runs the release contract, build, parity wait, bundle, readiness report and fail-closed step unchanged. |

- Number of shards: repository variable `TEST_EVIDENCE_SHARDS` (1 to 16, default 6). It is a size, not a rule, so it is a setting and not a number in a script.
- Fails closed: the check fails if any shard fails, if fewer blobs than shards arrive, or if the merge fails. The bundle still compares the merged total with `playwright test --list`, so a lost shard is a "partial run" and the bundle is incomplete.
- Retries (1 in CI), `workers: 1`, `fullyParallel: false`, the `@responsive` phone rule (`chromium-mobile` runs only `@responsive`, `chromium-desktop` skips it) and `--grep-invert @deployed` come from `playwright.config.mjs` and the unchanged command line. Playwright filters first and shards after, so no rule is applied differently.
- Balance: Playwright 1.63 cuts the filtered list into equal-sized contiguous slices by test count, in project order (all `chromium-desktop` tests in file order, then the `chromium-mobile` tests). It does not weigh by duration. The 83 phone tests (Pixel 7) therefore all land in the last shard. Each shard writes its wall-clock into its job summary; if one shard stays much slower than the rest, the next step is a duration-weighted split, not a change to any test.
- The merged `results.json` differs from a single run only in report metadata (`config.workers`, `config.metadata.actualWorkers`, `config.forbidOnly`, `config.projects[].id`) and in `stats.duration`, which is the sum of the shard run times and not the wall-clock. Suites, specs, tests, results, statuses and retries are the same.
- Caches: `~/.npm` (key `pilot-npm-<os>-node22-<hash of package.json>`, the key `Pilot Frontend Build` already saves on main) and `~/.cache/ms-playwright` (key `testev-playwright-<os>-<hash of package.json>-<Playwright version>`). Neither key uses a lockfile (there is none); `npm install` still resolves versions exactly as before.

### Readiness report

`node scripts/test-evidence-readiness.mjs report --repo msinghbs-ai/Coursefinder-Pilot --pr <n>` (or the `release-readiness-<sha>` artifact and job summary of the workflow) gives the one report: PR and revision, evidence valid or not and whether executed or reused, the fingerprint and its freshness against the candidate right now, production-parity validity, each required check (`Workers Builds: coursefinder-pilot`, `build-and-smoke`, `release-history-contract`, `isolated-postgres`; a path-filtered check that does not apply is shown as not applicable), the final-candidate checks, and the remaining blockers. The verdict is READY, WAITING (only pending checks) or BLOCKED; missing, stale or incomplete evidence is always BLOCKED. Branch protection settings are not readable with the workflow token, so the required names are mirrored in the classification file and guarded by `cf-247-s400`.

### Production parity

Parity is the outcome of the isolated-PostgreSQL workflows (every workflow with a `postgres:` service and a pull_request trigger is discovered automatically, so a new one cannot be forgotten) for the same commit: pass, fail, missing (applicable by its path filter but no run), or not applicable. The bundle also records digests of the migrations and the parity fixtures.

### Limits (stated plainly)

- The bundle proves development and release readiness only. Live version, guarded function hashes, Worker and UI behaviour, admission and publication results are recorded after deployment against the same evidence reference (mandate section 7).
- The existing integration workflows do not upload their JSON reports, so the register's integration appendices still come from the committed appendix scripts; the evidence carries their run outcome instead.
- `README.md` and any other file a spec names are inputs, by design.


## Execution recovery, 6 November 2026

The existing s288 phone repair from #894 was reconciled into this PR before a justified new run. Run [42208692348](https://github.com/msinghbs-ai/Coursefinder-Pilot/actions/runs/42208692348), exact head `d4c3e37568960b6214b4db65cdc10e5ee39b8c43`, executed the full governed suite once: **1,950 passed, 0 failed, 0 skipped, 0 flaky** (6.0 minutes). Build, release contract and readiness passed; applicable skipped/neutral required checks now fail closed. Artifact `13498452408` was downloaded, ZIP SHA-256 verified and every bundle file digest validated; the bundle reports `complete=true`, `result=pass`, `READY`. The existing test register is regenerated from that retained run, not a second suite execution.

This PR's database parity outcome is `not-applicable`: its changed files do not trigger an isolated PostgreSQL track. It does not claim SQL acceptance for #893/#894. Their repaired fixtures must execute and pass at their own exact heads. No production release or admission is inferred; controller ownership remains unresolved under Admin #382.


Integration: #892 is included in the v2.15.490 controller-recovery candidate. Its existing Test evidence workflow is the authoritative full-suite producer; temporary per-capability full-suite wrappers are retired when merged into this dependency chain. Isolated PostgreSQL, release contracts and frontend checks retain their gates.
