# Intake Automation Progress (Process results › Automation progress)

**Mandate:**
- Platform Admin decision 5 Nov 2026 16:36 §3–§8 (admin `docs/platform/2026-11-05-pr882-release-operator-accountability-1636.md`).
- Decision 19:14 §10 (admin `docs/platform/2026-11-05-centralise-development-claude-parallel-agents-1914.md`).
- Decision 20:03 on PR #889 (admin `docs/platform/2026-11-05-intake-milestone-pr877-pr889-decisions-2003.md`): "Reuse the existing generic progress observer wherever practicable, rather than introducing overlapping issue-detection mechanisms. Preserve its intake-specific Admin UI, historical results, provider-level progress and failure explanations."

**Process record:** admin `docs/platform/processes/intake-dates.md`.

**Change:** workstream D, branch `cf247-intake-progress-ui`, draft PR #889, migration `20261106400000_cf247_intake_automation_progress.sql`.

## 1. What the operator sees

Layer 2/3 Operations › Intake Run & Validate › Process results opens with a persistent **Automation progress: intake dates** section. It follows the order set in 19:14 §10: current state, work processed, data admitted, data published, failures, next action, historical evidence. Every count comes from persisted records.

| Section (16:36) | Shown | Source records |
|---|---|---|
| §3A Current state | The job is shown as enabled, paused, switched off, running, waiting (healthy idle), failed or stalled. Also shown: last run (with its pg_cron run id), open run id, last success, next run, batch, provider and pilot shares, pilot scope, rows per hour over 24 hours, pending and held work, and AI and Firecrawl use. "The last run completed but admitted no value" appears beside a green job state. | `cron.job`, `cron.job_run_details`, `pipeline.automation_catalogue`, settings, the decision records, and the saved `intake-dates` and `intake-recovery` measurements |
| Progress observer | The generic observer's latest reading of the three intake stages (selection, admission, publication). For each stage: eligible, processed and created counts, the zero reason, whether it is stalled, and its issue. "Observer readings" lists the stored history. | `pipeline.progress_transitions`, `pipeline.progress_observations` (job `first-run-verify`) |
| §3B Funnel | Ten steps from persisted decisions. Selected = admitted + nothing new + refused or held, row for row. | `pipeline.course_intake_date_events` |
| §3C Universities | One row per pilot university (`security.intake_ui_scopes_v1()`) and one per other provider processed in the window, with course drill-down. | as above |
| §3D History | Latest run, 24 hours, 7 days or 30 days. Gross activity is shown apart from net gain (admitted minus withdrawn). Each run in the list carries its pg_cron run id. | as above (all history, at full detail) |
| §3E Failures | Each row shows its class, exact reason, course, evidence version, last attempt, next action, next revisit or trigger, open issue, whether it recovers automatically, and whether a person must act. | `pipeline.course_intake_dates`, `pipeline.integration_issues` |
| §4 Controls | Pause and Resume use the existing `public.admin_automation_control`. Preview, Run Now and Verify publication sit in Intake Run & Validate. Blockers are reviewed in Layer 4 and the integration queue. | existing controls |
| §6 Alerts | Each alert gives the affected count, evidence, last successful stage and next action. It also names the observer that raises it, its fingerprint and its open issue. | see §2 |

**University states:**
- **Not processed:** the university was not selected in the window.
- **Zero eligible:** it was selected and evaluated, but no row reached validation.
- **Eligible, not admitted:** a row validated, but none was admitted.

## 2. One condition, one fingerprint (decision 20:03)

The generic progress contract was introduced on 4 Nov 2026 08:16 (job `first-run-verify` at :02 and :32, `security.progress_read_v1` → `security.progress_measure_v1` and `security.progress_zero_reason_v1`). Intake is now one more chain of it:

| Transition | Eligible | Created | A technical zero, stalled for `progress.stall_hours`, raises |
|---|---|---|---|
| `intake_selection` (Selection and evaluation; producer `intake-dates-apply`) | Active intake rows missing a value that were never decided, plus decided rows whose revisit is due | Rows decided since the window start | `stall:intake_selection`: the job runs but decides nothing, or does not run |
| `intake_admission` (Admission) | Rows decided in the window | Values admitted | `stall:intake_admission`: **zero yield** |
| `intake_publication` (Consumer publication; producers `intake-dates-apply`, `process-results`) | Values admitted in the window | Admitted values found in the Website API v2 source | `stall:intake_publication`: nothing admitted reaches the consumer source |

**How zeros are read.** Zero reasons are the contract's own: `no_eligible_work`, `blocked_authority` (all producing jobs paused), `correctly_excluded` and `technical_failure`.

For admission, a row counts as **correctly excluded** when it is "nothing new", or refused for missing evidence or a person's decision. Those classes are:
- `no_valid_calendar_source`, `stale_calendar_edition`, `wrong_institution_or_campus`
- `course_identity_unresolved`, `academic_year_unproven`, `no_matching_commencement_period`, `multiple_periods_match`
- `course_level_exception`, `missing_application_deadline_evidence`, `waiting_for_next_academic_year`

So runs whose rows only lack evidence raise nothing. A row that validated but is held by a lock, a reader failure or an unclassified row makes the zero technical. Issues of the intake chain are filed under layer "Layer 2" and workstream A8. Scholarship and AER keep "Scholarships"/"AER" and A7.

**Intake checks the contract cannot express.** `security.intake_progress_checks_v1()` is called once by `progress_read_v1` after its loop, isolated by its own exception block:

| Fingerprint | Why the transition contract cannot express it |
|---|---|
| `intake-progress:monopoly` | It needs a per-provider share of recent scheduled runs. The contract has no provider dimension. |
| `intake-progress:publication-mismatch` | Some admitted values are not published while others are, so the publication transition still advances and never stalls. It is raised only while `intake_publication` is not stalled. When nothing publishes, the condition is `stall:intake_publication` and this issue is marked cleared, so one condition never carries two fingerprints. |
| `intake-progress:repeated-deterministic` | A per-row invariant: a deterministic failure must not be decided again under unchanged inputs (mandate 12:44 §9). It is not a throughput measure. |

**Shown only**, because existing mechanisms route them:
- stale calendar editions (process-results calendar flags);
- pending human decisions (Layer 4);
- the calendar refresh budget;
- valid calendars changed since the previous measurement.

The screen's own "stalled" job state uses `intake_progress.stall_minutes` (90) for display only. The issue for a job that stops deciding rows is the observer's `stall:intake_selection`.

## 3. Automation compatibility record (decision 19:14 §6)

**Reuses**
- The generic progress contract: transitions and observations tables, measure, zero reason, observer, job `first-run-verify`, its window and stall settings, its fingerprints and its issue routing.
- The intake decision records, and the publication state written by `security.intake_publication_check_v1`.
- The process-results measurements: `intake-dates` (never examined, AI cost) and `intake-recovery` (refresh credits).
- The pg_cron history and the pilot scope.
- The existing job toggle and its audit.
- The integration queue: `security.integration_issue_upsert_v1`, `condition_cleared_at`, and P0 alert sync through `security.integration_alert_sync_v1`.
- Settings › Pipeline settings, and the existing Process results screen and bridge.

**Changes**
- `security.progress_measure_v1`: an md5-guarded additive edit (40c0c972) adds three keys before its final `else`. Every existing branch is byte for byte unchanged.
- `security.progress_read_v1`: an md5-guarded edit (f11ed22d). Intake issues are filed as layer "Layer 2" and workstream A8, the intake checks run after the loop, and the result gains an `intake` key when that chain exists.
- `pipeline.progress_transitions`: the `chain` check is widened to scholarship, aer and intake, and three intake transitions are added.
- One index, `course_intake_date_events_run_idx` on `run_at`, keeps the window reads bounded. Processing does not read it.
- `src/ProcessResults.jsx` mounts the section. `src/process-results-api.js` gains `progress` (read) and `control` (Pause/Resume only).
- `security.self_sustainability_v1` counts every transition, so its totals now include the three intake transitions. Its scholarship and AER figures read named keys and are unchanged.

**Replaces**
- Nothing in production.
- In this PR, the earlier draft's own observer is replaced: the process-results snapshot, the `process-results` command edit, and `intake-progress:zero-yield` / `:job-overdue`. They are now the generic observer's `stall:intake_*`. None of these was ever deployed.

**Retires**
- Nothing.

**Conflicts**
- Held PR #875 also edits `security.progress_measure_v1`: it guards 40c0c972 and produces 4f10e10e. Whichever lands second must be re-guarded on the other's result. This migration refuses any definition other than 40c0c972 (tested).
- There is no conflict with the intake scheduler or processing. `intake_dates_plan_v3`, `intake-dates-apply`, `intake_course_applicability_v1`, withdrawals and the intake settings are not edited.
- No job is added or changed. Job `process-results` keeps its command.

**Protects**
- The consumer API is untouched (G3).
- Scholarship and AER outputs of the measure and of the observer are unchanged (proved below).
- One fingerprint per condition.
- Expected absence of evidence raises nothing.
- Read functions are SECURITY DEFINER with `search_path ''` and the rank 3 check. Helpers are revoked from `authenticated`. Pipeline tables keep RLS with no grants.
- Pause/Resume keeps its role check, retirement rule and audit.

**Validates**
- `tests/fixtures/intake-progress/run.sh` covers:
  - 19 live definitions, each md5 = production;
  - the regression proof;
  - refusal of a non-live `progress_measure_v1`;
  - the migration applied twice with no change;
  - no job added or changed;
  - 24 SQL cases.
- `benchmark.sh`.
- `tests/integration-progress/intake-progress-postgres.spec.mjs`: browser to PostgreSQL, desktop and phone.
- `tests/uat/cf-247-s340-intake-automation-progress.spec.mjs`.
- s32, s42, s57, s120, s121 and s288.

### Regression proof (scholarship and admission requirements unchanged)

`tests/fixtures/intake-progress/regression.sql` runs against the production shapes of the 25 tables the live measure reads (`progress-tables.sql`). Each table holds synthetic rows: checked columns take their allowed values in turn, and other text columns take the literals the measure compares with. Then, in one transaction (one `now()`):

1. All 19 existing keys are measured with the live definition.
2. One observer reading of the scholarship and AER chains is taken: transitions, observations and the stall issues with their layer and workstream.
3. The migration is applied.
4. Steps 1 and 2 are repeated.

Results:
- **Identical**, except `first_run_verify.eligible`, which counts the transitions the observer reads (16 → 19, by design).
- **Structural check:** the new `progress_measure_v1` with the inserted intake block removed has md5 40c0c972, the live definition.

## 4. Settings (G2, Settings › Pipeline settings › Process results)

| Key | Default | Range | Used by |
|---|---|---|---|
| `intake_progress.stall_minutes` | 90 minutes | 30–1440 | screen state "stalled" (display) |
| `intake_progress.runs_listed` | 24 runs | 5–200 | run list per window |
| `intake_progress.failure_rows` | 50 rows | 10–500 | failure list |
| `intake_progress.university_rows` | 60 providers | 10–500 | university table |
| `intake_progress.monopoly_runs` | 3 runs | 1–24 | monopoly check |
| `intake_progress.monopoly_share_pct` | 80 per cent | 50–100 | monopoly check |

- **Existing settings that now also apply to intake:** `progress.on`, `progress.window_hours` (24) and `progress.stall_hours` (6).
- **Fixed windows:** latest, 24 hours, 7 days and 30 days are the windows named in 16:36 §3D (`-- fixed:`).

## 5. Production schema relied on (read only, fxcwkweaxjtknorudmwp, 5 Nov 2026 19:18–20:10 AEDT)

**`parity-tables.sql`** reproduces the intake tables with live columns, types, defaults, NOT NULL, checks, keys, foreign keys, indexes, triggers, RLS and grants:
- `course_intake_date_events`, with trigger `intake_failure_class`;
- `course_intake_dates`, with its outcome check, its FK and its trigger;
- `process_results`;
- `integration_issues` (generated `issue_ref`, its checks, trigger `ops_guard_issue`);
- `integration_issue_events`;
- `admin_control_events` (identity `id`);
- `automation_catalogue`, `platform_toolset_settings`, `component_register`;
- `cron.job` and `cron.job_run_details`;
- `security.roles` and `security.user_roles`.

The catalogue and reference tables keep only the columns read here, with their live types and keys. `auth.uid()`, `cron.alter_job` and `cron.schedule` are stubs with the same signatures.

**`progress-tables.sql`** reproduces the 27 tables the generic contract reads, generated from production: columns, types, defaults, NOT NULL, generated columns, and primary, unique and check constraints. It leaves out secondary indexes and triggers, and foreign keys except the three on the two contract tables.

**`seed.sql`** holds:
- the sixteen live transitions;
- the live `first-run-verify` command and its catalogue label, area, sort and control rank;
- the `progress.*` settings.

**Live definitions (md5 = production; `run.sh` refuses any difference):**

| Function | md5 | |
|---|---|---|
| security.current_role_rank() | d709d92dbd7a648ccf78e594d68ca980 | guarded in the migration |
| security.pipeline_num_v1(text,numeric) | 09f9b1551daf42b4a0c9795e6f30c6d4 | guarded in the migration |
| security.toolset_setting(text,text) | 678dbbc416c5188ab99b3526e68b0c4d | |
| security.intake_ui_scopes_v1() | 94bae55f4ecfeca5957f17a0327ba660 | guarded in the migration |
| security.integration_issue_allowed_v1(text,text) | 0854285323de4ea519089ce6394f96fc | |
| security.integration_issue_upsert_v1(jsonb,text) | f9d7bf1a6dbe94ba97c34f10817f56c1 | guarded in the migration |
| security.automation_batch(text) | 9d0f6ac4fecba4469ef01b25354e34e3 | |
| security.admin_automations_read_v1() | 419aef5d1f13e46081a35f23b01d6a15 | |
| security.job_idle_flag_person_release_v1(text,text) | 1f69edfe8ca8f8515a2559991076f2c9 | |
| security.admin_automation_control_v1(text,text,jsonb) | 431aff603f21b8c8a030073b07a08259 | guarded in the migration |
| public.admin_automation_control(text,text,jsonb) | b032f84e705b926ce7026f209116111a | guarded in the migration |
| security.ops_remedy_guard_active_v1() | 5f2ec6b47ce55213c0e90bb46649c844 | |
| security.ops_guard_issue_v1() | bb7c1d67a645f52e27a6f7ad184553af | |
| security.intake_failure_class_v1(…) | 969ebc2cb266f0024d3f4511dc4515a0 | |
| security.intake_failure_class_trg_v1() | 1ce780aa6cbde2c9a1d9307c3cd68a53 | |
| public.admin_process_results_v1(text,jsonb) | 6b1097934385d72ac15afce6b781d6ab | |
| security.progress_measure_v1(text,timestamptz) | 40c0c972abc353be8f6eee35c79750e9 | **edited** (md5-guarded) |
| security.progress_zero_reason_v1(text,jsonb) | 746d7baedb0a79dc0a6fbfead82f67c2 | guarded in the migration |
| security.progress_read_v1() | f11ed22d149eb06aa10387e67467ec6f | **edited** (md5-guarded) |

The three generic functions were rebuilt from migrations `20261104460000` and `20261104520000`, and each rebuild's md5 equals production. Their callers (live) are `security.first_run_verify_tick_v1` (9df7a97b), `security.first_run_verify_jobs_v1`, `security.release_first_run_register_v1` and `security.self_sustainability_v1` (1965a719). None of them is edited.

**Live facts:**
- Jobs:
  - `intake-dates-apply`: `26 * * * *`, batch 200, pilot share 60%, provider share 25;
  - `process-results`: `53 * * * *`;
  - `first-run-verify`: `2,32 * * * *`, control rank 6.
- Generic contract:
  - 16 transitions (scholarship 9, AER 7);
  - about 1,072 observations;
  - `progress.window_hours` 24, `progress.stall_hours` 6.
- Volumes:
  - 1,612 decision rows;
  - 10,270 intake states;
  - 124,226 pg_cron rows;
  - 300 integration issues.

## 6. Bounded performance (benchmark.sh, local PostgreSQL 16, 2 shared CPUs)

The benchmark uses 30 days of hourly 200-row runs (144,000 decision rows), 12,000 intake states, 130,000 pg_cron rows and 300 issues.

| Read | Time |
|---|---|
| status | 86 ms |
| latest run | 154 ms |
| 24 hours | 223 ms |
| 7 days | 298 ms |
| 30 days | 583 ms |
| runs, 30 days | 12 ms |
| failures | 22 ms |
| observations | 1 ms |
| one whole observer reading, all chains (`progress_read_v1`) | 104 ms |

The benchmark fails above 3 s. The bridge's statement time-out is 20 s. In production (read only, 5 Nov 2026 20:26 AEDT, while the :26 intake run was executing), the three intake measures together took 651 ms (EXPLAIN ANALYZE). The selection count scans 37,434 intakes and 44,391 courses and finds 21,147 rows waiting; it runs once every 30 minutes in the observer.

## 7. Release and acceptance (for the Integration Controller)

1. Apply `20261106400000`. It refuses if a guarded md5 differs, including `progress_measure_v1` when #875 has landed first.
2. At the next `:02` or `:32`, job `first-run-verify` reads the intake chain: three new rows in `pipeline.progress_transitions` and their observations.
3. Its first readings may raise:
   - `intake-progress:publication-mismatch`, if any admitted value is not in the Website API source;
   - `stall:intake_admission`, if no value was admitted in the last 6 hours while rows failed for a non-excluded reason.

   Both are P2, workstream A8. They are evidence, not regressions.
4. Open Process results and compare the observer table, and the latest-run and 24-hour counts, with `pipeline.progress_transitions` and `pipeline.course_intake_date_events`.
