# Course intake Run & Validate — integrated implementation (#872)

Authority: Platform Admin's 4 Nov 2026 vertical-feature correction, the [20:05 intake pilot authority](https://github.com/msinghbs-ai/coursefinder-admin/blob/main/docs/platform/2026-11-04-course-intake-pilot-authority-2005.md), Pilot [CLAUDE.md](../CLAUDE.md), and the [canonical operating model](https://github.com/msinghbs-ai/coursefinder-admin/blob/main/docs/platform/DATA-PIPELINE-OPERATING-MODEL.md). Integration Controller: Claude; final release number, merge and deployment remain with Claude.

## Implementation

Layer 2/3 → Operations now connects scope discovery → read-only evidence preview → fixed cohort → governed Run Now → saved results → catalogue and consumer verification. Scope is the v2.15.477-approved top Australian universities **by active course count**, narrowed to an individual member if selected. The configured top count defaults to ten. No scope is widened when eligible work is sparse. University identities, counts, bounds and evidence are queried from the database, never embedded in React.

The feature uses `security.intake_dates_plan_v2` for eligibility and the established most-fields/round-robin provider-and-pattern ordering. Its UI selection projection is read-only and does not extract, read pages, call vendors, admit values or schedule work. Fixed members go into the existing `run_now_cohorts` and `run_now_cohort_members` tables. The existing job performs admission, manual-lock checks and scoped publication refresh. No second reader, scheduler or controller was added.

Preview is a read-only calculation. Its opaque token binds requester, scope, size, expiry and a SHA-256 selection/evidence fingerprint using HMAC-SHA256 and a private key. Preparation validates signature, ownership, bounds, exact selection and reason, serialises duplicate preparation and saves the fixed cohort plus an immutable server-generated execution key. Repeated preparation returns the same saved request. Changes require a fresh preview. No arbitrary course IDs or SQL are accepted.

The UI's Run Now facade accepts **only the cohort UUID**. It loads requester-bound saved reason and key and calls the existing `public.admin_job_run_now_v1`; that API retains catalogue/rank/allowlist/pause/switch/cap/job-lock/audit authority. A request-specific advisory lock prevents simultaneous retries from reaching the shared runner before its final audit row exists. A duplicate returns `in_progress` without dispatching another job, and records a control event. No shared-function definition is changed.

Capabilities list saved requests belonging to the caller. On refresh, the UI restores cohort, reason, immutable key, saved run IDs, times, counts and verification. A cohort ID in the existing route query can select a saved request; older owned cohorts can also be opened by UUID. A lost response can be recovered through the same saved request. The v2.15.476 job is synchronous: the UI shows an indeterminate wait and actual final counts, with no invented percentage or cancellation promise.

Verification is a read-only wrapper of the existing verifier, with ownership checks and course/provider names. It returns fixed evidence, before/after values, current catalogue, saved task records and Website/Zoho responses. Per-course status requires all non-null admitted scalars (year, start and deadline) to match in a consumer intake. Missing/error/non-array Zoho output is `unsupported`, not a pass; mismatched data is `unverified`. The existing verifier's aggregate `published` count is retained for compatibility and is less strict; the new `publication` statuses use the full scalar comparison. No frozen consumer function, response shape or admission authority changes.

AI diagnostics remain unavailable: no approved existing pinned-model read-only diagnostic backend was identified, and this feature calls no AI controller or vendor. Execution operates on stored evidence, so its expected vendor spend is zero; the real Run Now results report vendor-call counts. No budget, credit floor or activation setting is changed.

## Exact database dependencies and changed functions

New migration: `supabase/migrations/20261105000000_intake_run_validate_bridge.sql`. Generated with Supabase CLI and ordered after the repository's logical dependency versions `20261104610000` and `20261104630000`. Claude may reconcile the filename with the integrated migration sequence before deployment. The migration changes no existing function definition, table shape consumed by Website/Zoho, scheduler, job command or switch.

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

Live metadata was inspected **read-only** on 4 Nov 2026 and matched the reconciled main definitions. Migration preconditions reject drift in these authorities:

| Existing function | Definition MD5 |
|---|---|
| `security.intake_dates_plan_v2(uuid[],integer)` | `8e3e11c3b78e4e52ea0709e48a666ff6` |
| `security.intake_dates_apply_v1(integer,uuid[])` | `d47fbe685ae62287264a1909c988e9d6` |
| `security.run_now_cohort_create_v1(text,uuid,text,text)` | `410db5ca480e038e32d12c16f66eefa9` |
| `security.job_run_now_v1(text,text,jsonb,uuid)` | `cabacd4094ed138a57f6b102183eeacc` |
| `public.admin_job_run_now_v1(text,text,jsonb)` | `2a5ccb9fe52041696582a8b524bc8ae2` |
| `security.run_now_cohort_verify_v1(uuid)` | `9de88275d2e29a7f4c062d5319d6316d` |

`public.admin_read` is untouched: dedicated role-checked `admin_*` RPCs follow the existing UI pattern and isolate this work from the shared dispatcher. No shared-function work requires a competing migration. This handoff and PR are the coordination record for Claude.

## Executable integration tests and evidence

**Environment correction from Platform Admin: “no test db only production pilot.”** There is no approved hosted test database. No migration, fixture, job execution or admission write was sent to production. The existing repository-approved **isolated PostgreSQL 16 harness** was used instead. This is real PostgreSQL execution, not mocked backend success. It does not prove production admission.

The intake base harness rebuilds the real plan, bounded apply, admission triggers and search core projection from repository definitions and checks their live-contract hashes. Infrastructure is controlled: minimal schemas/auth roles, pg_cron stand-in, parser-driven stored calendar fixture and bound course-page evidence. The vertical fixture hooks the actual core search projection into the base harness's refresh recorder. Its Website intake wrapper uses the established consumer expression; it is not a full deployed Website stack. Zoho is normally unavailable; a separate controlled supported-shape fixture tests the bridge comparison and restores the unavailable implementation. Neither represents a live Zoho request.

The SQL suite tests scope/counts, an individual university, eligibility/evidence, missing calendar, manual locks, exact fixed membership, duplicate preparation, signed-token tampering, cross-user/expired/changed previews, authorised existing job execution, before/after catalogue, real core projection read-back, supported/unsupported Zoho handling, deadline mismatch, saved IDs/key/results, repeat/interrupted-response recovery, role/anonymous/foreign-cohort refusal, concurrency and zero vendor calls. It also checks migration reapplication, unchanged shared cohort/runner hashes, new-table RLS and private grants.

The separate Playwright integration suite mounts the real React component with its real RPC adapter. A loopback-only transport executes each request against PostgreSQL under `SET ROLE authenticated` and the controlled fixture identity; **no RPC result is mocked**. This proves the browser-to-SQL workflow and saved refresh recovery. It does not claim a deployed Supabase Auth/PostgREST session was tested. Desktop executes the entire workflow; phone inspects saved admission/publication without horizontal page overflow. Local lightweight UI tests remain for fast refusal/network/layout regressions.

Run against a disposable local PostgreSQL (never a hosted project):

```sh
# psql and a local PostgreSQL 16 server are required; the script refuses remote PGHOST.
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres
bash tests/fixtures/intake-ui/run.sh
npx playwright test --config=playwright.intake.config.mjs
```

Docker alternative when the host has Node/Python but lacks psql:

```sh
docker --host=unix:///var/run/docker.sock run -d --name intake-ui-postgres -e POSTGRES_PASSWORD=fixture-only postgres:16
export PATH="$PWD/tests/fixtures/intake-ui/bin:$PATH"
bash tests/fixtures/intake-ui/run.sh
npx playwright test --config=playwright.intake.config.mjs
```

The Docker psql helper always targets that named local container; it cannot target a Supabase database. The browser transport binds loopback and exposes only the three fixture RPCs. Test databases are disposable and fixture DDL is never applied to production. `.github/workflows/intake-run-validate-test.yml` makes the same SQL/browser sequence executable on a PostgreSQL service without secrets or deployment permissions. Integration specs are registered separately here under guard **PR #872 complete UI workflow against isolated PostgreSQL** (`tests/integration/intake-postgres.spec.mjs`: two browser tests, desktop and responsive phone); the canonical UAT register is regenerated for its existing suite, then the separate SQL-backed track is generated into a supplementary section with `node tests/fixtures/intake-ui/register.mjs`.

Results: see [integration evidence](ui-evidence/intake-integration-results.txt). UI evidence now shows actual local SQL-backed results: [desktop](ui-evidence/intake-database-desktop.png), [phone](ui-evidence/intake-database-phone.png). Earlier `intake-desktop.png` / `intake-phone.png` remain explicitly lightweight fixture UI evidence.

## Production acceptance procedure — Claude only

1. Reconcile latest main, the six guarded definitions above and migration ordering. Review settings and current scope/counts without switching anything on. Apply the reviewed bridge through the existing release process; assign final release number and deploy UI as Integration Controller.
2. Immediately within the existing 5–10 minute gate, sign in as an authorised operator. Confirm actual Australian university identities/counts and approved top-ten scope. Preview a bounded cohort using real stored official evidence and approved calendars. Inspect source URLs, course-page wording, calendar quotes, denominator and eligibility reasons.
3. Fix the preview with an audited reason. Record the cohort UUID. Run Now once through the UI. Confirm existing task/audit requester, reason, ID, times, processed/admitted/skipped/failed and vendor-call counts. Do not resume a paused job, change an admission rule or bypass a spending control to manufacture success.
4. Verify exact before/after catalogue values and official evidence, then Website API v2 and supported Zoho read-back. Missing, unsupported and mismatching responses remain unverified. Preserve manual values. Refresh and confirm the same saved run and outcome are restored; an interrupted response must recover through the saved request rather than create another execution.
5. Record PASS/FAIL/BLOCKED against the exact fixed cohort and evidence-backed denominator, using the existing pilot target (ten newly verified intake values, zero incorrect values) and immediate acceptance register. A short denominator is not widened or relabelled a pass. Production consumer/API requests remain the final acceptance evidence.

## Operational limitations

No hosted test project exists, so hosted Auth/PostgREST, full deployed Website/Zoho behaviour and production admission remain unverified until Claude's gate. Local fixtures prove implementation execution, not production outcome. The current verifier counts intake rows and changes since cohort selection; scheduled processing may contribute, and that is not proof of a particular Run Now's exclusive causation. The existing vendor-call counter is global to the run window; concurrent unrelated vendor activity can contribute, so a production nonzero count needs attribution rather than an invented spending verdict. Large canonical plan scans and synchronous runs can time out; keep governed scan/cap limits, inspect saved results and recover the same request. Dependency drift stops migration application for Integration Controller reconciliation. No merge, deployment, production write or final release-number assignment is part of this feature branch.
