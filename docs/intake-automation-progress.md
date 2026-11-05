# Intake Automation Progress (Process results › Automation progress)

**Mandate:** Platform Admin decision 5 Nov 2026 16:36 §3–§8 (admin `docs/platform/2026-11-05-pr882-release-operator-accountability-1636.md`) and decision 19:14 §10 (admin `docs/platform/2026-11-05-centralise-development-claude-parallel-agents-1914.md`). Process record: admin `docs/platform/processes/intake-dates.md`. Workstream D, branch `cf247-intake-progress-ui`, migration `20261106400000_cf247_intake_automation_progress.sql`.

**What the operator sees.** Layer 2/3 Operations › Intake Run & Validate › Process results now opens with a persistent **Automation progress: intake dates** section. It follows the 19:14 §10 order: current state → work processed → data admitted → data published → failures → next action → historical evidence. Every count comes from persisted records. The browser computes nothing.

## 1. What is shown, and where each value comes from

| Section (16:36) | Shown | Source records |
|---|---|---|
| §3A Current state | Enabled, paused, switched off, running, waiting (healthy idle), failed or stalled; last run (pg_cron run id, start, finish); running run id; last success; next run; batch, provider and pilot shares; pilot scope; rate per hour over 24 hours; pending eligible work; held or blocked work; AI and Firecrawl use. "The last run completed but admitted no value" is shown beside a green job state. | `cron.job`, `cron.job_run_details`, `pipeline.automation_catalogue`, `pipeline.component_register`, settings, `pipeline.course_intake_date_events`, `pipeline.course_intake_dates`, the saved `intake-dates` and `intake-recovery` measurements in `pipeline.process_results` |
| §3B Funnel (each run or window) | 1 eligible (pending work now), 2 selected, 3 examined, 4 evidence found, 5 dates extracted, 6 dates validated, 7 admitted, 8 published, 9 refused or held, 10 awaiting the next revisit | `pipeline.course_intake_date_events` (one row per intake row per run). Selected = admitted + nothing new + refused or held, row for row. |
| §3C Universities | One row for each pilot university (`security.intake_ui_scopes_v1()`) and for each other provider processed in the window. Columns: state, pending, selected, eligible (validated), admitted, published, held (withdrawn), last run, next revisit, and course drill-down | as above |
| §3D History | Latest run, last 24 hours, last 7 days and last 30 days. Gross activity (rows and runs: scheduled, Run Now) is shown apart from net data gain (admitted − withdrawn). The run list gives each run's kind and its pg_cron run id. | as above |
| §3E Failures | Every failed or held row, grouped by class with the count needing a person. Each row shows its class, exact reason, university and course, evidence version (calendar set, reader, evidence year, rule, calendar document), last attempt, next action, next revisit or trigger, open integration issue, whether the platform recovers automatically, and whether a person must act. | `pipeline.course_intake_dates`, `pipeline.integration_issues` |
| §4 Controls | Pause or Resume of `intake-dates-apply`. A button opens Preview, Run Now and Verify publication in Intake Run & Validate on the same page. Review blockers links to Layer 4 and, for PIM Admin and above, the Integration queue. Saved snapshots. | existing controls only (see §3) |
| §5 Observer | Hourly snapshot (process `intake-progress`) and zero-yield routing | `pipeline.process_results`, `pipeline.integration_issues` |
| §6 Alerts | Zero yield, one university monopolising, job overdue/stalled/failed, publication mismatch and repeated deterministic failures are shown and routed. Stale calendar editions, pending human decisions, the refresh budget and a change in valid calendars are shown only, because their existing mechanisms route them. Each alert gives the affected count, evidence, last successful stage and next action. | as above |

**Not processed and zero eligible.** In the selected window:

- **Not processed** means the university has no decision row, so it was never selected.
- **Zero eligible** means it was selected and evaluated, but no row reached validation (admitted, or validated and held by a lock).
- **Eligible, not admitted** means at least one row validated and none was admitted.

Both states come from the run records. Pending work comes from the latest saved measurement (never examined) plus revisits now due. A provider outside the pilot is "Not measured" for pending work, because the hourly measurement covers the pilot only.

**Current university while a run is open.** A run is one transaction, so its decisions appear only when it commits. While the job is running, the screen shows the open run id and says so.

## 2. Automation compatibility record (decision 19:14 §6)

| | |
|---|---|
| **Reuses** | The decision records of `security.intake_dates_apply_v1` (`pipeline.course_intake_date_events`, `pipeline.course_intake_dates`, the failure-class trigger, the publication state written by `security.intake_publication_check_v1`). The hourly measurements of job `process-results` (`intake-dates`, `intake-recovery`). pg_cron run history. The pilot scope `security.intake_ui_scopes_v1()`. The existing job on/off control `public.admin_automation_control` → `security.admin_automation_control_v1`, with its role floor (rank 5 and the job's `control_rank`), its retired-job rule, its idle-flag release and its audit (`pipeline.admin_control_events`). The integration queue (`security.integration_issue_upsert_v1`, stable fingerprints, `condition_cleared_at`). The existing alert path (integration issue → `security.integration_alert_sync_v1` for P0). Settings › Pipeline settings. The existing Process results screen and its bridge. |
| **Changes** | Job `process-results` gains one call, `security.intake_progress_record_v1()`. The migration checks the live command before it extends it, and its catalogue description says so. `src/ProcessResults.jsx` mounts the section. `src/process-results-api.js` gains `progress` (read) and `control` (Pause/Resume only). One index, `course_intake_date_events_run_idx` on `run_at`, so the latest run and the windows are bounded reads. Nothing in processing reads it. |
| **Replaces** | Nothing. |
| **Retires** | Nothing. |
| **Conflicts** | None with the intake scheduler or processing: `intake_dates_plan_v3`, `intake-dates-apply`, `intake_course_applicability_v1`, withdrawals and the intake settings are not edited (s340 checks the migration text). The generic progress contract (`pipeline.progress_transitions`, `security.progress_measure_v1`, md5 `40c0c972…`, scholarship and AER chains only) does not cover intake. Adding intake to it means editing that 28 KB function, which is out of D's ownership. The observer here uses the same zero reasons (`no_eligible_work`, `correctly_excluded`, `technical_failure`) and the same fingerprint routing. Whether to fold intake into that contract is a decision for the Integration Controller (dependency D-1). |
| **Protects** | The consumer API is not read or changed (G3). No new job, scheduler, queue, notification system or dashboard. The only write reachable from the screen is the existing Pause/Resume, which keeps its role check, retirement rule and audit. Expected absence of evidence raises no issue. Issues are P2 (P0 alerting is unchanged). Read functions are SECURITY DEFINER with `search_path ''` and the Operations read check (rank 3), as `admin_process_results_v1`. Helpers are revoked from `authenticated`. Pipeline tables keep RLS with no grants. |
| **Validates** | `tests/fixtures/intake-progress/run.sh`: production shapes and 16 live definitions (md5 = production), the migration applied twice, and 22 SQL cases. `benchmark.sh`: production volume and beyond. `tests/integration-progress/intake-progress-postgres.spec.mjs`: browser to PostgreSQL, desktop and phone. `tests/uat/cf-247-s340-intake-automation-progress.spec.mjs`: bridge and scope contract. Governance s32, s42, s57, s120 and s121 pass, and s288 (existing Process results) passes unchanged. |

## 3. Settings (G2, Settings › Pipeline settings › Process results)

| Key | Default | Range | Used by |
|---|---|---|---|
| `intake_progress.stall_minutes` | 90 minutes | 30–1440 | status: stalled; observer: job overdue |
| `intake_progress.runs_listed` | 24 runs | 5–200 | run list per window |
| `intake_progress.failure_rows` | 50 rows | 10–500 | failure list |
| `intake_progress.university_rows` | 60 providers | 10–500 | university table |
| `intake_progress.zero_yield_runs` | 3 runs | 1–24 | zero-yield and monopoly checks |
| `intake_progress.monopoly_share_pct` | 80 per cent | 50–100 | monopoly check |

The four history windows (latest, 24 hours, 7 days, 30 days) are the ones named in 16:36 §3D. They are marked `-- fixed:` in the migration.

**Zero-yield rule (16:36 §5).** The last `zero_yield_runs` scheduled runs admitted nothing, yet rows reached validation (held by a lock) or failed for a platform reason (`calendar_interpretation_failed`, `consumer_publication_failed`, unclassified). This is recorded as `technical_failure` and routed under fingerprint `intake-progress:zero-yield`. Runs whose rows only lack evidence are `correctly_excluded` and raise nothing.

## 4. Production schema relied on (read only, fxcwkweaxjtknorudmwp, 5 Nov 2026 19:18–19:35 AEDT)

**Tables.** Reproduced in `tests/fixtures/intake-progress/parity-tables.sql` with live columns, types, defaults, NOT NULL, checks, keys, foreign keys, indexes, triggers, RLS and grants:

- **Pipeline:** `course_intake_date_events` (BEFORE INSERT trigger `intake_failure_class`), `course_intake_dates` (outcome check: `filled`, `nothing_new`, `skipped`; FK to `catalogue.course_intakes`; trigger `intake_failure_class`), `process_results`, `integration_issues` (generated `issue_ref`; workstream A1–A10, severity, status, root cause and validation-layer checks; trigger `ops_guard_issue`), `integration_issue_events` (kind check), `admin_control_events` (identity `id`), `automation_catalogue`, `platform_toolset_settings` (kind check, FK to `platform_toolsets`), `component_register`.
- **pg_cron:** `cron.job` and `cron.job_run_details` (RLS policies).
- **Security:** `security.roles` and `security.user_roles`.
- **No grants:** none of these tables grants anything to `authenticated` or `anon`, and none has a policy.

**Reduced to the columns read.** `catalogue.providers`, `courses`, `course_intakes`, `ref.countries` and `ref.provider_types` keep the columns read here, with their live types, keys and foreign keys. `pim.entity_registry`, `pipeline.platform_toolsets`, `scholarship_layer_settings`, `enrichment_flags` and `provider_policy_proposals` keep only the columns a live function reads.

**Stubs.** These keep the same signatures: `auth.uid()`, `cron.alter_job`, `cron.schedule`, and `security.calendar_dated_periods_v2` (which the progress layer does not call).

**Live definitions** in `live-functions.sql`. `run.sh` refuses to continue on any md5 difference.

| Function | md5 |
|---|---|
| security.current_role_rank() | d709d92dbd7a648ccf78e594d68ca980 |
| security.pipeline_num_v1(text,numeric) | 09f9b1551daf42b4a0c9795e6f30c6d4 |
| security.toolset_setting(text,text) | 678dbbc416c5188ab99b3526e68b0c4d |
| security.intake_ui_scopes_v1() | 94bae55f4ecfeca5957f17a0327ba660 |
| security.integration_issue_allowed_v1(text,text) | 0854285323de4ea519089ce6394f96fc |
| security.integration_issue_upsert_v1(jsonb,text) | f9d7bf1a6dbe94ba97c34f10817f56c1 |
| security.automation_batch(text) | 9d0f6ac4fecba4469ef01b25354e34e3 |
| security.admin_automations_read_v1() | 419aef5d1f13e46081a35f23b01d6a15 |
| security.job_idle_flag_person_release_v1(text,text) | 1f69edfe8ca8f8515a2559991076f2c9 |
| security.admin_automation_control_v1(text,text,jsonb) | 431aff603f21b8c8a030073b07a08259 |
| public.admin_automation_control(text,text,jsonb) | b032f84e705b926ce7026f209116111a |
| security.ops_remedy_guard_active_v1() | 5f2ec6b47ce55213c0e90bb46649c844 |
| security.ops_guard_issue_v1() | bb7c1d67a645f52e27a6f7ad184553af |
| security.intake_failure_class_v1(…) | 969ebc2cb266f0024d3f4511dc4515a0 |
| security.intake_failure_class_trg_v1() | 1ce780aa6cbde2c9a1d9307c3cd68a53 |
| public.admin_process_results_v1(text,jsonb) | 6b1097934385d72ac15afce6b781d6ab |

**Guards in the migration.** The migration itself checks six of these md5 values: `intake_ui_scopes_v1`, `integration_issue_upsert_v1`, `admin_automation_control_v1`, `admin_automation_control`, `pipeline_num_v1` and `current_role_rank`. It also checks the live `process-results` command:

```
select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1()
```

**Live intake facts at the time of reading:**

- `intake-dates-apply` runs at `26 * * * *` with a batch of 200, pilot share 60% and provider share 25.
- `process-results` runs at `53 * * * *`. Both jobs have `control_rank` 5.
- Volumes: 1,612 decision rows (each scheduled run writes 200), 10,270 intake states, 124,226 pg_cron run rows and 300 integration issues.

## 5. Bounded performance (benchmark.sh, local PostgreSQL 16, 2 shared CPUs)

The benchmark loads 30 days of hourly 200-row runs (144,000 decision rows over 50 providers), 12,000 intake states, 130,000 pg_cron rows and 300 issues. Each view is timed as the Operations reader:

| View | Time |
|---|---|
| status | 85 ms |
| latest run | 177 ms |
| 24 hours | 222 ms |
| 7 days | 301 ms |
| 30 days | 567 ms |
| runs, 30 days | 12 ms |
| failures | 26 ms |
| saved snapshots | 1 ms |
| observer | 341 ms |

A second run on the same shared machine, with other agents' work running, had its slowest view at 1,025 ms. The bridge's statement time-out is 20 s, and the benchmark fails above 3 s.

## 6. Release and acceptance (for the Integration Controller)

1. Apply `20261106400000`. It refuses if any guarded md5 or the `process-results` command differs.
2. At the next `:53`, the `process-results` run writes the first `intake-progress` snapshot.
3. The observer may raise these issues in production straight away:
   - `intake-progress:publication-mismatch`, if any admitted value is not in the Website API source;
   - `intake-progress:zero-yield`, if the last three scheduled runs admitted nothing while rows failed for a platform reason. The 5 Nov runs had 45 `calendar_interpretation_failed` rows in 7 days.

   Both are P2 in workstream A8 and are expected evidence, not regressions.
4. Open Process results. Compare its latest run and 24-hour counts with the decision records.
