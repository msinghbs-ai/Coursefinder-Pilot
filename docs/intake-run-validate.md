# Course intake Run & Validate — integrated implementation (#872)

Authority: Platform Admin's 4 Nov 2026 vertical-feature correction, the [20:05 intake pilot authority](https://github.com/msinghbs-ai/coursefinder-admin/blob/main/docs/platform/2026-11-04-course-intake-pilot-authority-2005.md), Pilot [CLAUDE.md](../CLAUDE.md), and the [canonical operating model](https://github.com/msinghbs-ai/coursefinder-admin/blob/main/docs/platform/DATA-PIPELINE-OPERATING-MODEL.md). Integration Controller: Claude; final release number, merge and deployment remain with Claude.

## Follow-up: complete bounded discovery and one-action Run Now

The v2.15.479 five-row workaround fixed request latency but **did not complete the existing discovery budget**. A three-course UNSW preview was not evidence that the other universities had no eligible courses. Run Now also required a separate saved-cohort action. This follow-up corrects both behaviours; it does not fill unsupported source gaps.

Migration `20261105020000_intake_preview_paging.sql` adds private, operator-owned preview snapshots and resumable, idempotent pages. Each request reads the existing `run_now.preview_rows_per_university` work setting (currently 5), while round-robin discovery continues until each university reaches its share of `run_now.cohort_scan_rows` (currently 1,500 / 10 = 150 intake rows) or candidate end. It does not claim exhaustive catalogue coverage beyond that configured budget. Every university reports its actual denominator and eligible count, including zero. Pause/Resume and lost-response replay retain the cursor without advancing it twice.

The canonical private `security.intake_dates_plan_v2` gains a four-argument cursor overload. The original two-argument signature delegates to that single implementation; there is no second reader. Only the candidate keyset predicate changes. The original definition hash is checked before conversion. Source identity, period matching, manual locks, admission rules, the apply function, scheduler, governed runner and consumer APIs remain unchanged. Claude must reconcile any shared-definition conflict rather than bypass the migration guard.

New browser interfaces:

- `public.admin_intake_preview_v1(text,jsonb)`: start/step/read, rank ≥ 3, owner-only session access. Source/catalogue reads only; it writes private preview metadata and evidence snapshots.
- `public.admin_intake_preview_prepare_v1(uuid,text)`: existing job control rank, reason required, completed/unexpired snapshot, current approved scope/cap, exact selected-source/value revalidation, existing fixed-cohort/request/audit tables. Repeated preparation returns the same cohort and key.
- Existing `admin_intake_run_read_v1` advertises `paged_preview`; existing `admin_intake_run_now_v1` remains the only browser execution path. No private function grants are added.

Run Now now saves the validated cohort and invokes that existing governed execution path in one click. An optional **Save cohort only** action remains. The UI explains a missing reason, a smaller-than-requested eligible cohort, per-course evidence stops and approved-calendar exact-date coverage. Saved runs and verification still restore after refresh. No new AI controller or model is introduced.

### Source limitations

Read-only production metadata inspection found that the latest approved UNSW calendar had five start entries but **zero exact start dates**. Sydney, Monash, UTS, RMIT, Flinders and Newcastle had some exact starts; their individual course pages must still prove the corresponding named period. A year-only proposal does not prove a new start date. Missing/refused/unproved course evidence and month-only wording must be resolved through existing source/identity review and calendar approval controls. The intake job must not invent dates or substitute a university-wide date for a course-specific admission decision.

### Reproduce and accept this correction

```sh
bash tests/fixtures/intake-complete-scan/run.sh
npx playwright test --config=playwright.intake.config.mjs
psql -X -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f tests/fixtures/intake-ui/post.sql
psql -X -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f tests/fixtures/intake-complete-scan/post.sql
```

The dense fixture adds a supported course after row five, with the same approved intake source and existing search document as standard catalogue fixtures and asserts that the old probe misses it. The real database browser test discovers it during the complete bounded scan, automatically saves/runs twenty courses, recovers a dropped preview response and dropped committed-run response, verifies admissions/publication and restores results on desktop/phone. Test-only RPC transport enforces the unchanged 8-second SQL and lock timeouts. Evidence includes per-request timings, authoritative schema parity, SQL results and screenshots. Controlled fixtures contain no production personal data and do not prove live admission or publication.

The original five-sample full-budget synchronous timing check is retained as a diagnostic baseline, including actual timeout outcomes. The later three-sample fifty-row synchronous preview latency assertion is superseded by ten actual paged-RPC SQL measurements and complete-budget browser acceptance. The original timeout reproducer, sixty authoritative identity/verdict comparisons and selected-cohort checks remain; no SQL timeout is increased and no failed feature check is skipped.

The test HTTP proxy allows up to 60 seconds for Docker/psql startup and JSON delivery, distinct from the unchanged eight-second database statement/lock limit. SQL timings use EXPLAIN ANALYZE; browser request timings include that transport overhead.

Publication remains a separate authority: a missing/unapproved intake source or absent consumer document stays unverified, even when the catalogue admission succeeds. A regression exercises that refusal through the real projection and rolls the fixture back.

Operational limitations: a preview spans several transactions, expires under the existing preview setting and revalidates selected evidence before preparation. Preview tables retain private evidence snapshots; deployment review must include retention under the platform housekeeping policy. No new cleanup scheduler or destructive migration is added. The scan budget remains finite; raising page work may cause timeouts, while raising total coverage requires capacity review. No production operation was performed.

Claude's immediate **5–10 minute post-deployment gate**: use the approved top-ten scope and size 20; confirm all ten universities finish their independent scans and inspect actual evidence/field gains. Enter an audited reason and click Run Now once; confirm one saved cohort/request/run and real admitted values. Verify catalogue before/after and Website API v2 for those exact course IDs, and supported Zoho with independently matching values (unsupported stays unverified). Refresh and inspect the same IDs/results on a phone. If fewer than twenty genuinely supported courses exist, record the actual count and source blockers; do not mark the twenty-course or new-date target met. Resolve source gaps through the existing approved workflow before repeating with a fresh preview. No version assignment, merge or deployment is included here.

Measured development acceptance: **271 pages / 1,350 canonical intake rows / all ten universities**, **20 admitted and Website-verified courses**, one persisted run after lost-response recovery, desktop refresh and phone inspection. Both database-backed browser tests and all 33 focused UI/platform tests passed; build and UI-token checks passed. The ten EXPLAIN ANALYZE page samples measured **25–348 ms**, below the unchanged eight-second SQL limit. The complete local browser run took 8.5 minutes including Docker transport; maximum individual HTTP wall time was 9.115 seconds and zero query-timeout resumes were needed in the final run. HTTP wall time is distinct from SQL duration. Full results, query plans and desktop/phone screenshots are in [the evidence directory](ui-evidence/intake-complete-scan-results.json). Production acceptance remains pending Claude's actual admission/publication gate.

## Post-release Preview timeout correction (v2.15.478)

The reported UI message `canceling statement due to statement timeout` was reproduced with a bounded **read-only** production query of the preview selector. The exception occurs in `course_title_key` → `course_page_check_v1` → `intake_dates_plan_v2`, before fixing a cohort or starting a Run Now job. The earlier no-evidence-heavy skew benchmark underrepresented this path, so its historical timing is not evidence that dense production pages fit the request limit.

Follow-up migration `20261105010000_intake_preview_identity_lookup.sql` retains the original identity predicates and decisions while adding an indexed, mathematically equivalent sibling-title prefix restriction and provider-scoped URL/final-URL lookup indexes. The immutable ASCII title normalizer and shared identity-check definitions are hash-guarded. No extraction, scheduler, admission rule, consumer response shape, role grant, existing spending/cohort limit or authenticated timeout is changed.

Index optimization alone is insufficient when every candidate has stored evidence. A new governed setting, `run_now.preview_rows_per_university` (default **5**, range 1–1,000 rows), explicitly bounds synchronous preview work, further clamped by the existing university's share of `run_now.cohort_scan_rows`. The operator's **20-course cohort remains unchanged**. The UI already displays each actual scan limit and evaluated denominator. Sparse results describe evaluated rows, not exhaustive eligibility; unexamined rows are not classified as ineligible. Increasing this work setting may reintroduce the timeout and requires capacity review with an audited reason through existing settings controls.

The new fixture loads the **authoritative production title-normalizer**, adds proved course-page evidence in every calendar-backed university (including the 5,200-course provider), and reproduces the old 8-second `57014` failure. After the fix, the accepted local samples were **3,673 / 3,946 / 4,264 ms**, with the unchanged 8-second request limit. All **60 full identity verdict/diagnostic snapshots** and prefix edge cases pass; selected twenty courses and their source-supported values match the baseline. Dense-path twenty-course UI execution, saved recovery and post-browser catalogue/API/evidence-lineage checks are executable with:

```sh
bash tests/fixtures/intake-complete-scan/run.sh
npx playwright test --config=playwright.intake.config.mjs
psql -X -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f tests/fixtures/intake-ui/post.sql
```

CI runs this dense regression before the real database-backed browser suite. The frontend now identifies Preview timeout explicitly and confirms it did not dispatch an intake job. Regression evidence is `docs/ui-evidence/intake-preview-timeout-results.json`; these are local measurements, not a claim of post-fix production performance. Claude must deploy and verify the actual production preview; no production job or write was performed during diagnosis.

**Integration risk:** normal index builds briefly block writers on the two indexed tables. Claude should choose a suitable deployment window or build the exact indexes concurrently through an approved separate operation before applying the idempotent migration. A future change to the immutable title normalizer requires index review/rebuild. Do not raise role timeouts or silently increase the scan/work/cohort limits to get a pass. After authorised deployment, verify the observed per-university limits, preview latency and genuine evidence denominator before proceeding to the existing governed Run Now acceptance gate.

## Implementation

Layer 2/3 → Operations now connects scope discovery → read-only evidence preview → fixed cohort → governed Run Now → saved results → catalogue and consumer verification. Scope is the approved top ten Australian universities **by active course count** (controlled by the existing setting), narrowed to an individual member if selected. The configured top count defaults to ten. No scope is widened when eligible work is sparse. University identities, counts, bounds and evidence are queried from the database, never embedded in React.

The feature uses `security.intake_dates_plan_v2` for eligibility and the established most-fields/round-robin provider-and-pattern ordering. Each university is evaluated independently, dividing the existing `run_now.cohort_scan_rows` budget equally across the configured top universities (1,500 total / ten = 150 per university at current defaults). A dominant university cannot consume another university's scan allowance. Every university is reported with active courses, evaluated rows, eligible courses/values and its scan limit, including zero. These are bounded-scan eligibility counts, not claims of exhaustive totals. No scope, scan or batch operational limit is embedded in React or raised to force success. Its UI selection projection is read-only and does not extract, read pages, call vendors, admit values or schedule work. Fixed members go into the existing `run_now_cohorts` and `run_now_cohort_members` tables. The existing job performs admission, manual-lock checks and scoped publication refresh. No second reader, scheduler or controller was added.

Preview is a read-only calculation. Its opaque token binds requester, scope, size, expiry and a SHA-256 selection/evidence fingerprint using HMAC-SHA256 and a private key. Preparation validates signature, ownership, bounds, exact selection and reason, serialises duplicate preparation and saves the fixed cohort plus an immutable server-generated execution key. Repeated preparation returns the same saved request. Changes require a fresh preview. No arbitrary course IDs or SQL are accepted.

The UI's Run Now facade accepts **only the cohort UUID**. It loads requester-bound saved reason and key and calls the existing `public.admin_job_run_now_v1`; that API retains catalogue/rank/allowlist/pause/switch/cap/job-lock/audit authority. A request-specific advisory lock prevents simultaneous retries from reaching the shared runner before its final audit row exists. A duplicate returns `in_progress` without dispatching another job, and records a control event. The only changed shared function is the exact tested PR #874 outcome-code correction; its migration is incorporated unchanged. No AER function/file from #875 is included.

Capabilities list saved requests belonging to the caller. On refresh, the UI restores cohort, reason, immutable key, saved run IDs, times, counts and verification. A cohort ID in the existing route query can select a saved request; older owned cohorts can also be opened by UUID. A lost response can be recovered through the same saved request. The v2.15.476 job is synchronous: the UI shows an indeterminate wait and actual final counts, with no invented percentage or cancellation promise.

Verification is a read-only wrapper of the existing verifier, with ownership checks and course/provider names. It returns fixed evidence, before/after values, current catalogue, saved task records and Website/Zoho responses. Per-course status requires all non-null admitted scalars (year, start and deadline) to match in a consumer intake. Missing/error/non-array Zoho output is `unsupported`, not a pass; mismatched data is `unverified`. The existing verifier's aggregate `published` count is retained for compatibility and is less strict; the new `publication` statuses use the full scalar comparison. No frozen consumer function, response shape or admission authority changes.

AI diagnostics remain unavailable: no approved existing pinned-model read-only diagnostic backend was identified, and this feature calls no AI controller or vendor. Execution operates on stored evidence, so its expected vendor spend is zero; the real Run Now results report vendor-call counts. No budget, credit floor or activation setting is changed.

## Exact database dependencies and changed functions

New migration: `supabase/migrations/20261105000000_intake_run_validate_bridge.sql`. Generated with Supabase CLI and ordered after `20261104610000`, `20261104630000` and the incorporated `20261104640000_cf247_run_now_outcome_code.sql` from draft PR #874 (`8ca549d1`). No release/version files from #874 are included. Claude may reconcile the filename with the integrated migration sequence before deployment. The bridge changes no existing reader, consumer API, scheduler, job command or switch. Apply the incorporated PR #874 outcome-code correction first; it changes only the existing Run Now task-outcome expressions.

New functions:

| Function | Purpose/access |
|---|---|
| `security.intake_ui_scopes_v1()` | Private approved top-AU university scope and active course counts |
| `security.intake_ui_selection_v1(text,integer)` | Private bounded projection of canonical eligibility and selection ordering |
| `security.intake_ui_preview_v1(text,integer)` | Private read-only signed preview |
| `security.intake_ui_values_match_v1(jsonb,jsonb)` | Private full admitted-scalar comparison |
| `public.admin_intake_cohort_prepare_v1(text,integer,text,text)` | Authenticated catalogue-control rank; signed fixed preparation |
| `public.admin_intake_run_now_v1(uuid)` | Authenticated owner/control rank; duplicate-safe facade to existing Run Now |
| `public.admin_intake_run_read_v1(text,jsonb)` | Authenticated Operations rank ≥3; capabilities/preview/owner-only verification |

Public bridges check `auth.uid()` and database role membership; no editable JWT metadata is trusted. Private functions have no client EXECUTE grant. New private tables `pipeline.intake_ui_signing_key` and `pipeline.intake_ui_requests` have RLS enabled and no anonymous/authenticated table grants. All privileged functions pin an empty search path. Component register rows cover new tables/functions. Settings `run_now.preview_seconds` and `run_now.history_rows` include labels, ranges, units and used-by lines and appear through the existing settings UI.

Authoritative schema/function metadata for the original integration baseline was inspected **read-only** on 4 Nov 2026; production was v2.15.477 at that point. PR #874 corrects Run Now outcomes from invalid `ran`/`refused` to the registered outcome codes; the bridge guard requires that tested correction before application. Migration preconditions reject drift in these authorities:

| Existing function | Definition MD5 |
|---|---|
| `security.intake_dates_plan_v2(uuid[],integer)` | `8e3e11c3b78e4e52ea0709e48a666ff6` |
| `security.intake_dates_apply_v1(integer,uuid[])` | `d47fbe685ae62287264a1909c988e9d6` |
| `security.run_now_cohort_create_v1(text,uuid,text,text)` | `410db5ca480e038e32d12c16f66eefa9` |
| `security.job_run_now_v1(text,text,jsonb,uuid)` | `2640319be221ab00f39e6e767b78a7b3` (after #874; production currently `cabacd4094ed138a57f6b102183eeacc`) |
| `public.admin_job_run_now_v1(text,text,jsonb)` | `2a5ccb9fe52041696582a8b524bc8ae2` |
| `security.run_now_cohort_verify_v1(uuid)` | `9de88275d2e29a7f4c062d5319d6316d` |

`public.admin_read` is untouched: dedicated role-checked `admin_*` RPCs follow the existing UI pattern and isolate this work from the shared dispatcher. No competing shared migration is introduced: #874 is included byte-for-byte and #875 remains separate. This handoff and PR are the coordination record for Claude.

## Executable integration tests and evidence

**Environment correction from Platform Admin: “no test db only production pilot.”** There is no approved hosted test database. No migration, fixture, job execution or admission write was sent to production. The existing repository-approved **isolated PostgreSQL 17.6 harness (matching production engine version)** was used instead. This is real PostgreSQL execution, not mocked backend success. It does not prove production admission.

The intake base harness rebuilds the real plan, bounded apply, admission triggers and search core projection from repository definitions and checks their live-contract hashes. Infrastructure is controlled: minimal schemas/auth roles, pg_cron stand-in, parser-driven stored calendar fixture and bound course-page evidence. The vertical fixture hooks the actual core search projection into the base harness's refresh recorder. Its Website intake wrapper uses the established consumer expression; it is not a full deployed Website stack. Zoho is normally unavailable; a separate controlled supported-shape fixture tests the bridge comparison and restores the unavailable implementation. Neither represents a live Zoho request.

The SQL suite tests scope/counts, an individual university, eligibility/evidence, missing calendar, manual locks, exact fixed membership, duplicate preparation, signed-token tampering, cross-user/expired/changed previews, authorised existing job execution, before/after catalogue, real core projection read-back, supported/unsupported Zoho handling, deadline mismatch, saved IDs/key/results, repeat/interrupted-response recovery, role/anonymous/foreign-cohort refusal, concurrency and zero vendor calls. It also checks migration reapplication, unchanged shared cohort/runner hashes, new-table RLS and private grants.

The separate Playwright integration suite mounts the real React component with its real RPC adapter. A loopback-only transport executes each request against PostgreSQL under `SET ROLE authenticated` and the controlled fixture identity; **no RPC result is mocked**. This proves the actual 20-course browser-to-SQL workflow, post-commit dropped-response recovery to the same run, and saved refresh recovery. It does not claim a deployed Supabase Auth/PostgREST session was tested. Desktop automatically selects/fixes/runs twenty courses, loses the real commit response, recovers the same saved run without creating another task and verifies all twenty catalogue/consumer results; phone inspects saved admission/publication without horizontal page overflow. Local lightweight UI tests remain for fast refusal/network/layout regressions.

Run against a disposable local PostgreSQL (never a hosted project):

```sh
# psql and a local PostgreSQL 17.6 server are required; the script refuses remote PGHOST.
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres
bash tests/fixtures/intake-ui/run.sh
npx playwright test --config=playwright.intake.config.mjs
psql -X -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f tests/fixtures/intake-ui/post.sql
```

Docker alternative when the host has Node/Python but lacks psql:

```sh
docker --host=unix:///var/run/docker.sock run -d --name intake-ui-postgres -e POSTGRES_PASSWORD=fixture-only postgres:17.6-alpine
export PATH="$PWD/tests/fixtures/intake-ui/bin:$PATH"
bash tests/fixtures/intake-ui/run.sh
npx playwright test --config=playwright.intake.config.mjs
psql -X -v ON_ERROR_STOP=1 -d intake_ui_fixtures -f tests/fixtures/intake-ui/post.sql
```

The Docker psql helper always targets that named local container; it cannot target a Supabase database. The browser transport binds loopback and exposes only the three fixture RPCs. Test databases are disposable and fixture DDL is never applied to production. `.github/workflows/intake-run-validate-test.yml` makes the same SQL/browser sequence executable on a PostgreSQL service without secrets or deployment permissions. Integration specs are registered separately here under guard **PR #872 complete UI workflow against isolated PostgreSQL** (`tests/integration/intake-postgres.spec.mjs`: two browser tests, desktop and responsive phone); the canonical UAT register is regenerated for its existing suite, then the separate SQL-backed track is generated into a supplementary section with `node tests/fixtures/intake-ui/register.mjs`.

Results: see [integration evidence](ui-evidence/intake-integration-results.txt). UI evidence now shows actual local SQL-backed results: [desktop](ui-evidence/intake-database-desktop.png), [phone](ui-evidence/intake-database-phone.png). Earlier `intake-desktop.png` / `intake-phone.png` remain explicitly lightweight fixture UI evidence.

## Relevant production-schema parity and 20-course acceptance

The previous fixture omitted `admin_jobs_outcome_fkey`; its earlier success was insufficient production evidence. The corrected harness carries the authoritative outcome FK/codes and task state/kind constraints, relevant intake/cohort foreign keys, column nullability/defaults, same-month/manual-lock triggers, and **both real evidence-lineage triggers plus their real helper functions**. The previously nullable fixture `admin_jobs.progress` now has production's default and NOT NULL constraint. Snapshot files `tests/fixtures/intake-ui/production-parity*.json` contain schema metadata only, no production personal data. `parity.mjs` reconstructs and asserts relevant definitions/EXECUTE privileges; `evidence-trigger-definitions.sql` carries authoritative trigger helpers. Function hashes guard unchanged admission authority and the reviewed #874 correction. Supabase platform preload libraries and hosted Auth infrastructure are not replicated.

Regression SQL proves `ran`, `refused` and invented outcomes fail the actual FK; valid `succeeded_with_result`, `succeeded_no_movement`, `blocked_policy` and `failed_retryable` persist. Failed execution rolls back source-value writes while saving the failure. Missing calendar yields no eligible cohort; paused execution is refused; duplicate and interrupted requests retain one persisted run. All intake admission/evidence triggers remain enabled during the twenty-course operation. Post-browser SQL checks the exact twenty-course cohort, twenty admitted and Website-verified rows, one task after response loss/recovery, the typed intake response contract and retained evidence lineage.

The controlled skewed dataset contains ten fictional Australian universities and over 7,000 active courses. A dominant university has 5,200 courses/2,700 candidates; eight other universities supply 24 eligible official-source-shaped page/calendar records, and two universities report zero eligibility. The old global scan produces zero eligible courses; independent scans automatically select twenty across eight universities without widening scope. No production IDs, source records or personal data are copied.

Five `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` previews run as the authenticated fixture role, with production's **8-second statement and lock limits explicitly enforced** (SET ROLE alone does not apply role configuration). Median **3,035 ms**, maximum **3,178 ms** in the accepted local run; exact samples/plans are in `docs/ui-evidence/intake-benchmark.json`. These are measured local skew-test timings, not production measurements or guarantees. Normal deployment must preserve the 8-second RPC limit and re-check actual evidence/denominators within the immediate acceptance gate.

## Production acceptance procedure — Claude only

1. Reconcile main plus #874 and #875 with the Integration Controller. Apply the byte-identical #874 migration once, then the bridge; keep #875 AER work separate. Recheck the six guarded definitions and migration ordering. Production remains on hold until Claude authorises the release. Review settings and current scope/counts without switching anything on. Apply the reviewed bridge through the existing release process; assign final release number and deploy UI as Integration Controller.
2. Immediately within the existing 5–10 minute gate, sign in as an authorised operator. Confirm actual Australian university identities/counts and approved top-ten scope. Preview twenty eligible courses using real stored official evidence and approved calendars. Inspect all ten per-university scan/eligibility denominators, including zeros; sparse work is BLOCKED rather than widened or relabelled a pass. Inspect source URLs, course-page wording, calendar quotes, denominator and eligibility reasons.
3. Fix the preview with an audited reason. Record the cohort UUID. Run Now once through the UI. Confirm existing task/audit requester, reason, ID, times, processed/admitted/skipped/failed and vendor-call counts. Do not resume a paused job, change an admission rule or bypass a spending control to manufacture success.
4. Verify exact before/after catalogue values and official evidence, then Website API v2 and supported Zoho read-back. Missing, unsupported and mismatching responses remain unverified. Preserve manual values. Refresh and confirm the same saved run and outcome are restored; an interrupted response must recover through the saved request rather than create another execution.
5. Record PASS/FAIL/BLOCKED against the exact fixed cohort and evidence-backed denominator, using the existing pilot target (ten newly verified intake values, zero incorrect values) and immediate acceptance register. A short denominator is not widened or relabelled a pass. Production consumer/API requests remain the final acceptance evidence.

## Operational limitations

No hosted test project exists, so hosted Auth/PostgREST, full deployed Website/Zoho behaviour and production admission remain Claude's production gate. Development acceptance uses a real isolated PostgreSQL 17.6 database with relevant production constraints, triggers, grants and function signatures; no backend dependency is left missing. Local fixtures prove implementation execution, not production outcome. The current verifier counts intake rows and changes since cohort selection; scheduled processing may contribute, and that is not proof of a particular Run Now's exclusive causation. The existing vendor-call counter is global to the run window; concurrent unrelated vendor activity can contribute, so a production nonzero count needs attribution rather than an invented spending verdict. Large canonical plan scans and synchronous runs can time out; keep governed scan/cap limits, inspect saved results and recover the same request. Dependency drift stops migration application for Integration Controller reconciliation. No merge, deployment, production write or final release-number assignment is part of this feature branch.
