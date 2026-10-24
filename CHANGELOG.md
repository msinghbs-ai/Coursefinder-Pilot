# Changelog

## 0.1.277 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.350** (R2 / C-Q1; O10 approved 24 Oct). Migration `20261024013000_cf247_r2_daily_cap_course_stop.sql`: settings `search.daily_picked_cap` (100, 10–2,000 a UTC day) and `search.stop_per_course_after` (6, 3–20); index on `course_link_search.sent_at`; md5-guarded edits to `svc_course_link_search_next` (cap counted from today's picks; a person's running task counted but not held; per-course stop from `page_rejections`) and `link_search_block_v1` (stall cause `daily_cap`). Tranche 1 (25 override rows) is applied after the deploy by its paste file. Test s102. Release notes v2.15.349. SOPs 1.91.

## 0.1.276 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.349** (Platform Admin 24 Oct 19:23, D1.4: target rule reasons). Migration `20261024012000_cf247_target_rule_reason.sql`: column `pipeline.firecrawl_target_cache.rule_reason`; `security.firecrawl_target_rule_reasons_v1()` (first failing condition, rule order); md5-guarded edits to `firecrawl_targets_refresh_v1` (fills it each minute), `admin_firecrawl_read` and `admin_adapters` (carry it). Screens say why a university is not matched. Rule, inclusion and settings unchanged. Test s101. Release notes v2.15.348. SOPs 1.90.

## 0.1.275 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.348** (Platform Admin 24 Oct 18:27, "Campus name and UI filter"). Presentation only, no migration: Campuses list gains a Provider filter (`provider_id`, already accepted by `admin_campus_page_fast`; reset with country or state), first column "Location name"; Provider details › Campuses pills show the location name with the course count (city in the hover); lists show a nameless provider as "Unnamed on the register". The stored names already equal the CRICOS location names (3,984 of 3,984). Test s100; ui-standard expectation updated. Release notes v2.15.347. SOPs 1.89.

## 0.1.274 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.347** (HOTFIX 3 — Task manager timed out, Platform Admin 24 Oct 15:51, ref 9F5R4H). Migration `20261024011000_cf247_hotfix3_task_status_speed.sql`: `security.link_search_block_v1` (md5-guarded) checks the stop for the one university (`fc_search_stopped_for_v1`, 0.09 s instead of 1.7 s), works out the month and day totals once per statement, and asks "a person's task?" in one query. Dry run on live: Task manager read 0.74 s (was over the 8 s limit). Gates, order and words unchanged. Test s99 (5th test). Release notes v2.15.346. SOPs 1.88.

## 0.1.273 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.346** (UI audit Phase 1 — strip internals from list views; Platform Admin 24 Oct 11:27). Not merged without Platform Admin review; stacked on v2.15.345.
  - Presentation layer only, no migration: stable keys, GUID course codes, hashes, UUID fragments, HTTP codes, raw cron and route text, job slugs, Decision references, raw state strings and vendor balances leave list views; every value stays reachable (detail "Identifiers (for support)" for Curator+, hover titles, `data-*`). `src/lib/viewer.js` (role context; balances as figures for Platform Admin, rank 6), `fmtPeriod` in `src/lib/format.js`. Test s98; five specs' expectations updated. SOPs 1.87. Release notes v2.15.345.

## 0.1.272 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.345** (UI audit Phase 3 — dedupe and data-quality leaks; Platform Admin 24 Oct 11:27). Not merged without Platform Admin review; stacked on v2.15.344.
  - Dashboard: one Inbox total (opens Layer 4 Review `?view=kind`), no per-kind duplicate; Scholarships tile reconciled (published · active · retired) from additive dashboard keys (migration `20261024008000`, md5-guarded edit of `admin_dashboard_maturity_compute`; snapshot refreshed). Provider contacts: duplicated header removed. Ranking imports kicker under its own screen. Unnamed register records ("N/A", "--") shown as "Unnamed on the register (code)". One campus city corrected (count-guarded). Test s97; dashboard contract updated. SOPs 1.86.


## 0.1.271 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.344** (UI audit Phase 2 — course list; Platform Admin 24 Oct 11:27). Not merged without Platform Admin review; stacked on v2.15.341.
  - Migration `20261024007000_cf247_ui_audit_phase2_course_list.sql` (md5-guarded edit of `admin_course_page_fast_base`): `intl_fee_basis` on the list row; sort keys `intl_fee` and `city`. Admin read path only.
  - Courses list: International fee shows amount, year and basis; International fee and City sort. Test s96. SOPs 1.85.


## 0.1.270 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.343** (HOTFIX 2 — found in the v2.15.342 post-merge check). Migration `20261024010000_cf247_hotfix2_person_task_spend_gate.sql`: `public.svc_fc_spend` (md5-guarded) lets a person's waiting or running Find course pages task past the search stop, as the picker does (406 refusals for Otago on 24 Oct); `security.admin_job_status_v1` (md5-guarded): for Find course pages the stall clock follows credits spent and a credit refusal is the blocking reason (`credit_refused`). Budgets, caps and target-only unchanged. Test s99 (4th test). Release notes v2.15.342. SOPs 1.84.

## 0.1.269 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.342** (HOTFIX — manual task and Layer 4 entry; Platform Admin 24 Oct 13:17). Not merged without Platform Admin review.
  - Migration `20261024009000_cf247_hotfix_manual_task_and_layer4_entry.sql`: settings `search.person_task_bypass` (1) and `tasks.stall_seconds` (60); `security.link_search_person_task_v1`, `link_search_block_v1` (stall cause in gate order), `admin_job_status_v1`, `layer4_fee_item_rebind_v1`; md5-guarded edits to `svc_course_link_search_next` (a person's running task passes the search stop and the bulk check only), `worker_mode_waiting_v1`, `provider_task_fire_v1` / `provider_task_prepare_v1` (forward on accept with the minute job's body; D-target_only: refused at start at a non-target university, gate named), `admin_job_watch_v1` (closing note names the gate), `admin_jobs` read (`status`), `admin_layer4_inbox` (held-fee enter → `admin_course_edit set_official_url`), `gap_causes_snapshot_v1` (new non-automatic cause). No gate, budget or cap changed.
  - `src/AdminTasks.jsx` status line and blocked chip; `src/Layer4Inbox.jsx` fee items: no "Use the new page", https only. Test s99. Release notes v2.15.341. SOPs 1.83.

## 0.1.268 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.341** (UI audit Phase 0 — incidents; Platform Admin 24 Oct 11:27). Not merged without Platform Admin review.
  - `src/lib/errors.js`: `plainError` / `scrubInternals` / `reportError` — one plain reading of any error, no `ERROR:`/`CONTEXT`/function signatures/vendor or job names; the global banner gets a reference and the full detail goes to `pipeline.ui_error_log` (`public.admin_ui_error_report`). Every panel's `errText` routes through it; Platform health titles/details and Automations' last-error use it; the banner is cleared on navigation (root cause of the banner following a person to Go-live, Users & roles and Guides).
  - `DeployedVersionNotice`: reads `release-history.json` after sign-in, on navigation and every 5 minutes; offers a reload when the deployed version differs (root cause of v2.15.339 in the top bar vs v2.15.340 in a screen: a cached shell with new lazy chunks).
  - Migration `20261024006000_cf247_ui_audit_phase0.sql`: `pipeline.ui_error_log` + `admin_ui_error_report` + `retention.ui_error_log_days`; `coverage_admission_apply_v1` never applies a plain `http://` address by rule (the job had failed every run since 23 Oct 11:40 UTC; 187 such rows now wait for a person); `course_completeness_build_v1` counts readable attributes for "fully complete" (5,660 → 0 on 20 Oct was three no-reader attributes joining the matrix); `ledger_retention_v1` replaced (md5-checked).
  - Coverage panel: the trend table says why 20–24 Oct read 0. Release notes files for v2.15.339 and v2.15.340 (the pill had shown the v2.15.338 notes). Test s95. SOPs 1.82.

## 0.1.267 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.340** (R3: hourly health delta; Platform Admin 24 Oct 09:55).
  - Migration `20261024005000_cf247_r3_health_hourly.sql`: `pipeline.health_snapshots`; `security.health_hourly_v1()` at :11 (job `health-hourly`) writes headline, fields_delta per country, lane_wait, ledger, idle, bound_empty, negative_movers and budget_burn from the 15-minute stats, the R1 ledger, the queue-wait function and the watchdog state; `security.health_latest_v1()` for the report; settings `health.*` (7) and `retention.health_snapshots_days`; `ledger_retention_v1` replaced (md5-checked) to keep health rows too; `stats.countries` setting (NZ, AU, CA) replaces the country list carried in the `stats-15m` job command. Test s94. SOPs 1.81.

## 0.1.266 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.339** (R1: empty-tick backoff cap, per-mode ledger, why-idle line, apply-time identity check; Platform Admin 24 Oct 09:55).
  - Migration `20261024004000_cf247_r1_backoff_ledger_identity.sql`: setting `tick.backoff_max_minutes` (15, 1–60) caps the idle guard's trial wait (`flag_jobs_v1`, md5-guarded); `worker_mode_waiting_v1` gains a "work is waiting" test for every paused-prone lane (13 modes) so the 10-minute flag recheck wakes a lane as soon as its queue is fed; `pipeline.mode_outcome_ledger` + `public.svc_worker_report_v1` (one row per worker call) + `security.lane_queue_wait_v1` (queue wait p50/p90/max per lane) + job `ledger-retention` daily 03:37 UTC (also removes old zero-yield snapshots, which v2.15.338 left to a job that never did); `pipeline.queue_watch.upstream_key` + `security.lane_why_idle_v1` shown on the Work queues screen (`admin_queue_watch`, md5-guarded); 219 University of Sydney companion data files get their attempts back (count-guarded); `coverage_apply_course_v1` quarantines a fee whose bound page carries a proof the country's tuition policy refuses (`fee_quarantined_identity`, Layer 4 source `identity_basis_reverify`; manual exempt; md5-guarded).
  - Worker `coverage-sweep-worker-v0.46.0`: every call reports to the ledger after its answer is built; a `.json` address that answers with HTML is read as the page. Test s93. SOPs 1.80.

## 0.1.265 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.338** (zero-yield page re-acquisition; Platform Admin 24 Oct 07:43).
  - Migration `20261024003000_cf247_zero_yield_reacquisition.sql`: `pipeline.page_rejections` (S1 partial), `pipeline.zero_yield_snapshots`, `security.zero_yield_pages_v1` (predicate and signals), `security.zero_yield_reset_v1`, `security.zero_yield_detect_v1`, `page_rejection_bonus_v1` / `page_match_bonus_v1`; `svc_coverage_reidentify_next` and `coverage_ai_match_prepare_v1` skip rejected pages (md5-guarded); 14 settings; job `zero-yield-detect` hourly at :21. Automatic resets off by default. Test s92. SOPs 1.79.

## 0.1.264 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.337** (CRICOS proofs Australian only; Platform Admin 24 Oct 07:32).
  - Worker `coverage-sweep-worker-v0.45.0`, identity rule `identity-v0.6.0`: `cricos_code` only for AU pages; NZ code on page → `nzqa_code`; CA and others → title rules. `FC_TRUSTED_BASIS` gains `nzqa_code`, `adapter_code`.
  - Migration `20261024002000_cf247_cricos_australia_only.sql`: `coverage_identity_allowed` refuses CRICOS proofs outside AU; `cricos_code` removed from every non-AU proof list; `svc_coverage_read_record` and `coverage_bind_v2` country-aware (md5-guarded); 406 mislabelled NZ/CA bindings re-verified (count-guarded); fee requests for the 149 quarantined courses.
  - Courses list: CRICOS fee column hidden when the country filter is not AU. Tests s91 (new), s27 updated. SOPs 1.78.

## 0.1.263 — 24 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.336** (NZ brief item 5 Option A: official course link filled from the proven page; Platform Admin 23 Oct 20:42, built on the 24 Oct 00:35 mandate).
  - Migration `20261024001000_cf247_course_url_fill.sql`: table `pipeline.course_url_fills`, `security.course_url_fill_v1` (four guards), `security.course_url_retraction_30d_v1`, settings `course_url.fill_enabled`, `course_url.max_retraction_pct`, `batch.course_url_fill`, `course_url.fill_countries` (NZ), job `course-url-fill` daily 02:23 UTC. Dry run: NZ 1,874 fill (AU 16,887 and CA 1,836 would fill if the country list is widened); guard 3 proven (one unbind → one retraction, one emptied). SOPs 1.77.
  - Test `tests/uat/cf-247-s90-course-url-fill-contract.spec.mjs`.

## 0.1.262 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.335** (read lane capacity from Settings; Platform Admin 22:57 and 23:13 "Go").
  - Migration `20261023027000_cf247_read_lane_settings.sql`: setting `reading.pages_at_once` (1 to 32, 8); `svc_worker_settings_v1` returns `reading.*`; `svc_coverage_read_next` takes up to 200 pages a call (md5-guarded edits). Worker `coverage-sweep-worker-v0.44.0`: read mode up to 200 pages a call, `reading.pages_at_once` fetched at once (both were fixed at 60 and 8). SOPs 1.76. Live changes by the Platform Admin's "Go", logged: `pages.render_countries` + CA; job `coverage-read-2` on.
  - Test `tests/uat/cf-247-s89-read-lane-settings-contract.spec.mjs`.

## 0.1.261 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.334** (NZ enrichment brief Release 1: items 1, 2, 4; Platform Admin decisions 20:42, addendum 20:52, flags 20:56).
  - Migrations `20261023023000_cf247_nz_provider_transitions.sql` (table `pipeline.provider_transitions`, `security.transition_recheck_v1`, job `transition-recheck` daily 03:41, settings `transition.recheck_days` and `batch.transition_recheck`), `20261023024000_cf247_nz_provider_transitions_seed.sql` (17 rows, each with its Government source; C1 closed), `20261023025000_cf247_provider_domain_moved.sql` (`public.admin_provider_domain_moved`, same host refused), `20261023026000_cf247_fee_floor.sql` (`min_annual_international` per country, `security.fee_below_floor_v1`, md5-guarded edits to `coverage_apply_course_v1`, `svc_fee_ai_record`, `admin_pipeline_settings_read/write`; C4 pass: 20 NZ fees to `unverified`, 2 flagged; F2: NZ-only).
  - `src/AdapterBuilderTab.jsx`: "Move the course pages too" on Change website. `src/PipelineSettings.jsx`: fee floor on the country row. SOPs 1.75. Consumer API unchanged (Decision 266): a quarantined fee has status `unverified`, which the website never returns.

## 0.1.260 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.333** (AI reader load settings; OpenRouter on the Task manager). Platform Admin, 23 Oct 2026 19:27: "Lets test openrouter where it goes bottleneck, and make that settings configurable in ui as well."
  - Worker `coverage-sweep-worker-v0.43.0`: enrich_ai and fee_ai count every OpenRouter request (answered, 429, 5xx, other, timed out, answer times) and return the summary; enrich_ai pages at once from the database (at most 12, fixed); fee_ai up to 16 pages at once. Migration `20261023022000_cf247_openrouter_load_settings.sql`: `enrich.ai_calls_at_once` 1 to 40, new `enrich.ai_pages_at_once` (1 to 12, 3), `fees.concurrency` 1 to 16 (logged, values unchanged); `security.enrich_ai_fire_v1` sends pages at once; `public.admin_jobs_pulse` sums the last 15 minutes (openrouter). `src/AdminTasks.jsx`: OpenRouter line, red when more than 5% are pushed back. SOPs 1.74. Consumer API unchanged (Decision 266).

## 0.1.259 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.332** (Task manager: up to 2,000 tasks a minute). Platform Admin, 23 Oct 2026 18:42: "We should try higher setting lets try 100"; 18:45: "Keep incrementing to higher i want to test the limits".
  - Migration `20261023021000_cf247_tasks_per_lane_100.sql`: `jobs.per_lane_per_tick` range 1 to 2,000, set to 1,000 (logged); `security.admin_jobs_tick_v1` and `public.admin_jobs_pulse` cap at 2,000. Dry runs (one minute's run): 100 in 1.6 s, 250 in 3.5 s, 500 in 4.4 s, 1,000 in 12.4 s, 2,000 in 25.2 s. SOPs 1.73. Consumer API unchanged (Decision 266).

## 0.1.258 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.331** (Task manager: 40 tasks a minute, and shows it is alive). Platform Admin, 23 Oct 2026 16:40: "Yes, maximise to speed it up" (145 Read with AI tasks moving one a minute); 16:43 "can you dry run 40 task in a minute"; 16:47 "i can't trust the task manager even after refreshing it nothing seems moving".
  - Migration `20261023020000_cf247_tasks_per_lane_per_minute.sql`: setting `jobs.per_lane_per_tick` (1 to 40, set to 40, logged; dry run: 40 tasks moved in 1.3 seconds); `security.admin_jobs_tick_v1` moves up to that many tasks per lane each minute, oldest first, and stops taking more after 40 seconds (fixed: the runner is called each minute); `public.admin_jobs_pulse()` (read only, Operator or above). `src/AdminTasks.jsx`: live line (refreshed time, runner last run, red when late, waiting, running, finished in 15 minutes, AI reader backlog), each task's place in line and items. SOPs 1.72. Consumer API unchanged (Decision 266).

## 0.1.257 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.330** (values from an older wrong page; South Auckland campus). Platform Admin, 23 Oct 2026 16:02: "Take back 3,462, re-read 2,023" and "Add it, Auckland region".
  - Migration `20261023019000_cf247_older_wrong_page_values_and_south_auckland.sql`: AI values from an earlier page that was not the course's own recorded in `pipeline.enrich_value_retractions` and taken back (3,462 on courses whose page is another course's; 2,023 read again from the course's own page in one Read with AI job per university, campus re-reads queued by the admin-repo paste file `docs/platform/wrong-page-values/PASTE-20261023-older-wrong-page-campus-links.sql` after the 1,572 old links are removed); University of Auckland South Auckland campus (6 Osterley Way, Manukau) added and linked to the Diploma in Arts. SOPs 1.71. Consumer API shape unchanged (Decision 266).

## 0.1.256 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.329** (Read with AI links a campus the university already has). Read with AI on the University of Auckland diplomas (v0.42.3) read ["City","South Auckland"] but linked no campus: the campus list step kept only names given exactly, and a campus needed `enrich.campus_min_pages` (2) course pages while Read with AI reads one course.
  - Worker `coverage-sweep-worker-v0.42.4`: a campus name found inside a name given as a list is kept. Migration `20261023018000_cf247_campus_list_existing_campus_one_page.sql`: `security.enrich_campus_list_apply_v1` links an active campus of the same name from one course page; a new campus still needs the setting's pages or a person. SOPs 1.70. Consumer API unchanged (Decision 266).

## 0.1.255 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.328** (Read with AI reads labelled page data items). Read with AI on the 12 University of Auckland diplomas (13:13) found no campus, length or delivery: the catalogue holds them as display items (P5_CAMPUS, P5_DURATION_FULL_TIME, P5_DELIVERY_MODE) outside the page's main text, which the reader dropped.
  - Worker `coverage-sweep-worker-v0.42.3`: `pageDataItems` (extract.ts) gives each short labelled item as "Label: value" ahead of the main text in enrich_ai. SOPs 1.69.
  - Migration `20261023017000_cf247_ai_reader_bound_pages_only.sql`: `security.enrich_fields_slice_v1` gives the AI only the course's own page (bound, or ambiguous with an identity proof), never a page with status mismatch; 3,371 values filled from such pages since 14 Oct (1,875 delivery, 594 duration, 320 international, 1 intake, 581 campus) recorded in `pipeline.enrich_value_retractions` and taken back (Platform Admin 23 Oct 2026: "Take them all back"); 717 campus links removed by the admin-repo paste file `docs/platform/wrong-page-values/PASTE-20261023-wrong-page-campus-links.sql`. Consumer API shape unchanged (Decision 266).

## 0.1.254 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.327** (Courses list column names). Platform Admin, 23 Oct 2026 13:24: "change column name - CRICOS tuition to Tuition Only and Legacy presence - to completeness".
  - `src/mature-main.jsx` column labels. `src/Toolsets.jsx`: every notice Go to opens and scrolls to its card, also when already on that screen (Platform Admin 13:26 "go to openrouter settings doesn't open"); course-page search budget and website links fixed. No database change. Consumer API unchanged (Decision 266). SOPs 1.68.

## 0.1.253 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.326** (Courses list: international fee and city). Platform Admin, 23 Oct 2026 12:52: "Still no city or fees on these."
  - Migration `20261023016000_cf247_course_list_international_fee_city.sql`; worker `coverage-sweep-worker-v0.42.2`; `src/mature-main.jsx` columns.
  - Consumer API unchanged (Decision 266). SOPs 1.67.

## 0.1.252 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.325** (the AI reader covers every attribute; why values are missing, every hour). Platform Admin, 23 Oct 2026 10:25: "cross check the gaps and accommodate the ai reader requiement. What is point of hourly reporting if you are not finding gaps and making the platform self sufficient."
  - Migration `20261023012000_cf247_ai_reader_every_attribute_and_gap_causes.sql`: Enrich fields english, intakes, campus_region; `pipeline.city_regions`; `pipeline.gap_cause_snapshots`, job `gap-causes`, `public.admin_gap_causes`.
  - Worker `coverage-sweep-worker-v0.42.0`. `src/GapCauses.jsx` on Platform health › Work queues; `src/EnrichFields.jsx` values.
  - Consumer API unchanged (Decision 266). SOPs 1.66.

## 0.1.251 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.324** (fee reader at full speed; a course first in line from its page). Platform Admin, 23 Oct 2026 09:03 and 09:07: "what maximum system can handle", "push it as priority from course page", "all avaible to change from ui with maximum values displayed".
  - Migration `20261023010000_cf247_fee_reader_speed_and_course_priority.sql`: settings `fees.run_every_minutes`, `fees.concurrency`, `fees.pages_per_run` up to 40; `pipeline.fee_course_requests`; queue priority; Read with AI and a changed official page request the fee first in line; job fee-reader called each minute.
  - Worker `coverage-sweep-worker-v0.41.1` (up to 40 pages a call, concurrency from the job). `src/CourseAudit.jsx` text.
  - Consumer API unchanged (Decision 266). SOPs 1.65.

## 0.1.250 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.323** (course page fees through the AI fee reader; fee proofs for New Zealand). Platform Admin, 23 Oct 2026 07:47: "Page bound by a person, exact title, title and level" admit NZ international fees.
  - Migration `20261023007000_cf247_identity_settings_all_proofs.sql`: `public.admin_pipeline_settings_write` accepts every proof the gate reads; NZ tuition admits pages bound by a person.
  - `src/PipelineSettings.jsx` shows the four extra proofs.
  - Migration `20261023009000_cf247_fee_reader_course_pages.sql` and worker `coverage-sweep-worker-v0.41.0`: the AI fee reader reads course pages (Platform Admin 23 Oct: "Through the AI fee reader"). Settings `fees.course_pages`, `fees.course_pages_per_tick`.
  - Migration `20261023008000_cf247_read_now_releases_holds.sql`: Read with AI releases AI-found-no-value holds and re-sends the fee; `svc_coverage_tuition_handoff_next` re-sends a changed page fee after a closed check.
  - Worker `coverage-sweep-worker-v0.40.9`: the newer-version link is found inside escaped markup and page items (Auckland catalogue).
  - Consumer API unchanged (Decision 266). SOPs 1.64.

## 0.1.249 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.322** (What happened to a course; Read with AI). Platform Admin, 23 Oct 2026 07:12 to 07:24: Auckland diplomas missing location and fees; "audit and logging of exactly what happened and was tried"; "read course pages with ai button".
  - Migration `20261023006000_cf247_course_audit_read_now.sql`: `public.admin_course_audit`, `public.admin_course_read_now`. Migration `20261023005000_cf247_find_again_with_source.sql` (Find again with a source).
  - Worker `coverage-sweep-worker-v0.40.8` (newest year version of a course page; escaped-markup values; fee label decides the audience) and v0.40.7 (up to three course folders).
  - `src/CourseAudit.jsx` in the course drawer (`src/RecordEditor.jsx`), `src/admin-pages.css`.
  - Consumer API unchanged (Decision 266). SOPs 1.63.

## 0.1.248 — 23 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.321** (Course sources). Platform Admin, 22 Oct 2026 23:46: "Platform needs to independently read website ... leave all configurable and manageable from ui"; 23:53: "use the ai or firecrawl to fasten up the process".
  - Migration `20261022044000_cf247_course_source_finder.sql`: `pipeline.source_find_countries`, `pipeline.source_find_paths`, `pipeline.source_find_runs`, `public.svc_source_find_next`, `public.svc_source_find_record`, `public.admin_course_sources`, `read_via` on course and programme lists, job `source-find` (off until its test run is checked), settings `source_find.*` and `batch.source_find`.
  - Migration `20261022043000_cf247_programme_lists.sql` (PR #652): `pipeline.programme_sources`, `pipeline.programme_candidates`, jobs `programme-discover`, `programme-read` and `programme-create`; courses created inactive; the country scope gate waits for a Platform Admin approval; French university credentials for CA; course lists may be site maps with a pattern.
  - Worker `coverage-sweep-worker-v0.40.0` (modes `source_find`, `programme_discover`, `programme_read`; course lists read by Firecrawl map or site map). v0.38.1 (PR #651): AI-matched pages may use the scraper when blocked.
  - `src/CourseSources.jsx` (Layer 2/3 › Course sources), `src/nav-map.js`, `src/mature-main.jsx`, `src/admin-pages.css`.
  - Consumer API unchanged (Decision 266). SOPs 1.62.

## 0.1.247 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.320** (15-minute stats). Platform Admin, 22 Oct 2026 21:57: "Give me stat's and toolset usuage every 15 minutes. Keep the lesson learnt and find gaps quickly"; tasks seen stuck at 2 of 3.
  - Migrations `20261022038000_cf247_stats_15m_and_fill_central.sql` (`pipeline.stats_15m`, `security.stats_15m_v1` job `stats-15m`, `security.stats_15m_fields_v1`, `security.stats_15m_report_v1`, settings `stats.*`), `20261022039000_cf247_fill_respects_central_hold.sql` (Fill in from website respects the central page hold; not-due refusals are not a gap; watchdog central count follows the spend check), `20261022040000_cf247_admin_stats_15m.sql` (`public.admin_stats_15m`, setting `stats.trend_hours`).
  - `src/Stats15m.jsx` on Platform health › Work queues; `src/QueueWatch.jsx`; `src/admin-pages.css`. Hourly scheduled task "StudySearch hourly stats (15-minute snapshots)" (scheduled tasks run at most hourly).
  - Consumer API unchanged (Decision 266). SOPs 1.61.

## 0.1.246 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.319** (progress watchdog). Platform Admin, 22 Oct 2026 19:42: "I wanted the platform to self maintain work job or queue until it completes the data enrichment or notify when it runs out of toolset or get stuck." Choices at 19:53: alerts "Health page + phone/email", build order "Watchdog, rules, workspace, clean-up", self-fix "Safe fixes only, logged".
  - Migration `20261022033000_cf247_queue_watchdog.sql`: `pipeline.queue_watch` (14 enrichment queues with their counts, tools and fixes), `queue_watch_state`, `queue_watch_events`, `queue_watch_alerts` (outbox: notify / report), `queue_watch_fixes`, `queue_watch_retries`; `security.queue_watch_run_v1` (job `queue-watch`, every 15 minutes, catalogued), `security.queue_watch_tool_state_v1`, `security.queue_watch_alerts_take_v1`, `security.queue_watch_report_v1`, `public.admin_queue_watch` (list, report, run); Platform health check `queue_watch`; settings `queue_watch.*` (9).
  - `src/QueueWatch.jsx`, `src/nav-map.js` (Platform health › Work queues), `src/mature-main.jsx`, `src/PlatformHealth.jsx` (Go to link), `src/admin-pages.css`.
  - Delivery of phone and email alerts and the daily report: scheduled tasks reading the outbox and the report.
  - Consumer API unchanged (Decision 266). SOPs 1.60.

## 0.1.245 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.318**. Platform Admin, 22 Oct 2026 19:05: "Yes, we need to accommodate manual actions as well. Do what complete the process in manual mode".
  - `src/nav-map.js` Adapter builder back in the Layer 2/3 tabs; `src/BuildAdapter.jsx` Do it by hand in Adapter builder; `src/AdapterBuilderTab.jsx` Write the settings by hand (3.1), hand-saved settings count for 3.2/3.3, step 4 from one read page, admit by decision in 3.4.
  - Migration `20261022031000_cf247_builder_screenshots_open_build.sql`: screenshots of an open build kept (`security.screenshot_in_open_build_v1`, setting `retention.screenshot_open_build_days`). md5-guarded. Guide; SOPs 1.59.

## 0.1.244 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.317**. Platform Admin, 22 Oct 2026 16:30, choice "Course list page per provider (Recommended)".
  - Migration `20261022026000_cf247_course_list_pages.sql`: `pipeline.provider_course_lists`; `public.admin_course_list` (list, add, stop, read_now); `svc_course_list_next` / `svc_course_list_record` (links into `pipeline.coverage_provider_urls`, source `course_list`); `security.coverage_ai_match_prepare_v1` runs for providers with a read course list and gives one more attempt after each read (md5-guarded); job `course-list-read` (catalogued); six settings.
  - Worker v0.37.0: mode `course_list_read` (direct, then the scraper when too few links; follows next pages).
  - Adapter builder 2.1 Course list page box. Guide; SOPs 1.58.

## 0.1.243 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.316**. Platform Admin, 22 Oct 2026: 16:22 "is ti correct 1410 don't have adapters" (choice "Stop onboarding, label 'No courses'"); 16:10 UTS Adapter builder course list (choice "Yes, build them").
  - Migration `20261022023000_cf247_no_courses_and_course_pages_card.sql`: adapter status `no_courses`; providers page filter and sort; onboarding stops `no_courses` and re-queues when a course is active; builder course list states `wrong_page`, `old_site`, list up to 2,000. md5-guarded.
  - `src/AdapterBuilderTab.jsx` course list (filter chips, tick any row, Search again, Add/Change page on the row, paging), step numbers kept; `src/mature-main.jsx` No courses chip and filter option; `src/ProviderOnboarding.jsx` stop reason. Guide; SOPs 1.57.

## 0.1.242 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.315**. Platform Admin, 22 Oct 2026 15:57 (University of Otago): "how to change the existing non-producing URL in UI and replace them with correct them. can we add manually in UI by ourselves, how will it start admitting data to the courses field?"
  - Migration `20261022022000_cf247_fee_pages_add_stop.sql`: `admin_fee_reader` actions `page_add`, `page_stop`, `page_resume` (Pipeline Operator and above, with a reason, logged); Read again leaves stopped pages out; each page returns fees, admitted, already held and to-review counts. md5-guarded.
  - `src/FeeReader.jsx`: fetch status in words, the AI fee reader's result per page, Stop / Start again, Add a fee page. Guide; SOPs 1.56.

## 0.1.241 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.314**. Platform Admin, 22 Oct 2026 15:21: "AUT fix - how can we make that available in the UI?".
  - `src/FeeReader.jsx`: each row shows its quote, "for N points" when `units_covered` is held, and how the yearly figure was worked out (amount ÷ points × the country's full-time year); rows `replaced` by a newer read hidden behind a count; findings show what a row was read as and what it is. No database change.
  - Guide; SOPs 1.55.

## 0.1.240 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.313**. Platform Admin, 22 Oct 2026 14:35: "proceed with AUT fee fix".
  - Migration `20261022021000_cf247_fee_reader_units_covered.sql`: `security.fee_row_units_v1` (points or credits a fee row covers, from its quote); `svc_fee_ai_record` works the yearly figure out from them (amount / units x full-time load), records a finding when the reader called the row per point, and marks a re-read page's earlier rows `replaced`; the 8 affected fee pages queued again. md5-guarded.
  - Worker v0.36.1: the fee reader prompt and schema carry `units_covered`.
  - Fee reader screen labels the `replaced` outcome. Guide; SOPs 1.54.

## 0.1.239 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.312**. Platform Admin, 22 Oct 2026: 11:42 "unpublished providers should be removed from any schedule tasks or updates. - reenabling them bring back to respective tasks and jobs"; 11:47 Adapter filter, sortable Adapter status, "Create adapters for All ... where website were found" (choice "All 738 with a website"); 11:50 course "not published" bug; 11:57 "Sujata last login was yesterday".
  - Migration `20261022014000_cf247_unpublished_providers_pause.sql`: 15 scheduled queues skip `security.provider_hidden_v1`; AI field reader items of automatic tasks settled as `provider unpublished` and asked again by the gap queue once published. md5-guarded.
  - Migration `20261022015000_cf247_course_detail_provider_published.sql`: course detail returns `provider_publication_status`; the course shows On the website or Hidden.
  - Migration `20261022016000_cf247_adapter_filter_and_backfill.sql`: `security.provider_adapter_status_v1`, `security.admin_providers_page_v2` (adapter filter, column, sort; old function retiring), `admin_catalogue_page` calls it; 726 providers queued for onboarding.
  - Migration `20261022017000_cf247_user_last_active.sql` and `admin-user-management`: Last active on Users & roles.
  - Guide; SOPs 1.53.

## 0.1.238 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.311** (Backup & restore fix). Platform Admin, 22 Oct 2026 11:40: "shown button doesn't work and there is no restore button to restore the select backup".
  - `src/SettingsBackup.jsx`: the backup shown is marked Selected (chip, not a button); every backup row has Compare and Restore; a Restore this backup section (reason, then Restore) is always shown, and says when there is nothing to put back. No database change.
  - Guide; SOPs 1.52.

## 0.1.237 — 22 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.310** (NZ enrichment review fixes; daily backup of publishing and settings). Platform Admin, 22 Oct 2026 07:22: "Review the data enrichment for nz and keep the stat how much of toolset we used used successfully and failed before uni or courses were flagged. Find the gaps and resolution."; choices "Quick wins: 1, 3, 6, 8", "University route change (2)", "Field reader fallbacks (4, 7)", "Daily toolset sheet (9)". 07:41: "Maintain daily unpublished providers as the sql script and report ... backup on daily basis and restore it, only by platform admin".
  - Migration `20261022010000_cf247_nz_review_quick_wins.sql`: `security.site_few_course_pages_v1`, `security.course_search_off_v1`, `security.render_country_v1`; search skips providers whose site map kept `search.min_site_course_pages` (5) or fewer pages in `search.site_check_countries` (["NZ"]); four more providers never searched; `render_ok` and `retry.course_page_render_hours` (24) in `pages.render_countries` (["NZ"]); address guesses only in `relink.url_pattern_countries` (["AU","CA"]); provider flag `course_pages_not_listed` replaces per-course `page_not_found` for those providers. md5-guarded.
  - Migration `20261022011000_cf247_nz_review_route_reader_stats.sql`: `security.site_list_match_done_v1` (`search.site_list_first_types` ["university"]); `retry_cap_v1('ai_match')` counts right pages; `ai_match.min_candidates` (2); Enrich fields hint after a quote miss and no re-ask of an unchanged page copy; `pipeline.toolset_use_daily`, `security.toolset_use_daily_record_v1`, job `toolset-use-daily` (seeded 8–21 Oct).
  - Migration `20261022012000_cf247_settings_backup.sql`: `pipeline.settings_backups`, `security.settings_backup_take_v1`, `security.settings_backup_diff_v1`, `public.admin_settings_backup` (Platform Admin), job `settings-backup-daily`, `retention.settings_backup_days` (60).
  - coverage-sweep worker v0.36.0: `render_ok` pages through Firecrawl; Enrich fields quote-miss retry with a note; fee reader `noNul` and `hasFeeAmount`.
  - Migration `20261022013000_cf247_flag_tool_stats.sql` (Platform Admin 08:12, flags "helpful and intuitive"): `security.flag_tool_summary_v1`; `admin_flags` list and events return the toolset used before each flag; Layer 2/3 › Flags shows it.
  - Settings › Backup & restore; guide; SOPs 1.51.

## 0.1.236 — 21 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.309** (AI fee reader). Platform Admin, 21 Oct 2026 20:02: "Build fee reader for nz unis and make sure its compatible to ca and upcoming countries ... collect and feed error to build and evolve data reader"; choices "Automatic above confidence", "As published + yearly estimate", "NZ universities, then NZ rest, then CA".
  - Migration `20261022001000_cf247_fee_reader.sql`: `pipeline.fee_country_profiles` (NZ, CA, AU), `fee_reader_queue`, `fee_reader_rows`, `fee_reader_findings`, `fee_reader_recipes`; `security.fee_reader_tick_v1` (job `fee-reader`, every 10 minutes): fee pages from the central search, queue per page version, learning from Layer 4 decisions, worker; `svc_fee_ai_next`/`svc_fee_ai_record`: admission above `fees.auto_admit_confidence`, Layer 4 otherwise, findings, notes, further fee pages; `admin_fee_reader`; spend in `ai_spend_today_v1` (`guard_fee_ai`); provider-facts woken when pages wait.
  - coverage-sweep worker v0.35.0: mode `fee_ai` (fees.ts).
  - Layer 2/3 › Enrich fields › Fee reader (AI); guide; SOPs 1.50.
  - Also on 21 Oct (PR #617, #618): never-a-course-page patterns, NZ/CA term dates, NZIST names; CRICOS deployed test suspended until data.gov.au returns.

## 0.1.235 — 21 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.308** (enrichment plans: two tracks, New Zealand first, more credits). Platform Admin, 21 Oct 2026 18:36: "Lets speed up course data for each provider, [Firecrawl] as a separate parallel job?"; choice "Two tracks + more credits".
  - Migration `20261021230000_cf247_plan_two_tracks.sql`: `security.enrich_plan_tick_v1` runs one step per track (Fill missing fields beside the Firecrawl steps); `security.enrich_plan_auto_v1` takes `plans.priority_countries` (["NZ"]) first; Firecrawl `daily_budget_total` 25,000, `daily_share_course_search` 13,000, `daily_share_reads` 5,000, `daily_share_central` 2,500; `plans.auto_per_run` 20, `plans.auto_open_max` 40 (each change logged). Edits md5-guarded.
  - Enrichment plan tab wording; guide; SOPs 1.49.
  - Also on 21 Oct (PR #615): `pipeline.provider_field_daily` and job `provider-field-daily` for the daily NZ field report per provider.

## 0.1.234 — 21 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.307** (enrichment plans: labels, plans that need a person, search refresh gap). Platform Admin, 21 Oct 2026 17:30: "Pick b, and proceed with task 2 and 3".
  - Migration `20261021190000_cf247_plan_needs_person.sql`: tasks a plan starts carry `plan_run`/`plan_mode` and say so in their reason (running ones labelled too); `pipeline.enrich_plan_runs.needs_person` written by `security.enrich_plan_needs_person_v1` when a plan finishes with a stopped, failed, timed out, cancelled or skipped step, or an adapter ready to admit (finished plans filled in); `admin_enrich_plan` overview lists them; `search_refresh_requested_v1` runs the full comparison for Enrich fields and plan requests at most every `search.refresh_min_gap_minutes` (30). Edits md5-guarded.
  - Task manager: Started by shows Enrichment plan (automatic) or (Run now). Layer 2/3 › Enrichment plan: Plans that need a person card; Needs a person on the list and runs. SOPs 1.48.

## 0.1.233 — 21 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.306** (enrichment plans). Platform Admin, 21 Oct 2026 12:03: "end to end data enrichment for universities ... automation is gated by toolset configurable limits but manual should decide on screen of required toolset usage but can do it on demand"; choices "Own on-demand allowance", "All, most missing first", "Universities row + plan tab".
  - Migration `20261021170000_cf247_enrichment_plan.sql`: a plan per university from its gaps (website/contacts/central pages, course pages, adapter, admit, missing fields, scholarships) with estimates from the last 30 days; `pipeline.enrich_plan_runs` run step by step by job `enrich-plan-run` with the existing tasks and onboarding; manual runs charged to the on-demand allowance in `svc_fc_spend` (`coverage_vendor_usage.on_demand_run`; shares leave it out); automatic plans hourly (`enrich-plan-auto`, most missing first, within shares); `public.admin_enrich_plan`. Settings `firecrawl.ondemand_credits_per_day`, `openrouter.ondemand_usd_per_day`, `plans.*`. Edits md5-guarded.
  - Layer 2/3 › Enrichment plan tab and Plan on each university row. SOPs 1.47.

## 0.1.232 — 21 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.305** (delivery modes). Platform Admin, 21 Oct 2026: choice "Keep two, fix reader (Recommended)".
  - Migration `20261021150000_cf247_delivery_modes.sql`: the delivery reader tells a list of options (on campus or online) from a mix inside one course (blended: hours or a share each way, online with block or onsite weeks) and leaves out online offered to domestic students only; `pipeline.delivery_wording` (a university's own phrase, seeded with UNSW "Face-to-face (includes blended)" = on campus) applied first by `security.delivery_mode_read_v1`; Enrich fields and the cross-check use it; open differences that no longer differ close themselves (647 closed). `admin_field_coverage` wording actions. Edits md5-guarded.
  - coverage-sweep worker v0.34.2: the AI prompt gets the same two meanings.
  - Coverage › Attributes: Delivery wording card; cross-check shows modes in words. SOPs 1.46.

## 0.1.231 — 21 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.304** (stalled fields). Platform Admin, 21 Oct 2026 08:42: "go ahead with next step for Field Stalled and action to resolve it. and 10-min check up - should update in the guide/SOP".
  - Migration `20261021130000_cf247_field_stalled.sql`: `pipeline.field_coverage_daily` (each field's filled share per country a day, history back-filled from 29 Sep); `security.field_stalled_v1` (below target and not moving in 7 days, behind the best country by 30 points, or no reader; main cause, action, top five universities missing it); Platform health check `field_stalled` every 3 hours (issue per country, no-reader fields, Fill the gaps not running); `admin_field_coverage` actions `stalled`, `fill_now`, `release_and_fill`. Settings `stall.*`. Edits md5-guarded.
  - Coverage › Attributes opens on Stalled fields (cause, action, Fill now, Release holds and fill); Platform health links field issues there. The 10-minute field check is in the guide and both SOPs (1.45).

## 0.1.230 — 21 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.303** (every field, every country). Platform Admin, 21 Oct 2026 07:30: "Platform needs to keep working and cross checking on missing data fields ... coverage menu should details all data fields filled together not the top 7"; choices "Stored pages + AI, small reads", "When page changes, or 60 days", "All on Coverage; queue for readable ones".
  - Migration `20261021110000_cf247_field_register_gap_queue.sql`: field register (15 course and 9 provider fields, how each is filled, target 80%); the hourly coverage build covers every course field (In the fill queue, No reader yet; duration and campus are register values in Australia only); standing gap queue (job `field-gap-queue`, every 6 hours: one Enrich fields task when due, new page reads capped at 200 a day, a field the page did not state tried again when the page changes or after 60 days); cross-check of held duration, level and delivery against the latest page reading (listed, never overwritten); `public.admin_field_coverage`. Edits md5-guarded.
  - Coverage › Attributes: Every field by country (with targets), Fill the gaps (standing queue) and Cross-check differences above the attribute table, which now lists every course field. SOPs 1.44.

## 0.1.229 — 20 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.302** (D11 second step). Platform Admin, 20 Oct 2026 21:29: "proceed with task 1"; on the reference cross-check, "Drop the 9, keep the 15 (Recommended)".
  - Migration `20261020140000_cf247_d11_readers_off_nine.sql`: nine live functions (retention estimate and tick, wave parent stamp, Task manager running now, platform health check, resource observe, platform health summary, scholarship layer read, dispatcher tuning read) stop reading the 9 tables to be dropped; the old scholarship AI control read answers "retired". Each edit md5-guarded. The 15 tables still in use go back to active in the component register.
  - Layer 4 drawer: the unused "Suggest a new record from a source" panel and `src/ManualPimCandidateWorkspace.jsx` retired (its table is one of the 9).
  - The 9 tables and 31 dead functions are dropped by a paste file after export. SOPs 1.43.

## 0.1.228 — 20 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.301** (menu review). Platform Admin, 20 Oct 2026 19:23: "Ask me nav menu wise and its tab wise questions with its use and recommended choice to keep, move or retire"; answers 19:2x; 19:31 "Go".
  - **Moved:** Scholarships › Extraction → Models & services › AI & OpenRouter; Reference data › Ranking imports → Rankings & statistics › Datasets; Coverage › Flags → Layer 2/3 › Flags; Layer 1 › Scholarships → Layer 2/3 › Scholarships (one tab with Layer 2's); Platform health › Capacity → Go-live checklist; API usage → Settings › API usage (Operator and above, as before); Storage & retention → Platform health › Storage & retention.
  - **Merged:** Key dates and Reference sources are one Reference data list with a type filter; Sources and Layer 1 › Sources are one page (Layer 1 Register) with a layer filter, registers first.
  - **Retired:** Progress › Running now (the board is Scheduled jobs › Task manager) and Levers; Data model. Every old address redirects (`src/nav-map.js`).
  - **Dashboard:** Waiting for you is the Layer 4 Inbox by kind (count, oldest, late; Open goes to the Inbox on that kind); failed jobs, key dates, reference sites and scholarship links stay under Also.
  - Migration `20261020110000_cf247_menu_decisions.sql` (component register: 12 screens retired, 4 added; nothing else). Menu 23 → 19 pages. SOPs 1.42.

## 0.1.227 — 20 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.300** (Layer 2/3 Build & enrich, and fewer screens). Platform Admin, 20 Oct 2026 10:35: "Proceed with task 4, 5 and suggest not used navigation items. Rework layer 2 into layer 2/3 so its cleared it has combined operations. Suggest tabs and nav items that can retire as well. Only actionable and operation relative information and items should be retained." Choices: "Operations first (Recommended)"; retire "Old Layer 4 tabs now", "Priority queue", "Counsellor reports tab", "Scrapers & fetchers page"; NZ flag "NZQA Code signatory (Recommended)".
  - **Screens:** `src/Layer23Operations.jsx` (new, Layer 2/3 › Operations); `src/AdaptersWorkspace.jsx` (`merged`: Layer 2/3 › Universities with onboarding stage, stop help, Retry/Stop, journey, Inbox count); `src/Layer4Inbox.jsx` (`?kind=`, `?provider=`, Decided, counsellor reports, provider departures); `src/ScreenUse.jsx` (Platform health › Screen use); `src/nav-map.js` (Layer 2/3 tabs, hidden builder tab, redirects); `src/ProviderOnboarding.jsx` (list retired; shared parts kept). Removed: `src/PriorityQueue.jsx`, `src/WebsitesToFind.jsx`, `src/CounsellorReports.jsx`, `src/ScholarshipAiReview.jsx`.
  - Migrations `20261020060000_cf247_layer23_operations.sql` (`public.admin_layer23`, `pipeline.automation_catalogue.layer23_stage`, `pipeline.admin_screen_opens`, `public.admin_screen_open`, `public.admin_screen_usage`, Inbox 'decided', counsellor report and provider departure choices, retired screens marked), `20261020070000_cf247_nz_cop_signatory.sql` (NZQA Code signatory → `enrols_international` for NZ; job `nz-cop`), `20261020080000_cf247_d11_idle_tables_retiring.sql` (D11 tables marked retiring with their readers). Worker `coverage-sweep` v0.34.0 (mode `nz_cop`).
  - Tests updated for the retired tabs; SOPs 1.41.

## 0.1.226 — 20 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.299** (Course links: CRICOS code and course-name match). Platform Admin, 20 Oct 2026 09:41: "on right of the Course name display the Cricos code ... the course name is align to course url, there should be no confusion. What we hold is correct."
  - **Screen:** Layer 4 › Inbox (`src/Layer4Inbox.jsx`) and Review queue (`src/m2-3-intelligence-entry.jsx`): CRICOS code beside the course name; each address marked "matches the course name" or "a major or specialisation of the course".
  - Migration `20261020050000_cf247_course_link_major_rule.sql`: `security.course_page_rule_v1` (md5-guarded) keeps the page held when the proposed page is a major or specialisation of it. The 5 waiting Adelaide items closed as Keep with the Platform Admin's decision.
  - Tests: new `tests/uat/cf-247-s80-course-link-code-match-contract.spec.mjs`.
  - SOPs 1.40 (reviewed, no steps changed).

## 0.1.225 — 20 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.298** (Layer 4 Inbox: everything that needs a person). Platform Admin, 20 Oct 2026 07:02: "anything that needs attention or intervention should come to Layer 4, define its return path"; 07:40 choices: by university; all stopped onboarding cases; courses not on the site at the bottom; websites down after 30 days.
  - Migration `20261020040000_cf247_layer4_inbox.sql`: `security.layer4_inbox_items_v1` (13 kinds from the existing sources), `security.layer4_inbox_kinds_v1` (choices and return paths), `public.admin_layer4_inbox` (summary, universities, items, decide; decide routes to the existing actions and is logged); settings `layer4.site_down_days` (30), `layer4.target_days` (7).
  - **Screen:** Layer 4 › Inbox (`src/Layer4Inbox.jsx`, first tab).
  - Tests: new `tests/uat/cf-247-s79-layer4-inbox-contract.spec.mjs`; three Layer 4 tests open the Review queue tab by name.
  - SOPs 1.39 (Operator SOP: start the day in Layer 4 › Inbox).

## 0.1.224 — 20 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.297** (Layer 4: clear choices for course links). Platform Admin, 20 Oct 2026 07:02: "there is no Approve button"; "Reset filter button is misplaced"; "Keep an running sheet for data admission per uni in the admin repo and make it daily schedule".
  - **Fixed:** migration `20261020020000`: the review desk recognises a proposed page stored as `course_url` (all 24 waiting course links), so Approve shows (md5-guarded, one line).
  - **Screen:** Layer 4 › Review queue (`src/m2-3-intelligence-entry.jsx`): course links show Page we hold and New page, with Keep the page we hold, Use the new page and Enter another address; Reset filters at the end of the task chips.
  - Migration `20261020030000`: `security.admission_sheet_v1()` (per-university running sheet, service only) for the daily sheet in the admin repo.
  - Tests: new `tests/uat/cf-247-s78-layer4-link-choices-contract.spec.mjs`.
  - SOPs 1.38 (reviewed, no steps changed).

## 0.1.223 — 20 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.296** (Course pages not found: held until released). Platform Admin, 20 Oct 2026 06:33: "flag the failed one with reason so they dont get tried again, only operator and above can unflag them".
  - Migration `20261020010000_cf247_course_pages_not_found_flag.sql`: flag reason `course_pages_not_found` (hard); `security.enrich_focus_v1` and `security.flag_requeue_v1` (md5-guarded), `admin_flags` and `admin_adapter_build` (one line each, md5-guarded); setting `flag.course_pages_release_min_rank` (4). Raised for the 54 re-find wave 1 providers without usable course pages.
  - **Screen:** Coverage & completeness › Flags (`src/FlagsPanel.jsx`): Release shown for the reasons the user's role may release (`release_codes`).
  - Tests: new `tests/uat/cf-247-s77-course-pages-flag-contract.spec.mjs`.
  - SOPs 1.37 (reviewed, no steps changed).

## 0.1.222 — 19 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.295** (Pages kept once today; scholarship re-check). Platform Admin, 19 Oct 2026 22:47: "finish unis without adapter in waves, following scholarship and data enrichment"; choices "Daily figure on Live activity", "AI re-check, then finish", "20+ and 5–19 re-find; 1–4 CRICOS-only", "Check CRICOS, keep with soft flag".
  - **Screen:** Live activity (`src/Progress.jsx` Running): tile Pages kept once, today, from `public.admin_evidence_reuse_today` (migration `20261019140000`).
  - **Screen:** Layer 4 › AI could not decide (`src/ScholarshipAiReview.jsx`): the AI re-check of each held page with its recommendation and sentences; Refuse starts with the re-check reason. Migration `20261019130000`: `pipeline.scholarship_ai_reviews.recheck`, `svc_scholarship_recheck_next/_record`, job `scholarship-recheck`, setting `batch.scholarship_recheck`; `admin_scholarship_ai('reviews')` returns the re-check (md5-guarded). Worker v0.33.0 mode `scholarship_recheck` (first model of the chain; recommendation only).
  - **Fixed:** small colleges outside the top-50 focus never had their site mapped (map skipped for the allowance counted as tries). Migration `20261019110000`: providers in a `refind-…` Build adapter wave are in focus; `security.refind_wave_discovery_v1(wave)` re-opens their discovery.
  - Migration `20261019120000`: 8 Adelaide University courses not on the new site keep their old page with a soft `not_on_provider_site` flag while CRICOS lists them.
  - Tests: new `tests/uat/cf-247-s76-refind-recheck-contract.spec.mjs`.
  - SOPs 1.36 (reviewed, no steps changed).

## 0.1.221 — 19 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.294** (View saved pages, and which copy is which). Platform Admin, 19 Oct 2026 22:13: "evidence still duplicated"; "tried opening view page and error Preview_not_allowed".
  - **Screen:** Evidence (`src/EvidenceWorkspace.jsx`): each row carries a label from `public.admin_evidence_copy_roles` (migration `20261019100000_cf247_evidence_copy_roles.sql`, helper `api.evidenceCopyRoles`): Course page in use, Older copy · its values are in use, or Older copy, with copy n of m; Provider's facts page (not this course's page); Register or catalogue file; Page screenshot. The panel says "Older copy · its values are in use" instead of "Replaced by a newer copy" when the values in use still come from that copy.
  - **Fixed:** View page was refused (`preview_not_allowed`) for saved web pages, markdown and every gzip-compressed file (about 117,000), and Download gave a .gz. `admin-evidence-access` v1.1 unpacks the file and returns its text; the panel shows HTML in a sandboxed frame (no scripts, forms or same-origin; a content policy blocks scripts and connections) and text as text; Download saves the unpacked .html or .md.
  - Tests: new `tests/uat/cf-247-s75-evidence-view-copies-contract.spec.mjs`.
  - SOPs 1.35 (reviewed, no steps changed).

## 0.1.220 — 19 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.293** (A shorter Evidence panel). Platform Admin, 19 Oct 2026 19:04: "explain why the evidence details panel is so bloated and hard to read ... simplify ... readability".
  - **Screen:** Evidence (`src/EvidenceWorkspace.jsx`): the panel for a saved page is one screen, read from `public.admin_evidence_summary` (migration `20261019070000_cf247_evidence_summary.sql`, new helper `api.evidenceSummary`). It shows the kind of page and read date; the course, code and university (Open course), the page address and how it was read; whether it was accepted as the course's page and how, and In use now or Replaced by a newer copy (with Open the newest copy); What this page supplied (or "No live value comes from this copy"); open review items and earlier or later copies; View page and Download; and Technical details (hash, size, MIME type, storage path, job, worker, evidence id), closed by default. Parts with nothing to show are not drawn.
  - Removed from the panel: the lineage strip, Private evidence boundary, the inline preview and related screenshot card, Acquisition provenance, Source authority, Acquisition job, Extracted observations, Affected canonical entities, Snapshot & change history, Claims, review & decisions, and Storage controls. The panel no longer reads `evidence_detail`, `evidence_entities` or `evidence_observations` (the helpers stay for Jobs). The evidence list, table and filters are unchanged.
  - **Fixed:** course pages showed "0 observations · 0 linked" because the panel read the retired observation model.
  - Tests: new `tests/uat/cf-247-s73-evidence-panel-contract.spec.mjs`; old drawer assertions updated in the CF-142/143, S70, data-quality and A25 specs.
  - SOPs 1.34 (reviewed, no steps changed).

## 0.1.219 — 19 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.292** (Counsellor reports from Zoho). Platform Admin, 19 Oct 2026 14:51: "Can I add some control for counsellor in zohoncreator or crm to flag or comment to pass on to studsearch platform admin for specific record."
  - **Screen:** Coverage & completeness › Counsellor reports (`src/CounsellorReports.jsx`): open, fixed and not changed reports with the record, field, issue, note, suggested value, source link, the value held when reported and the counsellor; close as Fixed or Not changed with a reason (role from setting `reports.resolve_min_rank`).
  - **Zoho API v2 (additive):** `report` takes a course by `course_id` or CRICOS code, an institute (`provider_id` or `cricos_provider_code`), a campus (`campus_id`) or a contact (`contact_id`), with `issue`, `suggested_value` and `source_url`; new action `report_status`. Migration `20261019040000_cf247_zoho_counsellor_reports.sql` (new functions `zoho_v2_report`, `zoho_v2_report_status`, `admin_counsellor_reports`).
  - Consumer API change approved: Platform Admin, 19 Oct 2026 14:51, "Approve all (Recommended)": the zoho-api-v2 edge function's report action extended and report_status added; additive only, no consumer API function altered; `tests/uat/consumer-api-baseline.json` updated.
  - **Fixed:** a Zoho report naming a course only by its CRICOS code was refused as not found.
  - SOPs 1.33 (Operator SOP: a morning step for counsellor reports).

## 0.1.218 — 19 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.291** (One source for the version and release notes). Platform Admin request, Phase 5 "retire the leftovers".
  - Retired the scripts that patched the page after it was drawn; the version and release history now come from one place.
  - **Screen:** `index.html` loads only the React entry. Retired `src/pim-version-entry.js` (an old v2.15.78 version and release list), `src/release-currentness-entry.js`, `src/StatisticsDatasetEnhancer.js`, `src/ranking-dataset-header.js` and `src/evidence-acquisition-provenance-entry.js`. What they still showed is now drawn by React: the version pill and release notes (`src/ReleaseNotes.jsx`), the Rankings & statistics cards from the dataset registry and the ranking dataset heading (`src/mature-main.jsx`), and the Evidence acquisition provenance box (`src/EvidenceWorkspace.jsx`).
  - **Release history:** the notes for v2.15.78 and earlier moved, unchanged, to `src/release-history-legacy.js`, read by `scripts/build-release-history.mjs`; `scripts/verify-release-contract.mjs` now fails if a retired script returns or `index.html` loads anything but the React entry.
  - **Fixed:** the QS and THE cards showed two edition pickers; now one, and its figures follow the chosen edition.
  - No database or worker change. Consumer API unchanged (Decision 266). SOPs 1.32.

## 0.1.217 — 18 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.290** (Asked-for searches first). The Platform Admin chose on 18 Oct 2026 22:25 ("proceed with recommended choice") that searches started from the builder go first.
  - **Database:** migration `20261018140000_cf247_asked_searches_first.sql`: `svc_course_link_search_next` lets a search a person asked for (requested) run for any provider and takes those first; a website change marks the provider's queued searches as asked for; new `admin_course_search_queue(provider)` for the builder guide. Found: since the focus rule of 15 Oct no search outside the 50 focus providers ran, even when asked for.
  - **Screen:** the Adapter builder guide shows course-page searches as running only when they will run, otherwise why.
  - Consumer API unchanged (Decision 266).

## 0.1.216 — 18 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.289** (Adapter builder guide). The Platform Admin said on 18 Oct 2026 22:03: "flow was not clear ... After this no movement or clear indication for next step ... find course pages are running 0-4 without me pressing anything. this has to be intutive right now very confusing with the flow of execution, fix and procced".
  - **Screen:** Layer 2 › Adapter builder: guide at the top (each step's state, the one next thing for a person with Go to step, what runs by itself now), automatic refresh every 15 seconds while work runs, spinners and "nothing to press" on steps that run by themselves (1.2, 1.3, 2.1), contacts and central pages marked optional for the adapter.
  - No database or worker change. Consumer API unchanged (Decision 266).

## 0.1.215 — 18 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.288** (Check or change a website), bug 18/10-01. The Platform Admin asked on 18 Oct 2026 20:35: "add to bug/fix: Website - should have to feature to validate or change the website in the adapter builder."
  - **Screen:** Layer 2 › Adapter builder, step 1.1 Website: Check website (Curator and above) and Change website (Platform Admin, with a reason), with the verdict, the evidence and, after a change, what was saved and restarted. A record holding two addresses is pointed out.
  - **Database:** table `pipeline.provider_website_checks`, `public.admin_provider_website_check` (list, check, change), worker functions `svc_provider_website_check_next` and `svc_provider_website_check_record`, `security.provider_website_change_apply_v1`, job `provider-website-check` (every 5 minutes, only when a check waits), setting `batch.website_check`.
  - **Worker:** coverage-sweep v0.31.0, mode `site_check`.
  - Consumer API unchanged (Decision 266).

## 0.1.214 — 18 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.287** (Build adapter). The Platform Admin asked on 17 Oct 2026 18:56: "click and generate the adapter and configure it for all fields available in the db and seek value for enrichment or foundation fill", on 18 Oct 11:58 "position and plan it on right ui and retire what is not used" (Build adapter added to Layer 2 › Adapters, the Adapter builder kept) and at 14:05 "Proceed with next step".
  - **Screen:** Layer 2 › Build adapter: Universities (stage and readiness of eight fields, build selected into a wave), a university's page (fields measured now, one Admit for Ready fields only), Waves. Backend Decision 267 (migration `20261018070000`). S60.
  - **Retired:** `src/RegulatorySettings.jsx` (nothing imported it); the separate script tag for the Layer 4 mass operations module (Layer 4 › Batches loads it); worker modes directory_capture, fc_extract_qualify, id_qualify, openrouter_key, page_codes, reference_capture and site_hint_verify (none ran in 30 days; worker v0.30.1). SOPs 1.28.

## 0.1.213 — 16 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.286** (Storage sizes). The Platform Admin asked on 16 Oct 2026 23:18: "Prepare and record all db and tables data and sizes also prepare total bucket usage. Keep the stat's simple and recoed on daily basis."
  - **Added:** table `pipeline.storage_size_daily` (one row a day for the database, each schema, each table and each bucket), job `storage-size-daily` (00:25 Melbourne), setting `storage.size_keep_days` (365, table rows only), `admin_storage_sizes` (Pipeline Operator and above) and `admin_storage_sizes_measure` (Platform Admin). Migration `20261016100000`.
  - **Screen:** Settings › Storage & retention starts with Storage sizes: Database, File storage and Tables tiles, then By day, Buckets, Schemas and Tables (filter; largest 25 or All). S52. SOPs 1.27.

## 0.1.212 — 16 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.285** (Task manager). The Platform Admin reported on 16 Oct 2026 22:51: "Task manager doesnt show any job running in the background."
  - **Found:** since v2.15.266 (13 Oct) the background board (scheduled jobs running, failing, paused, credits) was only on Coverage & completeness › Progress › Running now; Task manager listed only tasks people start (none were running) while about 280 scheduled runs and 70 worker calls ran every 15 minutes. That broke the standing rule of 11 Oct 2026 ("All background jobs using resources at any given time should be visible under task manager").
  - **Fixed:** Task manager shows Background jobs (the same component and read as Progress › Running now) under Tasks started by people. S51. SOPs 1.26.

## 0.1.211 — 16 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.284** (health, scholarships, dashboard icons, delete users). The Platform Admin reported on 16 Oct 2026 15:25: "Platform health: CRITICAL, with 5 critical issues and 1 warning. Most are stale or mis-labelled. The real one is scholarships: none published or read for two days." "Dashboard should display Icons" "Platform Users - can't be deleted, only disabled".
  - **Found:** no scholarship page read since 14 Oct; the only pages due belong to The University of Sydney (83) and RMIT (27), held by the per-university Firecrawl cap (150 credits in 30 days, used at onboarding on 12 Oct), 86 of them re-reads asked for on 12 Oct; the reader was then paused by the flag unit for running empty. Discovery has been through every eligible provider (the 106 waiting are small Australian providers, skipped by design).
  - **Fixed:** a requested read is not held by the per-university cap (`svc_scholarship_read_next`); the reader switched on again. Health checks: claimable work only, held work shown apart; tuition hand-off retired; trial-run restarts not overdue; scholarship allowance from its setting (60,000); live connection limit (120); compute profile Medium; size levels 4/6/7 GB. Migration 20261016070000.
  - **Users:** Delete (Platform Admin; database guard refuses Platform Admins, self and the system account; soft delete when recorded work names the user; roles end; `security.user_deletions`). `admin-user-management` now deployed from the repository. Migration 20261016080000. Dashboard queue icons. S51. SOPs 1.25.

## 0.1.210 — 16 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.283** (API usage console). The Platform Admin asked on 16 Oct 2026 14:31: "Create me a ui to check stats on Both APIs with relevant metrics/API calls or statistics, success & failure, last login, full sync, delta sync, bandwidth, load size etc. be able to rotate their keys. and on Demand fresh statistics by pressing a button, otherwise get refresh daily basis."
  - **Statistics** per key for 24 hours, 7 days and 30 days (`pipeline.api_usage_summary`, `security.api_key_stats_v1`), per API on top; full loads and deltas from the sync calls, now logged as `sync_full_start`, `sync_full`, `sync_full_end` and `sync_delta` by `zoho-api-v2` and `website-api-v2`.
  - **Refresh** daily (job `api-usage-rollup`, was every 15 minutes) and on demand (`admin_api_usage_refresh`); each refresh recorded (`pipeline.api_usage_refreshes`).
  - **Keys** (Platform Admin): rotate with an overlap (setting `api.key_rotate_overlap_hours`, 24), end the old key, switch off and on (`pipeline.api_key_events`); a call with an old key during the overlap is logged as `<key>#previous`. Also in this release: the API usage screen itself and the Website API v2 notes (Pilot PRs #541, #544). Migration 20261016060000; S50. SOPs 1.24.

## 0.1.209 — 15 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.282** (the flag unit). The Platform Admin asked on 15 Oct 2026: "we don't keep burning the toolset on repetitive waste and produce nothing ... have flag unit that can be removed or raised manually and automatically by tried burn ... the said entry or provider get re-entered in queue".
  - **Found:** in 6 hours about 4,000 worker calls, 3 jobs produced anything; the central-page finder picked the same four universities every 5 minutes (716 refusals that day); every Canadian and New Zealand gap had already been tried and skipped by Enrich fields.
  - **Flags** (`pipeline.enrichment_flags` extended, history in `pipeline.enrichment_flag_events`): providers, course fields and jobs; hard reasons hold at once, soft after 2 tries (a second try only on new input); released when input changes, a free website check passes (coverage-sweep v0.26.0 mode flag_check; 3, 7, 14, 30 days) or the date comes; released items re-queued. Person raise and release with a reason. Coverage & completeness › Flags.
  - **Waste:** worker jobs whose last 30 runs found nothing are paused and tried again after 1, 2, 4, then 6 hours; central pages held until due; Enrich fields does not queue held or unchanged items. Job flag-recheck every 10 minutes. Migration 20261015080000; S45. SOPs 1.23.

## 0.1.208 — 15 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.281** (bug fix and feature). The Platform Admin reported on 15 Oct 2026: "Bug/fix: i'm unable to upload Uni Logos or request to find it".
  - **Cause:** the provider panel's logo was made clickable by a page watcher that only noticed new tables and panels; when the provider's details arrived after the panel opened (a direct link, a slow load) the logo never became clickable, so no upload reached the server. The old logo finder had been retired on 10 Oct; 49 of 3,091 providers had a logo.
  - **Logo editing:** the logo is clickable in the provider panel, the providers list and the Logos list for roles allowed by the setting Pipeline settings › Logos (Platform Admin). The editor uploads a file, downloads an image address, or asks the logo finder. Errors show the server's reason. The page watcher is retired.
  - **Logo finder** (job logo-find, every 10 minutes; coverage-sweep v0.25.0 mode logo_find): providers with a website and no logo, asked-for first then by courses; the logo from the home page (header logo, declared logo, SVG icon, touch icon); type read from the bytes, size and SVG content checked; stored and attached only when the provider still has no logo; not found flagged (`logo_not_found`) and tried again after the set days. Migration 20261015050000; S44.

## 0.1.207 — 15 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.280** (Decision 260, housekeeping). The Platform Admin asked on 15 Oct 2026: "always keep the snapshot/documentation what corresponds to what and decommission as we create new approach. outcome is code/platform and database are always streamlined and secure." Choice: "Live table + generated doc".
  - **Component register** (`pipeline.component_register`): every job, table, view, edge function and screen with its layer, purpose, status (active, retiring, retired), replaces and replaced by, last used and size.
  - **Weekly hygiene check** (job hygiene-check): usage counters; unused tables, indexes and edge functions; uncatalogued jobs; tables without row-level security; definer functions without a pinned search path; public functions open to anonymous callers; components ready to drop. Notice "Housekeeping".
  - **Component register workflow** (daily): edge function calls from the logs, edge functions and screens from this repository; generated document on the `component-register-snapshot` branch.
  - **Build rule (S42):** migrations from 20261015030000 say what they replace and retire, state each new table's purpose and catalogue each new job. Repository rules (CLAUDE.md) updated. SOPs 1.21.

## 0.1.206 — 15 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.279** (central pages and fee checks). Platform Admin decisions on 15 Oct 2026 (multiple choice): "Central pages, per course group"; fees "Qualify first, then decide", then "Clear the >=90% ones"; "Auto-approve checked AI proposals", "Double degrees take the shared default", "Research degrees need a research default", "Keep the other holds".
  - **Fees:** Wollongong, Tasmania, TAFE NSW and Notre Dame adapters admit fee (fee only); before admission each fee is compared with the CRICOS registered course total and held back and flagged when more than `admit.fee_crosscheck_pct` (25%) off. Victoria University, Academies Australasia and Torrens are flagged for an adapter fix.
  - **Central pages:** the top 50 providers' English policies and calendars are read with the pinned AI model (206 pages); a reading is approved automatically when every value is quoted on the page and course pages do not mostly disagree (`central.max_disagree_pct`, `central.min_compare`); otherwise it is flagged for a person. Job policy-auto-approve.
  - **English plan:** double degrees whose awards are all at the course's level take that level's default (513 top-50 courses to fill); research degrees take a research default only where the policy states one (worker v0.24.0 asks for it). Other Decision 227 holds stay.
  - Migration 20261015020000 (three functions md5-guarded). Worker coverage-sweep v0.24.0. SOPs 1.20.

## 0.1.205 — 15 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.278** (waste rules for data enrichment). The Platform Admin asked on 15 Oct 2026 at 09:18: "If we are wasting resources on multiple tries then tighten rules around it, recording, flagging and moving on, rather getting stuck an wasting resources." Decisions (multiple choice): "Auto-pause idle jobs", "Yield-based retry cap", "No repeat reads unchanged", "Run admit jobs on new input"; approach "Top 50 by adapter, flag the tail".
  - **Idle jobs:** the waste-guard job (hourly) pauses a watched job with no output and nothing waiting (course-link-reverse, about 6.5 hours of database time a day for 2 courses ever), and switches it on again when work arrives.
  - **Admit jobs on new input:** coverage-admit, coverage-admit-intakes and adapter-overwrite run only when pages, adapters, checked values, exclusions, locks, decisions, courses or providers changed, with a full check every `waste.admit_full_check_hours` (6).
  - **Retry cap by yield:** AI course-page matching makes a further attempt only while that attempt still finds a page in at least `waste.retry_min_yield_pct` (15%) of recent cases (now 2 attempts; attempt 3 found 9%).
  - **Flip-flops:** exit awards no longer overwrite a value the course's own page gives (106 courses were rewritten about 33 times each in 4 days); a value changed automatically more than `waste.flipflop_max_changes` in the window is frozen through the adapter exclusions and flagged; the same review item is not raised again while an identical one was superseded (9 courses were raised 144 times a day).
  - **Stored pages:** a scholarship page stored within `waste.page_reuse_hours` (24) is used instead of being read again.
  - **Focus providers:** course-page search, site mapping and AI matching run only for the top `enrich.focus_top_n` (50) Australian providers by missing English and intakes; others keep their register data and are flagged.
  - **Records:** `pipeline.enrichment_flags` (what was stopped and why); notices for paused jobs and frozen values; Firecrawl panel and target refresh no longer run at the same time (95 deadlocks a day). Migration 20261015010000 (eight functions md5-guarded). SOPs 1.19.

## 0.1.204 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.277**. The Platform Admin asked on 14 Oct 2026 at 20:43: "For ranking, we can pass it on v2 api and for logos we can pass it on as file links to be stored in wix platform with maximun validity. And subsequent api requests only pass changed data unless queried for full load." Decisions (multiple choice): approved to display; logo links 1 year, renewed in the delta; a new sync action with a cursor.
  - **Display terms:** rankings and logos are returned with `terms_status: approved`, read from two Yes/No settings on Settings › Pipeline settings › Website API (no longer a fixed value in five functions).
  - **Logo links:** valid for `website.logo_link_days` (365) instead of 24 hours written into the edge function.
  - **Sync action (website API v2, additive):** no cursor or `full_load` returns everything in pages; `next_cursor` passed back returns only what changed since, with removals. Entities: reference, provider, logo, rankings, scholarship, course (course items are the search items). Job `website-sync-check` (catalogued, Search and API) builds and compares items every minute; a logo is resent before its link ends.
  - Pipeline settings show Yes/No settings. Migration 20261014110000 (five website functions md5-guarded). SOPs 1.18.

## 0.1.203 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.276** (Decision 258). The Platform Admin chose on 14 Oct 2026 to map institution type for the website (multiple choice): types mirror the registers; Australian universities from the TEQSA National Register on data.gov.au; a CRICOS Government provider that offers VET is TAFE; New Zealand from NZQA; Canada left empty; training.gov.au later.
  - **Types:** University, University College, Higher Education Institute, TAFE / Polytechnic, Private VET college, School, Wānanga, Other. The unused tafe and college rows are retired, not dropped.
  - **Register facts and rules.** `catalogue.provider_register_facts` keeps each register value with its source and evidence. `pipeline.provider_type_rules` are ordered and editable; the first enabled match sets the type. A type set by hand is kept. No match, no type: the reason is kept and shown.
  - **Layer 1 reader `layer1-provider-facts` v1.0.0** reads the TEQSA National Register providers file and CRICOS Institutions through the data.gov.au CKAN API, keeps the file as evidence and runs the rules. `layer1-operations-control` v1.9.0 and `layer1-operations-scheduled` v1.5.0 verify and run the two sources. The NZQA register applier now keeps the organisation type.
  - **Screens.** Providers › Type column (Needs type with its reason; PIM Admin sets it by hand or back to Auto, no reason asked). Settings › Pipeline settings › Institution type rules (Platform Admin).
  - **Website API v2:** `institution_type` on providers and courses, the `institution_types` filter on search and providers, and the type list in reference. Additive.
  - Daily job `provider-type-classify` (catalogued). Migrations 20261014060746 and 20261014063911 (the facts writer matches every code in one statement; the first live apply had passed the 8 second limit); test `cf-247-institution-type-contract`; SOPs 1.17.
  - Reader v1.2.0 adds the NZQA provider search by organisation type (format `nzqa_type_listing`), so New Zealand providers are typed without waiting for the next NZQA register change. The search links providers by an internal number, so each row is matched by the NZQA number first and otherwise by its listed name, only when exactly one provider of the register has that name (migration 20261014065115). Migration 20261014064736 adds the NZQA source and resumes the three sources (verified weekly, applied when the file changes).
  - Reader v1.3.0: the NZQA search number is the organisation number followed by a five-digit site number (415 of 415 checked), so every NZQA row now matches by number (migration 20261014070622). The name match (migrations 20261014070026 and 20261014070327, the first of which passed the time limit) stays as a fallback for a number that matches nothing; a name is used only when every listed row with it has the same type.

## 0.1.202 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.275**. The Platform Admin asked on 14 Oct 2026 at 12:04: "make sure all config and limits can be controlled through UI. go for NZ and CA enrichment. record any lesson learnt and start with top tier 50 uni batch. maintain stats and telemetry. raise and use the scraper and AI accordingly."
  - **Every limit on screen.** The worker's last fixed Enrich fields values (page text the AI reads, titles per AI call) are settings (worker v0.23.0 reads them). The Coverage and telemetry card lists every limit in force and where it is changed.
  - **Stats and telemetry.** Hourly job `enrich-coverage-snapshot` (catalogued) records, per country and field, how many active courses have the field. Layer 2 › Enrich fields › Coverage and telemetry shows shares, movement since the first snapshot and in 24 hours, and the job's last 24 hours (settled, filled, AI calls and failures, AI spend, scraper credits).
  - **Raised (logged with reasons):** Enrich fields AI daily guard US$2 → US$25; AI calls at once 2 → 6. Firecrawl shares left as they are (today: 0 of 1,000 "other", 76 of 3,000 "reads").
  - **Batch 1 started:** the top 50 New Zealand and Canadian universities (17 world-ranked, then the largest by courses), 8,901 courses, 44,539 items, AI and scraper on.
  - Migration 20261014013800; test S37; SOPs 1.16.

## 0.1.201 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.274**: fixes from the Enrich fields live trial (University of Waikato).
  - Worker v0.22.1: stored contact pages are plain, not gzip; the AI step now reads either (the address and campus list reads had failed).
  - Worker v0.22.2: "open to international" needs a quote about the course's students or fees; a site-wide footer line ("International Enquiries") no longer counts. The 39 trial values that rested on the footer were undone.

## 0.1.200 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.273**. The Platform Admin asked on 14 Oct 2026 at 10:41 for "a job to enrich data for specific or multiple fields across uni or countries using scraper and ai in layer 2 and layer 3. Keep it simple" (plan `FIELD-GAPS-AND-ENRICHMENT-PLAN.md` v1.0; decisions: build the full job first, campus lists admitted when sources agree, international by the institution rule).
  - **Layer 2 › Enrich fields.** Choose countries or universities and fields; preview what is missing, what has a stored page and what the adapters already read; start a task with a reason (Pipeline Operator and above). Tasks show progress, results by field and every value with the words it was read from.
  - **The task (`enrich_fields`).** It fills only missing values, never a value entered or locked by hand. Sources, in the order set per country under Field sources: adapter values already read, the institution rule, the AI reading the stored page (it must quote it) or classifying the title, and one new read through the scraper only when the task allows it.
  - **Campuses.** The AI turns a university's campus names into one list; a campus is admitted when at least `enrich.campus_min_pages` course pages name it; courses are then linked. International: Canada by the IRCC list; otherwise what the page says.
  - **Worker v0.22.0** (mode `enrich_ai`, the pinned central-pages model). AI spend shows on Toolsets as "Enrich fields with AI" with its own daily guard. Migrations 20261014013500–3700; new settings in Pipeline settings. SOPs 1.15.

## 0.1.199 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.272** (Platform Admin, 14 Oct 2026 10:14: "Proceed", after the settings control audit correction v1.2).
  - The "automatic publication" flag (`pipeline.publication_control_settings`, off since 5 Sep 2026) switched nothing on: the Layer 4 publish preview only printed it in its confirmation. The preview stops reading it and the confirmation no longer prints it (migration 20261014013400). Publication is still decided by each record's Published switch and the Layer 4 decision.
  - Paste file `PASTE-20261014-retire-unused-settings-tables-v2.sql` retires that table, `pipeline.scholarship_runtime_settings` and its uncalled write function, after copying their rows into `pipeline.admin_control_events`. It replaces the withdrawn 13 Oct paste file.

## 0.1.198 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.271**. The Platform Admin asked on 14 Oct 2026 at 08:33 for Canadian course codes ("fill the real program code and if missing generate the studysearch code ... meaningful with uni/campus/Degree based, applicable to upcoming countries") and "skip scholarship search for any provider whose website is a directory site ... visible flag in provider ... which we can toggle to enable".
  - **StudySearch codes.** `ref.course_code_schemes` says which identifier types are printed codes (CRICOS, NZQA, Quebec and Ontario program codes, college program codes) and which are source IDs (portal GUIDs, page IDs). 6,313 Canadian courses without a printed code now show a StudySearch code such as `UBC-MA-014` (university, level, number), marked SS; the list and course record show it and search finds it. `course_code` keeps the source's own value. The hourly job `studysearch-codes` codes new courses (setting `batch.studysearch_codes`). A code never changes; a printed code always wins.
  - **Scholarship search flag.** Off automatically for 85 providers whose only website is a directory site; shown on Providers and in the provider panel, where a Pipeline Operator turns it on with the provider's own website and a reason (a fresh search starts) or off. 105 providers whose own website is known were pointed back to it.
  - **Retry loop stopped.** 1,391 queued AI reads of directory pages were closed (`skip_reason`). The AI reader now closes such reads, and a read refused for credits counts toward its 3 tries.
  - Migrations 20261014013200 and 20261014013300. SOPs 1.14.

## 0.1.197 — 14 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.270**. The Platform Admin reported on 14 Oct 2026 at 07:13: "Bug/fix: Courses > state filter is not showing options for nz and Canada. Cross check all filters across all pages and report all relevant drop down options are visible."
  - **Regions.** A course's region is its campus region; when no campus region is recorded (every NZ and Canadian course today), it is the university's region. Courses › Region (NZ, 15) and Province / territory (Canada, 10) now list options, and the course list filters, shows and counts regions the same way (migration 20261014013000).
  - **Delivery.** Delivery options and the course list read the course's own mode first (On campus, Online, Blended, On campus and online); before, every course showed on campus.
  - **Empty filters say why.** University group (Australia only) and Field (not yet classified for NZ and Canada) explain an empty list.
  - **Every catalogue country.** Data Quality (Canada computed when opened), Enrichment operations, Provider assets, Key dates, Regulatory sources, the Layer 4 fee currency (CAD), the contacts provider picker (follows the country) and Websites to find (keeps the full country list) cover Canada. Scholarship amounts no longer assume A$. Priority queue says "State or region".
  - Fix migration 20261014013100 (Provider assets read the country list once). SOPs 1.13.

## 0.1.196 — 13 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.269**. The Platform Admin asked on 13 Oct 2026 at 21:43: "Bring all controls to UI and make sure in future it's not getting hard coded. All controls need to be reflected and control in UI. Use current recommended settings and choices." This follows the settings control audit v1.0.
  - **Settings register.** There is one settings register: toolset `pipeline`, in the same table, write path and log as Toolsets & limits. It holds 60 settings, each with a range, a unit and what uses it: 33 job sizes, 19 re-read and retry times, and 8 onboarding rules.
  - **Jobs.** All 31 scheduled jobs that had a number written into them now read their size from the register (migration 20261013012900). The Automations batch box and the Pipeline settings rows now change the setting instead of rewriting the job.
  - **Timing rules.** Fourteen functions read their re-read and retry times and their onboarding rules from the register. Each default is today's value, so nothing changed on the day; scholarship pages keep 90 days, as recommended.
  - **Worker.** Worker v0.21.7 reads the Firecrawl proxy (now used by every Firecrawl read), the site map sizes and the search result counts from Toolsets › Firecrawl (10 new settings, including the search-stop window).
  - **Policy tables.** Capacity, evidence storage, retention and provider fee rule policies can be changed on Pipeline settings, with a reason.
  - **Removed.** The leftover Layer 3 items are gone from Pipeline settings.
  - **Guards.** `security.controls_check_v1()` lists any running job with a number written into it; it shows on Pipeline settings and raises a Toolsets notice. Test S32 fails any later migration that writes a number into a job or a business rule into a function, unless the line is marked `-- fixed:` as technical. `CLAUDE.md` records the rule.
  - SOPs 1.12.

## 0.1.195 — 13 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.268** (Platform Admin, 13 Oct 2026 14:56, with a screenshot of Layer 2 › Onboarding: "these notification are asking for cant be fixed and if followed the link its doesnt open the specific card to adjust the values if required"; chose all four). Every notice now says plainly whether a person needs to act (Action needed, Action outside StudySearch, Optional) or not (Nothing to do), with the one thing to do. Its Go to button opens the exact card or setting and scrolls to it (Daily budget settings, Credits by university, Websites to find, the scholarship credits, the course-page search budget, Daily guards, Jobs). Held and stopped course searches list their universities with Search again, and providers with no official website have a website box, inside the notice. Information-only notices (a daily share used up, providers sharing a website, a one-off job failure, an AI guard passed) stay on Toolsets and limits; the layer page links to them. Course-page search stopped now counts only universities stopped after searching (27), not the 2 held for an adapter check, which have their own notice. Migration 20261013012800 (platform_notices_v1, read only). SOPs 1.11.

## 0.1.194 — 13 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.267** (Platform Admin, 13 Oct 2026 14:23, with screenshots: "progress mock-up and actual implementation for Journey is very different. Even Running now is all tasks are empty"). Progress › Journeys rebuilt as the approved mock-up: filter panel (group, country, stage, held up by, Only held up, find, count sorted by courses), the adapter journey as seven stage pills (the onboarding stepper had no styles outside its own page and showed as a numbered list), fields filled, scholarship journey, held up by and a Next step button; a selected university shows its steps (stage, time, note) and its run-on-demand actions (Find scholarships now, scholarship pages with AI again, read course pages again, Qualify adapter, Retry, Search again, links). Running now: schedules in words, last result as what happened and when, and every job's row opens to universities (more jobs report the universities they touched; otherwise the universities now at the job's stage). Migration `20261013012700` (`admin_progress_read`: journeys sort and filters, new `journey` view, wider `running_unis` with a stage fallback). SOPs 1.10.

## 0.1.193 — 13 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.266** (Platform Admin, 13 Oct 2026: "Show the adapter and scholarship journey and progress I can follow on the UI ... what is running, and where we can tweak or run on demand ... make sure redundant UI screens and controls are retired"; mock-up approved; "proceed with Progress tab, as v2.15.266"). **Coverage & completeness › Progress** (`Progress.jsx`) in four views: Overview (all, pilot or top 50: needs attention, the seven journey stages, fields when picked → now, scholarships, course pages in the last hour, Firecrawl and AI today, the hourly trend), Journeys (a row per university with what holds it up and the next step; a row opens its journey with Retry, Search again and Find scholarships now), Running now (jobs by journey stage, each opening to the universities it works on with a link to their journey; Pause, Resume, Run now; worker errors with Mark as seen) and Levers (every pace setting with what it did today, linking to where it is changed; run on demand). Migration `20261013012500`: `pipeline.progress_provider_facts`, `pipeline.progress_snapshots` (hourly, kept 90 days, job progress-snapshot at :09, catalogued), `admin_progress_read(view, args)`; onboarding-pilot-snapshot paused. Retired: the Live activity page (old addresses open Progress › Running now), the Pilot panel on Layer 2 › Onboarding, the Dashboard health strip, Layers and Recent activity, and Task manager's Running now. Guide and SOPs 1.9.

## 0.1.192 — 13 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.265** (Platform Admin, 13 Oct 2026: credit waste by university; "Block directory sites", "Universities only", "Refusals per university", "Reset cap for top-50", overseas "Keep going"; course search "Australia and 30+ courses first", "Flag Victoria Uni and Adelaide Uni", "Never search directory sites", "CRICOS code before title"; "use training.gov.au or ASQA, CRICOS/RTO code, flag the exceptions"; "Credit fixes first"). Over 30 days 63% of scholarship credits and 59% of course-search credits produced nothing. Migration `20261013012200`: `svc_fc_spend` refuses any Firecrawl spend on a directory site and counts refusals per university (`pipeline.firecrawl_refusals_by_provider`); search order top-50, Australian 30+ CRICOS courses, overseas, small (`fc_provider_tier_v1`); scholarship discovery for Australian providers with 30+ courses (setting `scholarship_min_courses`) and overseas universities, cap counted from joining onboarding (`fc_sch_cap_since_v1`), held universities not picked; 183 directory recipes and 190 scholarship rows switched off; course search held for Victoria University and Adelaide University (`pipeline.firecrawl_search_holds`); notices for held searches, providers with no official website and shared websites. Migration `20261013012300`: 124 Australian providers with no website searched again. Migration `20261013012400`: Credits by university lists today's refusals by university. Worker coverage-sweep v0.21.6: websites found on training.gov.au and the TEQSA National Register first (accepted with the CRICOS code on the home page, a name-fitting address, or the one website the register lists), then the CRICOS-code search. SOPs 1.8.

## 0.1.191 — 13 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.264** (Platform Admin, 13 Oct 2026 00:09: "Layer 3 has removed the configuration of OpenAI and access to toolsets and limits; restore them as a tab in Models & services"). Models & services in three tabs: Services, **AI & OpenRouter** (`AiConfig.jsx`: OpenRouter balance, mode, credit floor and key with set and verify; each AI use with its model, daily guard, spend and calls today; central pages model and switch; adapter proposal model; scholarship AI models with order, Qualify and Make active, shared with Scholarships › Extraction; model profiles with prompt version and hash; recent AI changes) and **Toolsets & limits**. Migration `20261013012100` (`admin_ai_config_read`, `admin_ai_config`). Guide and SOPs 1.7.

## 0.1.190 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.263** (Platform Admin, 12 Oct 2026 23:54: "Yes, use Firecrawl for pages found by CRICOS code or listed by the uni"). Worker coverage-sweep v0.21.5: a course page is read through Firecrawl only when found by its CRICOS code (cricos_search, cricos_code, cricos_code_on_page), listed on the university's own site (title_match, cms_path_public) or entered by a person (manual); pages found by a title or web search are read directly only. Evidence: Firecrawl read the right page for 1,436 of 1,440 CRICOS-code finds and 1,286 of 1,475 listed pages, against 989 of 2,053 title-search and 469 of 1,941 Firecrawl-search finds. No database change. SOPs 1.6.

## 0.1.189 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.262** (Platform Admin, 12 Oct 2026 21:47: "Report Firecrawl credit used per uni and pages produced, that will give us how much waste is happening, and tweak it along"; 22:22: "Give me the top 50 unis with maximum courses in Australia and try our mechanism over them"). Firecrawl daily budget of 15,000 credits (Melbourne day), shared by purpose (finding course pages 6,000, reading 3,000, scholarships 3,500, central pages 1,500, other 1,000), every worker spend checked and recorded by `svc_fc_spend`; per-university caps (scholarships 150 credits in 30 days, central pages again after 30 days, course-page search stopped after 30 searches without a correct page, resumed with Search again); Firecrawl credits by university on Models & services › Firecrawl (credits by purpose, correct and wrong pages, credits per correct page, waste flags); notices at 80%. Worker coverage-sweep v0.21.4. Cohort `au-top-2026-10-12`: the 50 Australian providers with the most CRICOS courses onboarded first, largest first; small pilot members not yet started held. Migrations `20261012011900`, `20261012012000`. SOPs 1.5.

## 0.1.188 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.261** (Platform Admin, 12 Oct 2026 21:21: "Read found pages directly first, and use Firecrawl only when the direct read is blocked or needs a browser. Also switch Firecrawl to its basic proxy, and turn the second reader off"). In the hour after v2.15.260 Firecrawl billed about 23,500 credits (about 7 a page; 76% of found pages were the wrong page). Worker coverage-sweep v0.21.3 reads a found course page directly first and through Firecrawl only when the direct read is blocked or the page needs a browser; every Firecrawl scrape uses the basic proxy. Migration 20261012011800 sets the Firecrawl read proxy to basic and pauses the second reader (coverage-read-2; resumable on Scheduled jobs › Automations). Guides and SOPs v1.4. Nothing dropped.

## 0.1.187 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.260** (Platform Admin, 12 Oct 2026 20:00: "Increase the limit to read course pages if found. Keep moving to the next wave if a course page is not found. I hope the same mechanism is used which has been successful using Firecrawl in finding course pages, and not burned by direct HTTP"). Found: course pages are found by Firecrawl search, but a page the search found was read by a direct request only; in 24 hours about 1,700 such reads were blocked, failed or needed a browser and were never tried through Firecrawl. (1) Worker coverage-sweep v0.21.2 reads search-found course pages through Firecrawl (rendered), a direct read only when Firecrawl cannot be used. (2) 1,237 found pages that were blocked, failed or needed a browser at Firecrawl target universities are read again. (3) Reading: up to 20 pages a university per call (was 8) and a second reader every 30 seconds (catalogued coverage-read-2). (4) Keep moving: a university whose search is finished and has had no page read for an hour stops as Too few course pages (the next starts) and carries on by itself once enough pages are read; a used-up adapter AI allowance stops as "AI allowance used" and carries on when it renews; a missing website is "No website", not an unexpected error. Guides and SOPs v1.3. Migration 20261012011700; nothing dropped.

## 0.1.186 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.259** (Platform Admin, 12 Oct 2026 17:43: "With the new mechanism, will the universities now be admitted automatically, enriched and launch the scholarship adapter? Automate step 4 and onwards, or at least pick 100 universities across AU, NZ and CA to prove the mechanism, with hourly updates and a summary table of data completeness"; answers "Auto-admit everything that passes" and "60 AU / 25 NZ / 15 CA, 48 hours"). (1) **Admit automatically**: a setting on Layer 2 › Onboarding (Platform Admin, with a reason; switched on as decided). A university at Ready to admit has exactly the fields that passed the admit rule admitted by itself within 10 minutes (logged), then goes on to Enrich courses, Scholarship adapter and Admit scholarships. Fields that did not pass are never admitted; Needs a person still needs a person; undo for one university on Layer 2 › Adapters. (2) **Pilot**: 100 universities (60 AU, 25 NZ, 15 CA, furthest along first, queued ones moved to the front), each with its completeness recorded when picked. (3) **Hourly snapshots** (catalogued job onboarding-pilot-snapshot) and a Pilot panel: by country, stages reached, needs a person or stopped, admitted automatically, share of courses with intakes, English, fee and delivery when picked → now, scholarships published when picked → now, AI cost; Refresh now and Show pilot only. Guides and SOPs v1.2. Migration 20261012011600; nothing dropped.

## 0.1.185 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.258** (Platform Admin bug 12/10-01, 12 Oct 2026: "Model and Services are missing Layer 3 Limits functionality. Provider onboarding should be in Layer 2/3 as a tab, mass automatic adapter creation is not there — if I press Onboard all without an adapter, what will happen? Prepare the journey milestones"). Agreed: the journey in seven stages, scholarships after courses are enriched, AI limits observed with notices only, 100 universities at once. (1) **AI limits**: Models & services › OpenRouter no longer reads the retired Layer 3 tables. The balance is read from OpenRouter every 15 minutes (new catalogued job openrouter-balance, worker coverage-sweep v0.21.1 mode openrouter_balance); the panel shows the balance, the credit floor (new, US$5), and for each AI use (scholarship AI, adapter builder, central pages AI, course matching) its calls and spend today against a daily guard (new settings under Daily guards), plus spend by day. Notices come from the AI uses that run now (refused calls, low balance or floor, balance not read, a use past its guard) on Layer 2; the stale "579 work items out of credit" and "balance not read" notices are gone. In Observe nothing stops; switched to stop at limits, the scholarship AI and central pages AI stop below the floor or past their guard (security.ai_use_allowed_v1). (2) **Onboarding moved to Layer 2 › Onboarding** (old addresses redirect). (3) **Seven journey stages**: Provider in → Prepare → Create adapter → Admit → Enrich courses → Scholarship adapter → Admit scholarships → Done, as a strip of counts that filters the list and a stepper on each row; the journey panel shows the stage, what was enriched and the scholarship result. Qualifying now ends at Admit; once admitted (or its central pages approved) the adapter is applied, its courses are enriched, and only then is the scholarship search started; Done when no page waits for the AI or a person (or after 7 days). (4) **The button** "Onboard all without an adapter (n)" counted universities already in onboarding (all 1,153 were queued, so it added none). It is now "Onboard universities not yet queued (n)", greyed out at 0, with the pace (stages finished in the last hour and 6 hours) and an estimate for the queue. Up to 100 universities at once (was 30); waiting stages do not count towards that and are checked every 10 minutes. Guides and both SOPs (v1.1) updated. Migrations 20261012011400 and 20261012011500; nothing dropped.

## 0.1.184 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.257** (Platform Admin, 12 Oct 2026 15:36: "SOPs for Platform Admin and operators to manage the platform, as separate guides of their daily tasks, how the platform automates, what to pay attention to and where a person intervenes; kept up to date with the UI and the data admission mechanism; under Guides in the UI and as versioned docs"). The Help menu is now Guides, with three tabs: Platform guide, Platform Admin SOP and Operator SOP (Curator and above). Each SOP has its purpose and what the role owns, the seven-stage automation table (what runs by itself, its scheduled jobs, where a person decides), the rules that never change, the daily routine (start of day, morning, afternoon, each step with who, why, done when and a button to its screen), weekly checks, where a person intervenes, what to watch, escalation and version history, and downloads as Markdown. The same words are the versioned documents docs/sops/admin-sop.md and operator-sop.md (also in the admin repository); the SOPs are reviewed with every release.

## 0.1.183 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.256** (Platform Admin status review, 12 Oct 2026 13:06; fixes 1 to 5 agreed). (1) The Firecrawl targets refresh runs one at a time (two at once deadlocked 14 times in 6 hours). (2) "AI could not decide" held 1,012 pages, mostly because of proof rules rather than model strength: a value the first model proved now stands when the confirming model's value is not proven, and an audience quote naming another country or region ("students from Papua New Guinea") or "not a domestic student" proves international (worker v0.20.3); GPT-4.1 was added and qualified as a third reader, and a Platform Admin adds it to the order on Scholarships › Extraction (qualifying switches nothing on); the waiting pages were read again, and "Read the waiting pages again" is on Layer 4 › AI could not decide. (3) When nothing passes on a university's course pages, a pinned model (GPT-4.1 mini) reads its stored English language policy and academic calendar pages, quoting every score and month; the result is a proposal a person approves (Adapter builder 1.3 or Approvals waiting), shown as "Approve central pages" on Providers › Onboarding; fee schedules stay with the rule parser. (4) Onboarding waits for course pages the search found but has not read yet, up to 6 hours. (5) A paste file removes 12 catalogue rows of retired jobs. Migrations 20261012011100, 20261012011200 and 20261012011300 (nothing dropped); scheduled job central-ai (catalogued).

## 0.1.182 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.255** (Platform Admin, 12 Oct 2026 11:15: "Will this create the adapter automatically, start the scholarships as well, and can I monitor the journey from the UI?"). Checked live: 35 of 38 universities at Ready to admit had nothing to admit, 27 because onboarding applied an old adapter again without asking the AI, and New scholarships showed 0 while their pages were still with the AI. Now, when no field passes, the AI proposes the settings again, told which fields did not pass and why (an old adapter gets up to two AI attempts, 6 then 10 sample pages; a new one a second attempt with 10); each proposal is saved in testing, applied and qualified, and nothing is admitted. Nothing ready after that shows as Needs a person (its own tile and filter), not Ready to admit. Each row opens its journey: steps with times and notes, tasks, AI drafts (sample pages, model, cost), the qualification of each field and the scholarships found with their state; New scholarships counts live (found, published, pages with the AI). The 35 were sent back to qualifying (no second scholarship search). Also found live: the course-page search had nearly stopped (5 searches in 6 hours, 3,764 waiting) because searches for universities that are not Firecrawl targets were picked first and refused every minute; the picker now takes only target universities while target-only is on, and the 8 universities stopped with 0 course pages read were sent back. Providers › Onboarding loaded in about 9 seconds because read course pages had no index by provider; an index is added. Migrations 20261012010700, 20261012010800 and 20261012010900 (nothing dropped).

## 0.1.181 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.254** (12 Oct 2026): two follow-ups to automatic onboarding. A course-page search that had been switched off because it was built from another university's domain (Humber College: guelphhumber.ca) stopped onboarding with a misleading "no website" error; when the switched-off search is for a different domain from the website now recorded, it is replaced by the generic search for the recorded website, and a search switched off for the same website stops onboarding with the plain reason "Course-page search switched off" for a person to decide. Humber College was put back to carry on. An AI adapter proposal with no answer after 30 minutes (the worker was shut down; University of Calgary and University of Manitoba) is now asked again, twice at most, before onboarding stops, and those two carry on. Dashboard "Waiting for you" no longer lists the retired Flagged values and Fee rules, adds Universities ready to admit and Onboarding stopped for a person (both open Providers › Onboarding), and Scholarships ready to publish opens Scholarships › Coverage. Migrations 20261012010500 and 20261012010600 (nothing dropped).

## 0.1.180 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.253** (Platform Admin, 12 Oct 2026 09:35): universities without an admitting adapter are now onboarded automatically. A database job takes each one through its website, course pages, 6 sample pages, the AI's proposed adapter, save in testing and apply, qualify, central pages and a scholarship search, and stops at Ready to admit: admitting stays a person's step on Layer 2 › Adapters, and a passing check never admits by itself. All 1,153 universities without one were queued, largest first, 30 at once; new universities start by themselves. Providers › Onboarding shows the tiles, each university's step and a plain note, why any stopped and what to do, with Retry selected, Stop selected, Onboard all without an adapter and the onboarding settings (Platform Admin, each with a reason). Fee schedules, English policies and academic calendars are now approved in the Adapter builder (1.3) for one university, or across universities under Providers › Onboarding › Approvals waiting. Layer 4 tabs Flagged values, Fee rules, Attributes, Scholarship publishing and Blocks are retired (the 33 open flagged fees were closed and the fees kept; fee rule results are kept); their old addresses open the Review queue, Providers › Onboarding or Scholarships › Coverage. A slim credit and limit banner on every page (Curator and above) warns when Firecrawl credits, OpenRouter credit, the adapter AI allowance or the scholarship scraper cap run low, with a link to Models & services. Platform guide reviewed. Migrations 20261012010200 and 20261012010300.

## 0.1.179 — 12 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.252** (Platform Admin, 12 Oct 2026 08:15): "Stop Layer 3 from working on intakes, English and fees and clean up UI and scripts", as asked when university adapters merged Layers 2 and 3. Layer 3 AI validation is retired everywhere: its 10 scheduled jobs are paused (migration 20261012010100; deletion by a paste file), the Layer 3 menu (Control, Work queue), Layer 4 › Send back to AI, the "Send back to AI check" review decision, the Dashboard Layer 3 tile and the Layer 3 settings are removed, and old Layer 3 addresses open Layer 2 › Adapters. The Layer 3 edge functions (model routing, work dispatch, work interpret and three benchmarks) and their shared helpers are removed from the repo; layer3-provider-control stays (it keeps the OpenRouter key the scholarship AI uses). 442 pending Layer 4 items for intakes, English and fees were closed (the university needs an adapter for that field). In the 24 hours before, 93% of Layer 3 intake and English work was for universities whose adapter already admits the field.

## 0.1.178 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.251** (11 Oct 2026, 23:50). In its first 30 minutes with AI admission on, Qwen3 30B admitted 6 scholarships on audience quotes that were on the page but did not say who the scholarship is for ("open to both full-time and part-time students"; a permanent humanitarian visa read as international); AI admission was paused and the 6 held (2 withdrawn). Worker v0.20.2: the audience quote must itself name international (or domestic) students. Migration 20261011010500: refusal reasons were not recorded while AI admission was on (text array append). Migration 20261011010600: pages read while paused are queued again. Migration 20261011010700 and Scholarships › Extraction: "Second model confirms admissions" (on by default) has the next model confirm each admission by the first.

## 0.1.177 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.250** (Platform Admin bugs 11/10-6 follow-up, S16): "Qwen 3 then GPT-4.1 mini then to Layer 4; Layer 4 review the current parked items, reroute to adapters or the new scholarship mechanism". Scholarships › Extraction sets the order models read in (each qualified with the current instructions); the next model reads a page again, on the same stored copy, only when the previous reply failed, the name was not on the page or a stated fact was not proven by its quote; a page no model settles goes to the new Layer 4 › AI could not decide (every answer, quotes, stored copy; Admit the chosen answer or Refuse with a reason), and the decision is kept as an exception for the same page copy. Re-read parked scholarships with AI queues active unpublished and held scholarships; a hold a person made stays, an automatic hold is released when the re-read passes every check. Layer 4 course items for intakes, English and fees at universities whose adapter admits that field are closed as superseded and the course page is read again (and new ones on arrival); course addresses stay with a person. Migration 20261011010400 (nothing dropped).

## 0.1.176 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.249** (Platform Admin bugs 11/10-6, S15). Scholarship pages are still read by code through the scraper and kept, but the facts are now read by a pinned AI model instead of fixed text rules, which had refused 20,021 of 21,286 pages (VU STEM Accommodation refused as not offered, a $1,300 deposit taken as the value, named courses missed). New Scholarships › Extraction: AI admission switch (off until a person switches it on), models with qualification scores on a 41-page sample (Qwen3 30B and GPT-4.1 mini, each pinned with require_parameters), the sample with labels a person can correct, the instructions with versions, Try a page, and recent answers with each quote and the stored copy. Every fact must quote the page and the worker checks the quote (coverage-sweep worker v0.20.1, mode scholarship_ai); a fact not proven counts as not stated. Qualifying never activates a model; Make active and Switch AI admission on are separate steps with a reason. While AI admission is on, new and re-read pages are decided by the AI answer and pass the same hourly publish checks; the rule audience reader no longer overrides AI-read scholarships; the watch list is re-checked on request and the rest nightly (scholarship-ai-backfill). Two task types (scholarship_ai_qualify, scholarship_ai_backfill) and two catalogued jobs (scholarship-ai-extract, scholarship-ai-backfill) show in Task manager. A listing link now needs a name match (Fix 5). Migration 20261011010300 (nothing dropped; an earlier unused scholarship AI scaffold is left as it is).

## 0.1.175 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.248** (Platform Admin bugs 11/10-5, S14). The 4-university Find scholarships now run (Bond, ACU, CDU, EIT) finished with no new scholarship and no way to see why. Feature 2: every site map, listing page, new page and known scholarship page a task finds or reads is recorded with the task (pipeline.admin_job_items). Feature 1: the task and each university's Coverage panel show the journey per university (found, read, decided with plain-English reasons, records, published or what blocks it, next automatic publish time, time left while running), with links to each page's stored copy and each scholarship. Fix 1: Jobs rows name the task and its universities. Fix 2: every candidate page read keeps a stored copy registered as evidence (worker v0.19.2). Fix 3: pages that are never scholarships are skipped by address rules (9 rules; none matches a page held or admitted; 120 earlier refusals would have been skipped). Fix 4: a page that lists scholarships is suggested as the listing page. Fix 5: a scholarship published automatically that now fails a check is held at the next hourly publish. Migration 20261011010200.

## 0.1.174 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.247** (Platform Admin bugs 11/10-4, S13). Fix 1: Find scholarships now on Scholarships › Coverage never started: it asked for a reason and returned silently when the reason was short; starting any task now asks only to confirm and the log records the screen it came from (Admit the passing fields, pause and cancel still need a reason). Fix 2: every outcome is shown next to the button (started, already running, or the error), and providers in a running Find scholarships task show Finding… until it finishes. Fix 3: Coverage shows each provider's CRICOS code, so Victoria University (00124K and 02475D) can be told apart. Migration 20261011010100.

## 0.1.173 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.246** (Platform Admin bugs 11/10-3, S12). Fix 1: NZQA showed 21 job rows per register run (1,712 rows); Jobs now shows one Register run row per run with what it found, and opening it shows why it ran, its counts, every batch and links to the stored source files. Fix 2: NZQA was rerun about 5 times a day because its listing changes on every read while nothing changed; a source whose last two runs changed nothing waits for its due date. Fix 3: the Task manager showed nothing (its read took up to 34 s and the error was hidden behind Loading); it now reads in 0.4 s, never hides an error, and shows everything using resources now and in the last 15 minutes (scheduled jobs with Pause, Resume and Run now, worker and API calls, AI and scraper spend, queues) and flags any job not in the catalogue. Fix 4: Automations read 34 s to 0.46 s. Fix 5: the Study Australia, DFAT and Manaaki scholarship registers retired and stopped. Fix 6: an unhealthy Layer 1 source says why. Fix 7 and Feature 2: Reference sources and Layer 1 › Sources are one list pattern with expandable rows, pills and in-place editing; Layer 1 › Sources has + Add source (public.admin_layer1_add_source); Runs, Source settings and Manual batch runs are retired into it. Feature 1: batch sizes editable for 32 automations. Migrations 20261011009800, 20261011009900 and 20261011010000. A name-only change on Reference sources no longer asks for a reason.

## 0.1.172 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.245** (Platform Admin bugs 11/10-2, S11). Fix 7: Zoho, website and search course queries took about 60 s and every coverage-admit run was rolled back since 10 Oct 14:10 UTC; the blocked-course check is built once per query (60.9 s to 0.5 s, same results) in 16 consumer functions (`20261011009300`). Fix 1: the Layer 2 › Adapters list styles are renamed adp- (ad blockers hid styles named ad-list, ad-row, ad-note). Fix 3: websites found and verified by search go on the provider record (41 at release, e.g. Britts College); never over one entered by hand. Features 2 to 4: every provider without a website is searched (all countries; Firecrawl targets no longer required; 189 skipped as budget searched again; new providers queued as added), and a website starts its course page search, contact read and central page search; central pages (key dates, international fees, English requirements) are suggested from a Firecrawl map of the site with targeted maps for what is missing (`pipeline.provider_central_search`, job central-find); task types Fill in a provider from its website and Find course pages with Firecrawl (`20261011009400`, `9500`, `9600`, `9700`). An address carrying another distinctive name is refused (Humber College was matched to guelphhumber.ca; corrected). Adapter builder: numbered 1.1 to 3.4 and 4 (Fix 6), readable text (Fix 2), capture status on its own (Fix 5), every course with its page state and Find with Firecrawl (Feature 1); a proposal cut off at its length limit is asked again once with a larger limit and every attempt's tokens and cost are recorded (Fix 4). Provider record: Fill in from website. Worker coverage-sweep v0.19.0.

## 0.1.171 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.244** (on-demand scholarship tasks and Task manager running now, S10; Platform Admin 11 Oct 2026). Find scholarships now (provider record; Scholarships › Coverage, one provider or up to 50 ticked), Check scholarships for this course (course record; lists scholarships added or removed) and Read again now (scholarship record) each start a task: its pages go first in the scraper queue, the worker gets the next step each minute (map, screen, read), courses attach by the evidence rules, and progress and Cancel show on the button and in Task manager. Task manager › Running now: tasks, scheduled jobs running this minute (pause, resume, run now), worker calls on their way (shown only) and scraper credits in the last hour. Standing rule: every background feature is registered as a task type (pipeline.admin_job_kinds) or a scheduled job and appears in Task manager with its controls. Database: Platform Admin paste removed the fixed task-kind list; `20261011009000` (task kind registry, scholarship task prepare and fire, running now; six functions md5-guarded) and `20261011009100` (an empty Read again now or course check is refused with its reason; the credits note names the provider) and `20261011009200` (every scheduled job has a plain label in Task manager), applied by the Database apply migration workflow. Mechanism document v1.0: admin repo docs/scholarships/SCHOLARSHIP-MECHANISM.md.

## 0.1.170 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.243** (scholarship evidence journey, S9; Platform Admin 11 Oct 2026). Scholarships are read through the scraper only: no direct read, no fallback, robots.txt not consulted for scholarship pages; a page waits when the scraper cannot be used. Reader v0.7.1: applications open and close (with rounds), study start, courses the page names and excludes, and the sentence behind each fact. Course links come from the evidence with a proof per link (named courses, English courses, levels and fields; none when the page names none); a scholarship without a course link can be published. Scholarship record: open, close and study start rows, link proofs and an Evidence & extraction journey. Study Australia and national registers retired (comparison, source, records without a provider page set inactive, register runs and the feed worker retired); Layer 3 › Scholarships (AI runs), scope rules, Layer 1 scholarship sources and five legacy jobs removed. Database: `20261011008400`, `8500`, `8600`, `8700`, `8800` (long course titles matched by containment); worker coverage-sweep v0.18.2; also `8300` (Scholarships list timeout fix).

## 0.1.169 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.242** (scholarships read through the scraper, S7; Platform Admin request 11 Oct 2026). Scholarship pages and provider listing pages are read through Firecrawl first (rendered page), for every provider, within the scholarship credit cap; a direct read is the fallback. New Layer 2 setting "Read scholarship pages through the scraper" (on/off switch on Scholarships › Coverage › Settings and jobs). Database: `20261011008200` (setting; svc_scholarship_fc_budget passes it to the worker; credit cap 6,000 to 12,000; every active scholarship page and listing page queued to be read again), applied by the Database apply migration workflow. Worker coverage-sweep v0.17.42 (records at most two at a time; a slow record is retried once and no longer fails the run). On/off scholarship settings show as switches.

## 0.1.168 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.241** (rename to StudySearch, S6; customer request 11 Oct 2026). App text, mark, titles and guide renamed. Database: `20261011007700` (82 functions: the word CourseFinder in messages and labels becomes StudySearch; md5-guarded), applied by the Database apply migration workflow. Repositories, web address, Wix/Zoho contract names, saved screen settings and reader user agents unchanged until production.

## 0.1.167 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.240** (scholarship coverage check, S3; bulk restore, S5). Database: `20261011007300` (listing pages, coverage checks, watch list of 27, coverage read/provider/write RPCs, scholarship-listing job and settings, bulk restore), applied by the Database apply migration workflow. Worker coverage-sweep v0.17.37 (mode scholarship_listing). Scholarships › Coverage screen; Providers › Archived bulk restore; scholarship settings and jobs without reason prompts.

## 0.1.166 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.239** (scholarship completeness, S1, S2 and S4; Platform Admin decisions of 11 Oct 2026). Database: `20261011007100` (scholarship APIs published only) and `20261011007200` (course links when the page names no restriction or an unmatched faculty; editions held; hourly auto-publish; values read again), applied by the new Database apply migration workflow. Worker coverage-sweep v0.17.36 (scholarship reader v0.6.3: academic-result percentages ignored; whole-sentence value text).

## 0.1.165 — 11 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.238** (Platform Admin bug list of 10 Oct 2026, R5: Features 5, 6 and 7; decision "New 'archived' status"). Database: `20261010007000` (md5-guarded): pipeline.provider_archives; archive and restore clean-up workflow with a checklist (status archived, unpublished, adapter and course link search off, waiting reviews superseded; restored exactly); Layer 1 departures archive and restore providers automatically; admin_archive_read; course archive by hand rebuilds search; non-active courses blocked from consumer APIs. Providers › Archived screen; lists show active records by default.

## 0.1.164 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.237** (Platform Admin bug list of 10 Oct 2026, R4 part 2: Feature 4, pause work). Database: `20261010006900` (md5-guarded): 20 automatic pickers skip providers in security.provider_hidden_v1 (unpublished or not active); hand-started admin work is not blocked; wrong public contact emails cleared and re-read. Worker coverage-sweep v0.17.35: contact emails must be on the provider's own domain (registrable name) and library, vet hospital, ethics, philanthropy, partnership, facilities and research mailboxes are skipped.

## 0.1.163 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.236** (Platform Admin bug list of 10 Oct 2026, R4 part 1: Feature 4, Published switch). Database: `20261010006800` (md5-guarded): security.provider_hidden_v1 joins the Layer 4 search-block views; every active provider published and new providers published by default; admin_provider_publish; course index build, Wix/website providers, single course, scholarships, rankings and Zoho scholarships gated. Provider list: Published switch, unpublished rows greyed.

## 0.1.162 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.235** (contact quality after the first R3 runs). Worker coverage-sweep v0.17.34: contact_page skips media/security/feedback and similar mailboxes and prefers the main contact page; cricos_peo reads the CRICOS institution page by provider code (no search). Database: `20261010006700` (md5-guarded): earlier automated values are replaced on re-read; checks re-queued; schedules back on.

## 0.1.161 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.234** (Platform Admin bug list of 10 Oct 2026, R3: Fix 2; decisions "Both, kept separate", "Fill automatically", CRICOS contacts "All at once"). Database: `20261010006600` (md5-guarded; additive): pipeline.provider_contact_points and provider_contact_checks; worker functions; provider read returns the contact source and, for PIM Operators and above, the internal regulatory contact; schedules provider-contact-page and cricos-peo. Worker coverage-sweep v0.17.33: modes contact_page and cricos_peo.

## 0.1.160 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.233** (Platform Admin bug list of 10 Oct 2026, R2: Fix 1, Feature 1, Feature 3; Hotcourses kept for logos only). Database: `20261010006500` (md5-guarded; no drops or deletes): twelve course directories join the third-party list; security.third_party_host_v1 and provider_site_verdict_v1; third-party sites refused as website, course finder or course page; directory site hints retired; third-party course finders cleared, their pages refused and facts read from them withdrawn; own sites found by the search copied to Website. Worker coverage-sweep v0.17.32: an AU site needs the CRICOS code on its home page, or on a deeper page of an address that fits the name.

## 0.1.159 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.232** (Platform Admin bug list of 10 Oct 2026, R1: Fix 3, Fix 4, Fix 5, Feature 2). Database: `20261010006400` (md5-guarded changes to admin_provider_edit, svc_coverage_site_record, admin_firecrawl_write and admin_adapter_builder). A course finder address entered by hand is locked and kept; the adapter builder asks for the provider's own website when none is recorded, starts page finding for one provider, takes a course page entered by hand (own site only) as a sample, and no longer asks for reasons.

## 0.1.158 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.231** (Platform Admin: load course insights on More; simple logo list). Database: `20261010006300` (md5-guarded admin_read change, applied through the connector: course_detail no longer returns related insights, ranking context, taxonomy or state summaries; new course_insights operation; about 85 KB to 21.5 KB). Providers › Logos & assets is a simple has-logo / no-logo list.

## 0.1.157 — 10 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.230** (UI stage 3: Rankings, Reference data, Settings, Models and services, Go-live checklist, remaining admin pages). Settings rows, Go-live and Capacity headers and the environment panels use the standard text sizes. The look-and-feel rollout across the app is complete.

## 0.1.156 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.229** (UI stage 2: Layer 1 register, Layer 2, Coverage, Sources, Platform health). Boxed filter selects keep their box under the standard control style (fixes the Sources/Jobs overflow from v2.15.227); Sources and Jobs headers slimmed; plain wording on Layer 1 manual batch runs and alerts; adapter names and tick labels sized consistently.

## 0.1.155 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.228** (Platform Admin: check usage, retire unused; remove the Reset database button and function). Clean-up batch 7: database `20261009006200` (6 functions of the old scale-qualification chain, md5-guarded, no CASCADE; 8 run-token rows) and 8 edge functions retired (coursefacts-au-qut/rmit/uq, layer2-scale-qualify-scheduled, layer2-screenshot-backfill-scheduled, layer3-source-pattern-benchmark, layer1-au-completeness, pilot-reset). The Go-live checklist no longer offers Reset database.

## 0.1.154 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.227** (Platform Admin: same look on every page, in stages; stage 1 — Dashboard, Layer 3, Layer 4 review, Scheduled jobs, Evidence). Every table resizes like the catalogue lists (shared helper, widths kept per page in the browser); dropdowns and inputs share one style; Evidence and Jobs lose their repeated headers; Layer 4 More button and dashboard tiles aligned.

## 0.1.153 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.226** (Platform Admin: slim the provider read). Database: `20261009006000` (md5-guarded admin_read change: provider_detail no longer returns the course, evidence, source and history lists or the scholarship, ranking and logo context; new provider_insights operation for related insights; about 385 KB to 4.4 KB for RMIT). The provider panel loads related insights only when More is opened.

## 0.1.152 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.225** (Platform Admin: lists fill the page width with resizable columns; course and provider panels as coloured pills and fact cards, with unnecessary evidence, regulatory and operational text removed; same look for other record panels). Bug fix: a long nationality list no longer pushes scholarship columns off screen.

## 0.1.151 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.224** (Platform Admin: modern, readable UI with coloured pills; clean up the old system's UI). Scholarships list: status pills for type, who it is for, linked courses and closing date (open, closing within 30 days, closed), using the shared StatusChip tones; names and values wrap to two lines. Clean-up batch 3 (screens): the old onboarding cases panel removed from Providers › Onboarding (no case was ever opened; RPCs onboarding_cases_* now have no screen), two orphaned stylesheets removed (layer2-operations.css, enrichment-operations.css), Live activity wording updated. Kept after a live check: Search pass (used by adapters), Sample runs (service test tool), Refresh schedules (Layer 1).
- Phase 3 shadow run, round 3 (Platform Admin: try one escalation step). Database: `20261008005700` (md5-guarded: the adapter's own model reads first; only when it finds nothing and the page clearly shows the field is MiMo v2.6 Pro asked, once; each read records whether it escalated; nothing admitted). Worker layer3-model-routing shadow v1.2.0. Round 2 result (e60): no field met the retire rule.
- Clean-up of the old system, batch 4 (database; Platform Admin: prepare it now). Database: `20261008005600` (15 functions of the old Layer 2 schedulers, wave and scope services, the Layer 3 enqueue, the scholarship settings wrapper and the onboarding-case RPCs dropped behind md5 guards, no CASCADE; the Layer 2 branch removed from the pilot edge-execution trigger; run-token rows for retired functions removed; no table, data or history dropped). Four dormant edge functions retired (layer2-extract-v2, layer2-course-fact-extract-v2, layer2-scholarship-extract, layer2-scholarship-catalogue-enumerate). Kept for a later decision: the provider-asset functions (page fan-out, asset promote, hotcourses directory parse), layer2-acquire-v2, layer2-scope-discover-scheduled, and 11 old functions still reached from admin_read or the scheduler workflow bridges.
- Phase 3 closes (Platform Admin: keep Layer 3, stop shadow). The shadow run is switched off (admin_adapter_shadow, logged). Database: `20261008005800` (the three shadow jobs removed; refused while the run is on; tables, functions and reads kept as the record). Layer 3 keeps intakes, English and tuition.
- Clean-up of the old system, batch 5 (database; Platform Admin: proceed with next step). Database: `20261008005900` (md5-guarded, 32 guards checked read-only first; no CASCADE): 31 functions dropped — the one-off run builder's scheduler-workflow chain, the Layer 2 operator, scope-batch, background and wave dispatch chain, and the old scholarship scope and runtime chain with pipeline.svc_pilot_invoke_layer2; dead admin_read operations removed (scholarship_runtime, scholarship_runtime_uat, layer2_profiles, layer2_profile_detail, layer2_provider_routes). No table, data or history dropped. Kept: scheduler_workflow_profile_binding_snapshot_v1, _queueable_url_allowed_v1 and _https_host_v1 (still used by Layer 2 discovery and provider attempts).

## 0.1.150 — 9 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.223** (Scholarships list: one sortable column per fact, fitted to the screen; release of the clean-up batch 2 screen removals and the Adapter builder link on Providers › Onboarding).

## 0.1.149 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.222** (Layer 1 schedule choice per source; ranking edition years from two years ahead back to 2010).
- Database: `20261008002700` (`admin_layer1_schedule`, Platform Admin only, logged; no source's schedule changed).
- Database: `20261008002800` (NZQA register adapter `nz_nzqa`, switched off; replay runs may list several stored files; `svc_register_replay_next_v3`; three NZQA replay runs) and `20261008002900` (replay driver started again). Worker coverage-sweep v0.17.21 (register_replay reads registers published as web pages, three stored batch files a call; reference is the layer1-nz-live v1.2.1 code).
- Database: `20261008003000` (PRISMS SA4 and QILT GOS, SES, GOS-L and ESS register adapters, switched off; six replay runs on the stored workbooks). Worker coverage-sweep v0.17.22 (register_replay reads statistics workbooks; references are prisms-au-etl v0.2.0 and qilt-au-etl v0.3.0).
- Layer 1 fix: qilt-au-etl v0.3.1 stores the confidence interval upper bound (v0.3.0 read `cell.h`, always empty). Database: `20261008003100` (refills the upper bound of 3,103 existing QILT rows from the published cell kept with each row; refused unless values and lower bounds read back unchanged). Worker coverage-sweep v0.17.23 (QILT reference follows v0.3.1).
- Database: `20261008003200` (QILT workbooks replayed again after the fix) and `20261008003300` (`admin_register_adapter_switch`, Platform Admin only, logged, switches on only after a passing replay with the spec unchanged since; `svc_register_adapter_reader`). Register engines moved to `supabase/functions/_shared/cf247-register-*.ts`. layer1-nz-live v1.3.0 and prisms-au-etl v0.3.0 read with their register adapter when it is switched on.
- Database: `20261008003400` (NZQA and PRISMS replayed again before switch-on), `20261008003500` (a replay run is leased to one call; `svc_register_replay_release`), `20261008003600` (PRISMS pre-switch replay re-run). Worker coverage-sweep v0.17.24 (releases the lease when a call ends).
- CRICOS register adapter version 2 (`20261008003700`, applied after the worker deploy): provider postal address and the campus and course location sets; engine adds `adapterSelect`, `adapterSets` and `adapterFingerprints`. layer1-au-depth v1.8.0 and layer1-au-cricos-facts v1.3.0 read with the adapter when it is switched on (local checks: fingerprints and every batch structure identical to the Layer 1 scans; plan fingerprints cost the same CPU as Layer 1). Worker coverage-sweep v0.17.25 (CRICOS replays compare the address fields and both location sets).
- Database: `20261008003800` (CRICOS v2 replays started), `20261008003900` (17 Canadian register adapters, format text_items, switched off: 16 Ontario college catalogues and IRCC DLI; replay runs on every stored August copy) and `20261008004000` (replay driver started). Engine `_shared/cf247-register-items.ts`; references `_shared/cf247-register-ca-ref.ts` (verbatim copies of the Layer 1 readers, checked by a contract test). Worker coverage-sweep v0.17.26.
- Worker coverage-sweep v0.17.27: a key repeated within one replay call is saved as key#2, key#3 (the CRICOS v2 location sets repeat some locations); `20261008004000` also replays the three CRICOS archives again.
- Canadian Layer 1 readers that kept only parsed output now also store the raw pages they fetch as a `-raw.json` evidence bundle beside their evidence (centennial, cna, fanshawe, firstparty-catalogues, mb, northern, ns-sk, on-college, sault, sk, stlawrence), so their parsing can be replayed after their next run. Nothing they parse or apply changes.
- Worker coverage-sweep v0.17.28: text_items fields are read in dependency order (a spec stored as jsonb loses key order; the Conestoga replay read 0 records).
- Database: `20261008004100` (four Canadian replays run again after the field-order fix) and `20261008004200` (ALIS and EducationPlannerBC register adapters, switched off; replays on the newest stored bundle per school and institution). Worker coverage-sweep v0.17.29 (text_items reads bundles of stored pages, lists, lookups and nested objects).
- Worker coverage-sweep v0.17.30: the CRICOS adapter joins and reads only the records of each replay slice (version 2 ran out of worker resources). Database: `20261008004300` (a replay run stops with an error after three calls end without saving at the same position; a leased run no longer holds up the others).
- Worker coverage-sweep v0.17.31: CRICOS v2 replays read each location set in a call of its own after the records. Database: `20261008004400` (the 11 Aug archive replay resumes).
- Scholarships central register (Platform Admin decisions: central register, country tagged; record for government, index for provider; AU then NZ then CA, monthly). Database: `20261008004500` (`scholarship.registers` AU, NZ, CA; `scholarship.register_listings`; Study Australia and DFAT Australia Awards registered as Layer 1 sources, source_system SCHOLARSHIP_REGISTER, no schedule switched on; the old hourly feeds for the same sources switched off; listings matched to held scholarships and unmatched provider pages handed to the provider page reader; `admin_scholarship_registers`). Workers: scholarships-au-etl v0.2.0 (whole Study Australia listing read, raw pages kept, stable count and hash; detail reads in batches for the provider page link and CRICOS), layer1-operations-control v1.7.0 and layer1-operations-scheduled v1.3.0 (verify and run the scholarship registers).
- Fix: `20261008004600` (provider page candidates accept the source `register`; the first Study Australia detail batch had failed on the old three-value check and rolled back).
- Fix: `20261008004700` (a provider page that several listings point at is handed to the page reader once; the second detail batch had failed and rolled back).
- Scholarships New Zealand register (Platform Admin: take recommended decisions). Database: `20261008004800` (Manaaki New Zealand Scholarships as a Layer 1 source, register `nz_mfat_manaaki` live, no schedule switched on). Workers: scholarships-au-etl v0.3.0 (feed nz_manaaki: eligible countries by region and destination, levels, approved institutions with their official sites, application rounds and criteria read from the pages; stops if countries or institutions are not found), layer1-operations-control v1.7.1 and layer1-operations-scheduled v1.3.1 (dispatch the New Zealand register).
- Government awards reach courses through approved institutions (Platform Admin: publish the government records; link to approved institutions). Database: `20261008004900` (11 nationality terms added and 2 extended; register record profile sets nationalities from the register's country lists, audience international, and course links at the approved institutions for bachelor, master's, doctorate and postgraduate diploma/certificate courses; `admin_scholarship_register_institutions` for a Platform Admin to pick institutions; the audience and nationality wording jobs no longer overwrite a register record; a register record with full tuition coverage counts as having a stated value; md5-guarded patches; nothing published). Worker scholarships-au-etl v0.3.1 (records where each institution's site redirects; runs the profile after each government register read).
- Scholarship countries (Platform Admin: AU, NZ and CA only for now; plan in place as countries join). Database: `20261008005000` (country switch off for DE, GB, IE and US, which have no courses; `scholarship.country_onboarding` with each country's status, domestic-student wording and government registers; planned registers Chevening, Commonwealth Scholarships, Fulbright; `security.scholarship_country_readiness_v1`; daily job scholarship-country-watch raises a platform issue when a country has courses but scholarships are off or not ready, and resolves it itself; `admin_scholarship_country` (Platform Admin, only when ready, queues the country's universities for discovery); `admin_scholarship_countries`; the university test and the audience reader no longer hard-wire NZ and CA (md5-guarded; behaviour for AU, NZ and CA unchanged)).
- Canadian catalogue and register sources on Layer 1, phase A (Platform Admin: Canada Layer 1 schedule). Database: `20261008005100` (26 sources name their reader, source_system CA_READER: 23 college and provincial catalogues, Aurora and Yukon through the first-party reader, and the IRCC Designated Learning Institutions register; Layer 1 operations rows with verification due now and no schedule switched on; 15 readers added to the run-token allow-list). Workers: layer1-operations-control v1.8.0 and layer1-operations-scheduled v1.4.0 (verify and run Canadian readers; IRCC applied in slices of 200), layer1-ca-live v1.2.0 (accepts the Layer 1 service key; added to the deploy list). layer1-ca-seneca-catalogue: the deployed v0.3.1 is now checked in (git held v0.1.0).
- Clean-up of the old system, batch 1 (Platform Admin: clean up the old system as we go). 24 unused edge functions retired (one-off QS ranking probes and recoveries, Layer 1 UAT gates and inspectors, the Layer 2 trial and discovery prototypes, layer3-benchmark-go5, layer4-course-resolve, scholarship-course-fill-control, search-vector-gate): no repository, database or cron reference; source removed and added to the deploy workflow's retired list for deletion from the live project. Database: `20261008005200` (eight cron jobs switched off on 2 Oct removed: seven of the old Layer 2 pipeline and the old Layer 3 tuition enqueue; refused if any is switched on; functions and history kept; definitions recorded in the file). Canadian probes left in place (Canada parked).
- Phase 3 of the adapter design: merged reading step run side by side with Layer 3 (Platform Admin: US$15/day, ~1,000 courses/day; retire a field at 95%+ agreement and at least as many found). Database: `20261008005300` (`pipeline.adapter_shadow_settings` and `pipeline.adapter_shadow_reads`; `svc_adapter_shadow_claim` and `svc_adapter_shadow_complete`, service role; `security.adapter_shadow_summary_v1` with the retire test, reported only; `admin_adapter_shadow` summary, providers and settings, Platform Admin, logged; jobs adapter-shadow-intake and adapter-shadow-english every 2 minutes). Worker layer3-model-routing shadow mode (`cf247-adapter-shadow-v1.0.0`; routing version and binding hashes unchanged): the adapter's own model (pinned) reads finished Layer 3 courses on the adapter's input for the field (JSON path, heading section, else the whole page) with the same task contract and checks; nothing is admitted. `_shared/cf247-adapter-shadow.ts`.
- Phase 3 shadow run: tuition added and capacity raised (Platform Admin: add tuition or any other attribute as required; finish in about 4 hours). Database: `20261008005400` (md5-guarded: task tuition; tuition read under the tuition task's own prompt, checks and input length with the adapter's pinned model; a pick counts as found and agrees on amount to the dollar, fee year and audience; 1,500 reads a day, 500 a field; courses finished in the last 30 days; 6 reads a field every 2 minutes; job adapter-shadow-tuition). Worker layer3-model-routing shadow v1.1.0. Layer 3 reads only these three fields, so all are now compared.
- Clean-up of the old system, batch 2 (Platform Admin, 9 Oct 2026: retire the old data-admission system). Removed screens: Scrapers › Source profiles (with per-source fetchers and Test fetch one page), Layer 2 workload defaults, Layer 2 automation, dispatcher tuning and scholarship runtime settings on Scrapers & fetchers, the one-off run builder (Run acquisition + deterministic Layer 2) on Automations, the Current Layer 2 wave panel, the Layer 3 course-page pattern requests panel, and code that never showed on screen. Providers › Onboarding now explains that new providers are onboarded through the guided Adapter builder, with a button to open it. Kept: Refresh schedules (Layer 1 still uses them) and the provider registry and keys on Scrapers & fetchers. 11 edge functions retired (layer2-extract, layer2-course-fact-extract, layer3-interpret, layer2-v2-diagnostic, layer2-sync-control, layer2-config-control, layer2-acquire, layer2-batch-runner, layer2-scholarship-extract-v2, scholarship-scope-job-execute, scholarship-runtime-control): source removed and added to the deploy workflow's retired list. Old workflows and tests for these removed. No database change in this batch; the visible release is unchanged.
- Phase 3 shadow run, round 2 (Platform Admin: stronger adapter model). Database: `20261008005500` (md5-guarded: shadow settings gain round and a model override; round 2 reads with Xiaomi MiMo v2.6 Pro as the single pinned adapter model for intakes, English and tuition; same contracts, checks and retire rule; round 1 kept and reported beside it; no adapter's own model choice changed; nothing admitted). Round 1 result (e58): no field met the retire rule (agreement held; the single Qwen3 30B model found fewer values than the Layer 3 ladder).

## 0.1.148 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.221** (Storage & retention: Unreferenced evidence purge, Platform Admin only, re-checked per batch).
- Database: `20261008001200` (file queue, skip log, category, estimate, worker handshake; applied through the connector) and `20261008001300` (run category widened; background worker purges in batches of 500; pasted in the SQL editor). Worker coverage-sweep v0.17.17 (retention_files removes files from the bucket each file names).
- Database: `20261008001400` (Unreferenced evidence estimate counts each file once and only files no kept record uses; the first purge removed 2,280 records and 541 MB against an estimate of 1,686 MB).
- Database: `20261008001500` (Rule 4: adapter fields with low agreement admitted daily, page wins; Canadian fees and the hold list excepted; schedule `l4-rule-low-agreement` 03:37 UTC) and `20261008001600` (new scheduled jobs listed by layer).
- Database: `20261008001700` (Rule 5: where the held value is the Layer 3 model's reading and the adapter's patterns read differently, the adapter reading replaces it in the 10-minute adapter-overwrite job, no review).
- Database: `20261008001800` (Rule 6 measurement: courses bound to a page named for another course, 140 listed). Worker coverage-sweep v0.17.18 (mode page_codes reads stored pages for CRICOS-shaped codes).
- Database: `20261008001900` (Rule 6: 71 courses whose page is named for another course and lacks their CRICOS code unbound, blocked from rebinding to that page, page values withdrawn and sent back to page finding; 15 hand-chosen pages and 54 with the code kept).
- Phase 2: `20261008002000` (CRICOS register adapter stored, switched off; side-by-side replay of the last three register archives with today's Layer 1 code) and `20261008002100` (register files never purged as unreferenced evidence). Worker coverage-sweep v0.17.19 (mode register_replay).
- `20261008002200` and worker v0.17.20: the replay reads 4,000 records a call (a whole archive in one call hit the edge resource limit).
- `20261008002300`: schedule `register-replay` drives the replay one slice a minute and stops itself when done.
- `20261008002400`: the job-log purge cuts off at 7 days before the run started, so it can finish (it previously kept finding newly aged records).
- `20261008002500`: the course-directory purge selects its batch by (provider_id, url); the first run failed on a missing id column and removed nothing.
- `20261008002600`: replay comparison converts durations and fees only when they are numbers. Phase 2 replay result: all three CRICOS archives identical under the adapter and today's Layer 1 code; the newest matches Layer 1's recorded fingerprints for all 25,540 courses.

## 0.1.147 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.220** (Rule 2: the provider's own course page fee with captured evidence is used over the CRICOS registered fee, whatever year it names; no review raised).
- Database: `20261008000900` (`security.course_fee_used_v1` and `admin_fee_rules_report` replaced behind md5 guards; `security.l4_shared_hosts_v1`, `security.fee_evidence_own_site_v1`). No stored fee written.
- Database: `20261008001000` (Rule 3: a provider page fee with no year whose evidence was captured this year is aligned to this year without review; daily at 03:27 UTC as `l4-rule-fee-year-align`; first run aligned 144 fees and closed their 144 Layer 4 items; 71 held where the course already has a different fee for this year), and `20261008001100` (those conflicts: newest evidence wins, the other fee superseded; 59 year-less readings won, 12 dated fees kept; no review items left).

## 0.1.146 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.219** (Platform settings › Storage & retention, Platform Admin only: size, rule, preview and purge per category, background batches, run log).
- Database: `20261008000400` (values from third-party course directories to Layer 4 review: 39 intake, 13 English, 160 course-page items), `20261008000500` (retention runs, estimates, `admin_retention`), `20261008000600` (estimates and worker), `20261008000700` (schedule `retention-worker`). Worker coverage-sweep v0.17.16 (mode retention_files removes screenshots through Storage).
- v2.15.79 remains the accepted recovery release.

## 0.1.145 — 8 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.218** (adapter builder: 6 spread samples, Use as sample on any course page (up to 10), the proposal reads every sample and lists attributes not found per sample; Platform Admin model choice per adapter from qualified intake models).
- Database: `20261008000100` (per-adapter model table and builder actions model and add_sample; 6 samples spread across course types), `20261008000200` (Use as sample by page address; samples setting 6), `20261008000300` (stored pages listed for picking). Worker coverage-sweep v0.17.15 (keeps captured pages when a sample is added; proposal reads all samples).
- v2.15.79 remains the accepted recovery release.

## 0.1.144 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.217** (code split: 41 page-only screens load on demand; React, Supabase and icon libraries in separate long-cached files; first load about 0.93 MB instead of 1.71 MB (257 kB instead of 461 kB compressed); a stale screen file after a deploy reloads the page once).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.143 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.216** (Layer 2 › Adapters is visible again to Pipeline Operators, read only, as the server allows; v2.15.211 had raised it to PIM Admin by mistake. Seven contract specs that checked code from screens redesigned since late September were rewritten to the current screens, keeping their intent).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.142 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.215** (guided adapter build in Layer 2 › Adapter builder: six buttoned steps run by the Platform Admin (find pages, capture samples, model proposal, save in testing and apply, qualify, admit the fields ready to admit); an Adapter column on the Providers list for Platform Admins that opens the builder with the provider loaded, or Create adapter).
- Database: `20261007001900` (builder AI allowance US$1.50 and 60 proposals a day) and `20261007001901` (`admin_adapter_autobuild` states, read by the Providers-list column). No scheduled build: each step uses the existing functions and their own checks.
- v2.15.79 remains the accepted recovery release.

## 0.1.141 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.214** (retired Layer 2 screens `layer2-operations-entry.jsx` and `EnrichmentOperations.jsx` deleted; their contract checks removed or rewritten; Adapter builder opens the visual builder in step 4 and uses only shared colour tokens; a mocked browser check of the builder was added).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.140 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.213** (operator screens cleaned up: raw JSON settings under Advanced (Platform Admin), Adapters list first, Firecrawl credits shown once on Models & services, Environment & integrations links renamed Settings, two unused ranking scripts removed).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.139 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.212** (role guides aligned with server permission checks; Your role section in the Platform guide; Automations wording).
- No database change.
- v2.15.79 remains the accepted recovery release.

## 0.1.138 — 7 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.211** (Layer 2 › Adapter builder: provider, basics, central pages, recognise attributes, validate and admit, on one screen).
- Database: migration 20261007001600 (`public.admin_adapter_builder_basics`, read only, rank 5; `admin_provider_central_page` also accepts `fee_schedule`, patched behind an md5 guard).
- v2.15.79 remains the accepted recovery release.

## 0.1.137 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.210** (Coverage › Attributes opens with a per-field 80% target panel for intakes, English and fees, split by who supplied the value).
- Database: migrations 1880 to 1884 (`pipeline.course_field_source` snapshot, its build, prune and hourly schedule at :55, and `course_coverage` returning `field_sources`). Read only for operators.
- v2.15.79 remains the accepted recovery release.

## 0.1.136 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.209** (the admin course blade's Scholarships context lists only the course's own provider's scholarships).
- Database: migration 1840 (`security.admin_contextual_insights` patched behind an md5 guard so study-level and field scopes count only for the scholarship's own provider). Read only.
- v2.15.79 remains the accepted recovery release.

## 0.1.135 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.208** (unscoped Canada and NZ scholarships queued for review; no links created).
- Database: migration 1830 (insert into `scholarship.course_mapping_candidates`, status needs review, for 19 Canadian and 38 NZ scholarships with no scope, against their own provider's active courses; `on conflict do nothing`).
- v2.15.79 remains the accepted recovery release.

## 0.1.134 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.207** (Canada and NZ scholarship runtime settings added, switched off).
- Database: migration 1820 (two `pipeline.scholarship_runtime_settings` rows, CA and NZ, `enabled` false, `auto_dispatch` false, publication not authorised; insert only, `on conflict do nothing`).
- v2.15.79 remains the accepted recovery release.

## 0.1.133 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.206** (course scholarship lists only include the course's own provider's scholarships; fixes Australian scholarships showing on Canadian courses).
- Database: migration 1810 (`security.scholarship_selection_for_course_impl` patched behind an md5 guard so study-level and field scopes match only the scholarship's own provider). No stored data changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.132 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.205** (suspected half-year page fees held back in the fee-rules dry run, Decision 255).
- Database: migration 1800 (`public.admin_fee_rules_report` adds `suspected_half` and `suspected_half_sample`, and excludes those rows from `would_change`; guarded by the live definition's md5). Read only; no stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.131 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.204** (fee used: courses under a year compare against the whole-course CRICOS fee, Decision 255 correction).
- Database: migration 1790 (`public.admin_fee_rules_report` and `security.course_fee_used_v1` divide the CRICOS total by the course length only when it is a year or more). Read only; no stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.130 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.203** (fee_used added to the Zoho, Wix and website course APIs, Decision 255; deployed Layer 2 checks rewritten for Adapters).
- Database: migration 1780 (`api.zoho_course_lookup_v1` and `api.zoho_course_search_v2` each gain an added `fee_used` key, behind md5 guards). No stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.129 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.202** (course drawer Fees › Fee used: which fee the course uses and why, Decision 255).
- Database: migration 1770 (`security.course_fee_used_v1`, read only, and a `fee_used` key on the drawer's fee summary behind an md5 guard). No stored fee is changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.128 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.201** (Layer 2 › Adapters › Page fees against CRICOS, a read-only dry run for Decision 255).
- Database: migration 1760 (`admin_fee_rules_report`, read only). Nothing is written or changed.
- v2.15.79 remains the accepted recovery release.

## 0.1.127 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.200** (Layer 2 Adapters lifecycle workspace, collapsed cards remembered per session, list-only Task manager; Coverage › Universities and four Layer 2 tabs retired).
- Database: migration 1750 (adapter read cycle column, admin_adapters list/detail/set_on/set_cycle, per-adapter Admit from its own latest Qualify). No adapter was switched and nothing was admitted.
- v2.15.79 remains the accepted recovery release.

## 0.1.126 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.199** (Read pages again, Firecrawl runs, adapter Apply and central pages run as tasks; old progress panels retired).
- Database: migration 1740 (four watcher task kinds; the admin_jobs.kind check constraint widened under the Platform Admin's 13:55 exception).
- v2.15.79 remains the accepted recovery release.

## 0.1.125 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.198** (Task manager shows only live tasks; finished tasks in Jobs; JobButton; old operations console retired).
- Database: migration 1730 (finished tasks written to the Jobs history, live-only Task manager read, task scope).
- v2.15.79 remains the accepted recovery release.

## 0.1.124 — 6 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.197** (Task manager: Qualify adapters and Admit the passing fields; adapter Reading options).
- Database: migrations 1700 (adapter reading options), 1710 (adapters read inactive courses), 1720 (admin jobs, dispatcher, qualifications). Worker v0.17.13.
- v2.15.79 remains the accepted recovery release.

## 0.1.123 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.196** (Read pages again shows Sending… and any error inside the panel).
- No database change
- v2.15.79 remains the accepted recovery release.

## 0.1.122 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.195** (Read pages again for many universities runs in the background).
- Migration 20261005001630 (read pages again in the background)
- v2.15.79 remains the accepted recovery release.

## 0.1.121 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.194** (Coverage › Universities: read pages again for one university or for the universities ticked).
- Migration 20261005001620 (read pages again)
- v2.15.79 remains the accepted recovery release.

## 0.1.120 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.193** (Central English rules applied again for every university, pages bound by hand admitted, online courses show Online as location).
- Migration 20261005001610; worker v0.17.10
- v2.15.79 remains the accepted recovery release.

## 0.1.119 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.192** (Coverage › Universities: hosted courses — exit and nested awards with a register check, shared pages, double degrees and pages that are gone).
- Migrations 20261005001580–20261005001600 (award links and host pages, year-aware register check with tolerances as settings, apply fix where fees are not admitted)
- v2.15.79 remains the accepted recovery release.

## 0.1.118 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.191** (Coverage › Universities: indicative whole-course fees per university, published per university).
- Migrations 20261005001560–20261005001570 (delivery from location, other requirements, whole-course fee range); worker v0.17.9
- v2.15.79 remains the accepted recovery release.

## 0.1.117 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.190** (Coverage › Universities: location, delivery and entry requirement; delivery and exit awards admitted; international view setting).
- Migrations 20261005001490–20261005001550 (delivery, international view, fees per credit, exit awards, exclusions withdraw values); worker v0.17.8
- v2.15.79 remains the accepted recovery release.

## 0.1.116 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.189** (Coverage › Universities tab and central pages).
- Database: central pages and the universities view (migrations 20261005001420 to 20261005001450).
- v2.15.79 remains the accepted recovery release.

## 0.1.115 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.188** (admission by field and course exclusions).
- Database: admission by field and course exclusions (migrations 20261005001400 and 20261005001410).
- v2.15.79 remains the accepted recovery release.

## 0.1.114 — 5 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.187** (adapter term names to months, wave 1 and 2 fixes).
- Migrations 20261005001370 and 20261005001380 (stale adapter readings cleared, refused pages sent back once and only for page-data adapters, term_months); coverage-sweep worker v0.17.3.
- v2.15.79 remains the accepted recovery release.

## 0.1.113 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.186** (visual adapter builder (screenshots, text blocks, page data, marks, pinned model proposal), international fees admitted from admitting adapters, Firecrawl search results kept in the bucket).
- Migration 20261004001340 (adapter fees, builder drafts, bucket adapter-captures, builder settings); coverage-sweep worker v0.17.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.112 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.185** (admitting adapters shown collapsed with their switches, adapter readings replace held values except hand-entered ones, every target university evaluated for its next step).
- Migrations 20261004001310 (adapter readings replace held values, better pages with Firecrawl) and 20261004001320 (adapter evaluation, three settings).
- v2.15.79 remains the accepted recovery release.

## 0.1.111 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.184** (adapter Apply works through large pages within the edge time limit, unsafe adapter patterns refused).
- Migrations 20261004001290 (adapter pattern safety) and 20261004001300 (adapter apply carries on); coverage-sweep worker v0.16.2.
- v2.15.79 remains the accepted recovery release.

## 0.1.110 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.183** (university adapters read page text patterns, extra fields shown for testing, intakes admitted from the adapter's own reading only after the admit switch).
- Migration 20261004001280 (adapter patterns, pick, adapter readings marked, admission plan gate for adapter intakes and English, schedule coverage-admit-intakes); coverage-sweep worker v0.16.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.109 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.182** (University adapters easy to find and the Firecrawl panel loads at once).
- Migration 20261004001270 applied and checked: the Firecrawl panel figures are kept by scheduled jobs (7 seconds down to 0.2).
- v2.15.79 remains the accepted recovery release.

## 0.1.108 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.181** (Decision 253 amended: admit from university adapters after testing, refuse archived and test sites).
- Migration 20261004001260 applied and checked. 380 pages on archived or test sites refused, 317 links, 96 English and 42 intake values from them taken out of use (logged).
- v2.15.79 remains the accepted recovery release.

## 0.1.107 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.180** (Decision 253: Firecrawl by use case for target universities, call log and support report).
- Migrations 20261004001200, 001210 and 001220 applied. coverage-sweep worker v0.14.0 deployed and checked byte for byte.
- v2.15.79 remains the accepted recovery release.

## 0.1.106 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.179** (Decision 252 steps 1-2: Serper search pass into the identity check; page addresses repaired).
- Migrations 20261004001000 and 20261004001100 applied and verified; toolset-runner v1.3.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.105 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.178** (Decision 252 amended: no trial wording; Serper and ScrapingBee keys carry plan limits set in the UI; sample runs).
- Migration 20261004000900 applied and verified; worker toolset-runner replaces toolset-trial.
- v2.15.79 remains the accepted recovery release.

## 0.1.104 — 4 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.177** (Decision 252: toolsets and limits, layer notices, OpenRouter observe only, Serper and ScrapingBee trials).
- Migrations 20261004000600 to 20261004000800 applied and verified against the live project; layer3-model-routing reads its credit policy; new toolset-trial worker.
- v2.15.79 remains the accepted recovery release.

## 0.1.103 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.176** (Scholarship job times follow Melbourne daylight saving; fixed clock times removed from screens and guide).
- 20261004000500_cf247_scholarship_job_text_dst
- v2.15.79 remains the accepted recovery release.

## 0.1.102 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.175** (Course decision support retired with Course links (only reachable from that screen); the course record's scholarship cards cover it).
- none
- v2.15.79 remains the accepted recovery release.

## 0.1.101 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.174** (Scholarships: Course links tab retired with its code; list heading removed (count on the search row); Firecrawl credit cap and reserve are Layer 2 settings shown with credits used).
- 20261004000400_cf247_scholarship_firecrawl_cap_setting
- v2.15.79 remains the accepted recovery release.

## 0.1.100 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.173** (Scholarships at each layer: sources per country and their use (Layer 1), discovery and reading results with per-run limits and job switches (Layer 2), AI check by country (Layer 3), jobs after publishing (Layer 4) — Decision 251).
- 20261004000300_cf247_scholarship_layer_settings
- v2.15.79 remains the accepted recovery release.

## 0.1.99 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.172** (Scholarships module lists published scholarships only (no status pills or status filters); record lists its courses; New Zealand and Canadian university scholarships (Decision 250)).
- 20261004000100_cf247_scholarships_nz_ca
- v2.15.79 remains the accepted recovery release.

## 0.1.98 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.171** (Scholarship screens follow the mockup: list status pills and columns, record drawer with source and hand edits, publishing tiles and reasons, course scholarship cards).
- 20261003003000_cf247_scholarships_page_status; 20261003003100_cf247_scholarship_screens_to_mockup
- v2.15.79 remains the accepted recovery release.

## 0.1.97 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.170** (Platform guide reviewed for the scholarship module).
- v2.15.79 remains the accepted recovery release.

## 0.1.96 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.169** (Scholarship publishing in Layer 4; course search; clean values; course attribute with savings (Decisions 247-249)).
- Migrations 20261003002500-002800; jobs scholarship-course-attribute (15 min) and -full (06:51 AEST).
- v2.15.79 remains the accepted recovery release.

## 0.1.95 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.168** (Scholarship award tiers and nationality from wording; Zoho scholarships action (Decisions 245, 246)).
- Migrations 20261003002100–002400; jobs scholarship-nationality (hourly).
- v2.15.79 remains the accepted recovery release.

## 0.1.94 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.167** (Scholarship audience read from wording (Decision 244)).
- Migration 20261003002000 scholarship_audience_from_wording; job scholarship-audience hourly.
- v2.15.79 remains the accepted recovery release.

## 0.1.93 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.166** (Academic calendars: Start months by hand folded into the one list; calendar parser v0.2.2 reads section-row layouts (Curtin)).
- Worker coverage-sweep v0.13.5 (calendar parser provider-policy-v0.2.2); 392 stored calendar pages re-parsed, 68 proposals.
- Provider drawer edited inline in priority order; Scholarships Audience filter (migration 20261003001900) and clipped Award column; course tuition field named against the CRICOS cost.
- v2.15.79 remains the accepted recovery release.

## 0.1.92 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.165** (Academic calendars: internal and external links on each row; months set by hand win; Not an intake no longer holds a course).
- Migration 20261003001700 applied.
- v2.15.79 remains the accepted recovery release.

## 0.1.91 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.164** (Academic calendars: Intake 1 and 2 pre-filled from Trimester or Semester 1 and 2, raw value beside them).
- v2.15.79 remains the accepted recovery release.

## 0.1.90 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.163** (Academic calendars: Intake 1, 2 … columns; a later intake can be left as Not an intake).
- v2.15.79 remains the accepted recovery release.

## 0.1.89 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.162** (Academic calendars: one column per study period with the suggested month as an input; Approve applies what is shown).
- v2.15.79 remains the accepted recovery release.

## 0.1.88 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.161** (start months by hand on Layer 4 › Attributes › Academic calendars; the calendar step is live).
- Migrations 20261003001500–001520 (Decision 228 parts 2 and 3) applied.
- v2.15.79 remains the accepted recovery release.

## 0.1.87 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.160** (Settings page: every throttle, budget and page-identity proof editable in one place, by pipeline step).
- Migration 20261003001200 adds admin_pipeline_settings_read/write.
- v2.15.79 remains the accepted recovery release.

## 0.1.86 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.159** (course drawer opens on its values, each with its Change button; the foldable editor and the comparison strip are gone).
- v2.15.79 remains the accepted recovery release.

## 0.1.85 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.158** (Fee schedules open on Waiting; Academic calendars explained).
- v2.15.79 remains the accepted recovery release.

## 0.1.84 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.157** (Fee schedules, English policies and Academic calendars moved from Coverage › Attributes to a new Layer 4 Review › Attributes tab).
- v2.15.79 remains the accepted recovery release.

## 0.1.83 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.156** (Course-page search budget moved to the top of Jobs › Priority queue).
- v2.15.79 remains the accepted recovery release.

## 0.1.82 — 3 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.155** (English policies: bulk approval and one approved document per university; course-page search budget on the Priority queue screen; overnight admission rules for Australia, Canada and New Zealand, Decisions 233-236).
- Database: reference sources and website hints; Australian English by exact title; English policy flag rule; Canada and New Zealand pinned first; Canadian search by title words; Canadian field + award and New Zealand degree-name page rules; bulk policy decisions; search cap setting.
- v2.15.79 remains the accepted recovery release.

## 0.1.81 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.154** (English policies applied for 11 universities, faster policy counts, intake cascade step 2, intake check v1.3.0 contract (not qualified)).
- Database: English policy plan counts kept and refreshed every 10 minutes; group-1 English policies approved; semester month helpers; intake step 2 (Claude Haiku 4.5) switched on and quoting failures sent back once; paused v1.3.0 intake profiles.
- v2.15.79 remains the accepted recovery release.

## 0.1.80 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.153** (Decisions 226-227: quote failures re-run; English from each university's policy).
- Database: migrations 20261002182700-20261002183200 (quote-failure re-run, reading English policies and calendars, policy proposals, English plan/approval/apply, agreement gate); coverage-sweep worker v0.9.5 (parser provider-policy-v0.2.1).
- v2.15.79 remains the accepted recovery release.

## 0.1.79 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.152** (Australian tuition from CRICOS only).
- Migration 20261002182600 (applied): Australian tuition from CRICOS; provider-page tuition chased only where the regulator publishes none.
- v2.15.79 remains the accepted recovery release.

## 0.1.78 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.151** (tuition reviews settled against the page's international view).
- Migrations 20261002182400 and 182500 (applied): review pages re-read first; tuition reviews settled every 10 minutes (job layer4-tuition-settle).
- v2.15.79 remains the accepted recovery release.

## 0.1.77 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.150** (fees follow the page's domestic or international view; answered tuition reviews closed).
- Migrations 20261002182100-182300 (applied): answered tuition reviews closed, retired fee feed paused, re-extraction in each country's currency.
- v2.15.79 remains the accepted recovery release.

## 0.1.76 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.149** (Fetch an area on the course-page sweep; Websites to find; worker errors say what to do).
- Migration 20261002182000 (applied): admin_coverage_fetch_area, Websites to find, 5-minute wait for the AI tuition check, faster tuition hand-off.
- v2.15.79 remains the accepted recovery release.

## 0.1.75 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.148** (Layer 3 cascade never falls back to a switched-off model; pending cascade claims labelled).
- Migration 20261002181900 (applied): Recent results hides the placeholder profile of an unanswered cascade claim.
- v2.15.79 remains the accepted recovery release.

## 0.1.74 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.147** (old Layer 2 pipeline retired; actionable Layer 2 overview; daily progress by country; Canada admission).
- Migration 20261002181800 (applied): 7 old Layer 2 jobs paused; Canada admission rule (CAD) and discovery queue; site finder returns country and DLI.
- v2.15.79 remains the accepted recovery release.

## 0.1.73 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.146** (Decision 219: New Zealand regions and country-named state filter; bulk flagged values).
- Database: migration 20261002181700 applied to fxcwkweaxjtknorudmwp.
- v2.15.79 remains the accepted recovery release.

## 0.1.72 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.145** (Decision 218: fee periods settled automatically; Live activity names the job behind each error).
- Database: migration 20261002181600 applied to fxcwkweaxjtknorudmwp; evidence-link-index lighter.
- v2.15.79 remains the accepted recovery release.

## 0.1.71 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.144** (Decision 217: New Zealand course pages, search and tuition; fee schedules follow the country).
- Database: migrations 20261002181300 and 20261002181400 applied to fxcwkweaxjtknorudmwp; coverage-sweep v42 (reader v0.9.1).
- v2.15.79 remains the accepted recovery release.

## 0.1.70 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.143** (Decision 216: every background function signs in with one-time run passes).
- Database: migration 20261002181200 applied to fxcwkweaxjtknorudmwp; 28 edge functions redeployed from CI.
- v2.15.79 remains the accepted recovery release.

## 0.1.69 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.142** (Decision 215: evidence link indexing fixed; Live activity shows worker errors).
- Database: migrations 20261002180900, 20261002181000 and 20261002181100 applied to fxcwkweaxjtknorudmwp; edge function evidence-link-index v4.
- v2.15.79 remains the accepted recovery release.

## 0.1.68 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.141** (Live activity; scholarship discovery refill; release check fixed).
- Migrations 20261002180600-180800 (Decision 214).
- v2.15.79 remains the accepted recovery release.

## 0.1.67 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.140** (coverage by country and university; fee schedule bulk approval; course-page pattern requests retired).
- Migration 20261002180500_cf247_coverage_countries_fee_review_patterns (Decision 213).
- v2.15.79 remains the accepted recovery release.

## 0.1.66 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.139** (scholarship publishing rules: domestic only, up-to values, savings per year).
- Migration 20261002180400_cf247_scholarship_publishing_rules (Decision 212); scholarship reader v0.5.4.
- v2.15.79 remains the accepted recovery release.

## 0.1.65 — 2 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.138** (scholarship eligibility and award scope from provider pages).
- Migration 20261002180300_cf247_scholarship_criteria_and_scope (Decision 211); coverage-sweep worker v0.9.0, scholarship reader v0.5.3.
- v2.15.79 remains the accepted recovery release.

## 0.1.64 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.137** (fee schedules settle flagged fees).
- Migration 20261001180200 (fee schedule settles flagged fees) applied live; stored md5 matches the file.
- v2.15.79 remains the accepted recovery release.

## 0.1.63 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.136** (Platform guide in the menu).
- v2.15.79 remains the accepted recovery release.

## 0.1.62 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.135** (QS and THE filters by country, state and provider; ranked universities linked to providers).
- Migration 20261001180000 (ranking links and filters) applied live; stored md5 matches the file.
- v2.15.79 remains the accepted recovery release.

## 0.1.61 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.134** (fee schedules for approval; Layer 3 claim fixes).
- Migrations 20261001179000 (Layer 3 stale claim), 179100 (Layer 3 claim speed) and 179200 (fee schedule proposals) applied live; stored md5 matches each file.
- v2.15.79 remains the accepted recovery release.

## 0.1.60 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.133** (course links of every kind, who can apply, link refresh schedules, country admission rules).
- Migrations 20261001170000, 171000, 172000, 173000 and 174000 applied to fxcwkweaxjtknorudmwp; each stored statement's md5 equals its file.
- v2.15.79 remains the accepted recovery release.

## 0.1.59 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.132** (Older screens in the compact style).
- v2.15.79 remains the accepted recovery release.

## 0.1.58 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.131** (Melbourne time, plain wording, clear counts and tidy-ups).
- v2.15.79 remains the accepted recovery release.

## 0.1.57 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.130** (Edit in list for tuition, intakes, English, campuses and scholarships).
- Database (applied live): 20261001140000 (list read for tuition, intakes, English) and 20261001150000 (campus and scholarship edits with the manual lock guard).
- v2.15.79 remains the accepted recovery release.

## 0.1.56 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.129** (Layer 4 review queue tidy-up).
- v2.15.79 remains the accepted recovery release.

## 0.1.55 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.128** (Layer 2 split into Overview, Fetch an area, History and Source profiles).
- v2.15.79 remains the accepted recovery release.

## 0.1.54 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.127** (Layer 3 Work queue and Layer 2 Source profiles in the compact style).
- v2.15.79 remains the accepted recovery release.

## 0.1.53 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.126** (Fee rules, Flagged values, Send back and Layer 3 Control tidy-up).
- v2.15.79 remains the accepted recovery release.

## 0.1.52 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.125** (Dashboard: Waiting for you first).
- Database (applied live): 20261001130000 (admin_waiting_read).
- v2.15.79 remains the accepted recovery release.

## 0.1.51 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.124** (Schedules folded into Automations; Readiness by area into Attributes; Sources moved to Operations).
- v2.15.79 remains the accepted recovery release.

## 0.1.50 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.123** (Duplicate screens merged: Regulatory settings into Layer 1, Go-live checklist, flat Capacity, Layer 4 Blocks).
- v2.15.79 remains the accepted recovery release.

## 0.1.49 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.122** (One home per setting: Models & services is the only on/off place; Environment holds keys only).
- Database (applied live): 20261001120000 (switching a model on needs a passed test; adding to a cascade no longer switches a model on).
- v2.15.79 remains the accepted recovery release.

## 0.1.48 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.121** (Reference data: Reference sources control how third-party sites are used; Key dates edited in place).
- Database (applied live): 20261001110000, 20261001111000 (reference sources), 20261001112000 (key dates). Edge function: coverage-sweep reads the list.
- v2.15.79 remains the accepted recovery release.

## 0.1.47 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.120** (Courses and Providers: Edit in list — change fields in place in the list; pages no longer run off the right edge).
- Database (applied live): 20260930180000 (admin_catalogue_edit_rows).
- v2.15.79 remains the accepted recovery release.

## 0.1.46 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.119** (Parse.bot removed completely; ranking imports are file upload only).
- Database (applied live): 20260930170000 (Parse.bot provider, 2,098 routes and stored key deleted; two functions edited behind md5 guards).
- Edge functions: ranking-publisher-url-import, ranking-qs-url-import and ranking-the-url-import retired; layer2-provider-control, layer2-acquire-v2, layer2-scope-discover-scheduled and ranking-layer1-etl no longer mention Parse.bot.
- v2.15.79 remains the accepted recovery release.

## 0.1.45 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.118** (Platform settings › Models & services: on/off switch for every AI model and page-fetching service; anything off is greyed and not offered in operation screens).
- Database (applied live): 20260930160000 (admin_services_read, admin_services_control; Layer 3 Control hides steps whose model is off).
- v2.15.79 remains the accepted recovery release.

## 0.1.44 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.117** (Batch rules: approve fixed, preview in one compact panel, errors shown in place).
- Database (applied live): 20260930150000 (layer4_mass_operations accepts course_tuition run logs).
- v2.15.79 remains the accepted recovery release.

## 0.1.43 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.116** (Layer 4 › Batch rules: fee wording rules with preview, found wordings, draft → approve & run, hourly runs, pause; values entered by hand never changed).
- Database (applied live): 20260930140000 (fee_wording_rules, fee_rule_admissions, admin_fee_rules_read / admin_fee_rule_preview / admin_fee_rule_control, hourly fee-wording-rules job).
- v2.15.79 remains the accepted recovery release.

## 0.1.42 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.115** (Scholarships › Course links: one decision per scholarship, all / matching / none, with live preview, suggestion from the name, history; decisions govern the automatic sweep).
- Database (applied live): 20260930130000 to 20260930133000 (scholarship scope decisions, admin_scholarship_links_read/detail/decide, hourly scholarship-scope-apply job, sweep guard trigger).
- v2.15.79 remains the accepted recovery release.

## 0.1.41 — 1 Oct 2026

- Prepared visible PIM Admin release candidate **v2.15.114** (Edit this course / Edit this provider panels; Add course and Add provider; values entered by hand always win over automation; history of hand changes).
- Database (applied live): 20260930120000 (manual locks with guard triggers on course facts, courses and providers; manual entry source; admin_course_edit_read/edit/create, admin_provider_edit_read/edit/create; hand-entered official pages trusted by the page reader). Also 20260930110000 to 114000 (course link recipes, link search and reverse match for the top 10 universities; backend only).
- v2.15.79 remains the accepted recovery release.

## 0.1.40 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.113** (Scheduled jobs › Priority queue: pin universities, states, countries or single courses to the front, reorder, remove; current order with pages matched and waiting).
- Database (applied live): 20260930090000 and 20260930091000 (provider ranking; Layer 3 and page reading take the largest providers first; Firecrawl for their blocked pages), 20260930100000 and 20260930101000 (priority pins, course priority, admin_priority_read/search/control; claim and page reader take pinned work first).
- v2.15.79 remains the accepted recovery release.

## 0.1.39 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.112** (Provider contacts under Catalogue; new Catalogue › Reference data with Ranking imports, Key dates and Key links; Onboarding under Providers; Coverage & completeness tabs Courses, Attributes, Readiness by area).
- Database (applied live): migration 20260930070000_system_identity_auth_list_fix — NULL token columns on the system automation identity set to empty strings, so the Auth admin user list works again (Users & roles).
- v2.15.79 remains the accepted recovery release.

## 0.1.38 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.111** (Layer 3 without Sonnet: model choice per field on Layer 4 Review › Send back to AI, including models whose cascade step is off).
- Live changes: Claude Sonnet 4.6 switched off in the intake and English cascades (logged admin control); intake and English routes every minute, 40 pages, 8 in parallel.
- Database (applied live): 20260930060000 (four cheaper intake candidates; none met the 80%-right, zero-wrong bar on the frozen holdout), 20260930061000 (pinned model from Layer 4: handoff column, claim and completion edited in place behind checksums, send_back model choice).
- Edge function layer3-model-routing: cascade v1.1.0 (a pinned page goes to its named model only).
- v2.15.79 remains the accepted recovery release.

## 0.1.37 — 30 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.110** (UI control sweep: Scheduled jobs > Automations for all 58 scheduled jobs with pause or resume per job or area, run now, frequency and batch size; Layer 4 Review > Send back to AI and a Send back to AI button on each Layer 3 task; Scholarships > Publishing with publish batch, hold and release).
- Database (applied live): migrations 20260930050000–20260930052000 — pipeline.automation_catalogue, pipeline.admin_control_events, public.admin_automations_read and public.admin_automation_control, public.admin_requeue_read and public.admin_requeue, public.admin_scholarship_publishing_read and public.admin_scholarship_publishing (reads rank >= 3, changes Platform Admin; three upkeep jobs top admin only); reason groups without amounts and failed counts that exclude released work (checksum-guarded).
- v2.15.79 remains the accepted recovery release.

## 0.1.36 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.109** (Layer 4 Review tabs: Review queue and Flagged values; operators confirm, edit or remove tuition recorded as per year when the page states no period).
- Database (applied live): migrations 20260930040000–20260930043000 — tuition per-year rule at admission with flags (pipeline.data_flags), public.admin_data_flags_read and public.admin_data_flag_resolve (rank >= 4 to change), period-word and reject-term exclusions, English daily limit US$10.
- v2.15.79 remains the accepted recovery release.

## 0.1.35 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.108** (Layer 3 control: Control, Models and Work queue tabs; per-task run or pause, daily limit and the model cascade with reorder, switch on or off, add qualified model and remove; logged changes).
- Database (applied live): migration 20260930030000_cf247_l3_control_and_requeue — public.admin_layer3_control_read and public.admin_layer3_control (Platform Admin); parked Layer 3 and Layer 4 work returned to Layer 3.
- v2.15.79 remains the accepted recovery release.

## 0.1.34 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.107** (admin simplification: five-section menu with old links redirected, one standard page layout in the shared kit, Coverage & completeness inside the app shell, new Platform health page and top-bar status dot, Layer 3 AI validation tabs, sources side by side on scholarship and course detail, Environment & integrations overview).
- Database (applied live): migration 20260930000000_cf247_admin_ui_reads — new read-only public.admin_layer3_operations and public.admin_source_comparison (with security-definer implementations); no existing function replaced.
- Removed src/layer2-navigation-restore.js (menu reordering by page scripting); the menu now comes from src/nav-map.js.
- v2.15.79 remains the accepted recovery release.

## 0.1.33 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.106** (B2 UI uniformity release with R12: one token set, one component kit, en-AU formats, "Layer N" wording; completeness states and the course completeness score on Course coverage).
- Database (applied live): migration 20260929190000_cf247_coverage_completeness_states — new helper security.coverage_completeness_state; checksum-guarded replacement of security.admin_course_coverage_read adding completeness states, the completeness score and a completeness-state course list (existing keys unchanged).
- Removed unreachable source files (legacy src/main.jsx and its stylesheets, and unmounted entry scripts).
- v2.15.79 remains the accepted recovery release.

## 0.1.32 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.105** (University group filter on Courses and Providers; university group shown on provider detail).
- Database (applied live): migration 20260929171000_cf247_admin_university_group_filter — checksum-guarded patches of the admin course and provider page functions, the catalogue filter options (new kind university_group) and provider detail; new helper security.university_group_provider_ids.
- v2.15.79 remains the accepted recovery release.

## 0.1.31 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.104** (complete-coverage sweep, website discovery, document change checks, Layer 3 throughput).
- Database (applied live): coverage sweep tables and services (discover, bind v2 one-to-one, read, find_site), coverage states candidate/blocked/page_found from the sweep, Firecrawl budget guard counts sweep usage, provider document checks, Layer 3 profile 15,000/day; schedules coverage-discover, coverage-bind, coverage-read, coverage-find-site, provider-document-check-monthly/-weekly-q4.
- Edge functions: coverage-sweep v0.4.0 (new), fee-schedule-etl v0.8.0.
- v2.15.79 remains the accepted recovery release.

## 0.1.30 — 29 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.103** (complete-coverage statistics; UQ English requirements in Search).
- Database (applied live): pipeline.course_attribute_coverage and pipeline.course_coverage_daily, security.course_coverage_build_v1 (hourly), admin_read operations course_coverage and course_coverage_courses; UQ English Search gate; double-degree higher-component rule.
- Data Quality: new "Course coverage" view (#course-coverage).
- v2.15.79 remains the accepted recovery release.

## 0.1.29 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.102** (Decision 162 step 1: badges from stored provenance; Decisions 161 and 162 cadence; Layer 2 discovery carry-forward).
- Database (applied live): security.admin_course_field_states reads stored provenance (Layer 3 admitted work items, Layer 4 resolutions, CRICOS sources) and provider-scoped Layer 2 sources; Layer 2 discovered URLs carried forward across settings-only profile versions; UQ and RMIT course-page refresh every 90 days; RMIT refresh re-enabled.
- Course page: new states "CRICOS tuition applies" and "Not collected"; badge tooltips show what resolved each value.
- v2.15.79 remains the accepted recovery release.

## 0.1.28 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.101** (Compare datasets on by default; Decision 160 Layer 3 activation; QILT SES 2025 applied; QS parser v1.4.0).
- Database (applied live): Layer 3 safe-abstention qualification and open-item move to the qualified profile; QILT apply guard accepts a verified institution's equivalent providers; Compare course mode falls back to state-level PRISMS context.
- Edge functions: ranking-qs-official-etl v1.4.0 (deploy allow-list updated).
- Compare: datasets on by default, never disabled before a selection; course-mode labels.
- v2.15.79 remains the accepted recovery release.

## 0.1.27 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.100** (Layer 1 closure, Decision 159; R5, R6, R14, R22, R25; Decision 149 identifiers; R23/R26 evidence).
- Database (applied live): NZQA seen tracking with departures and reactivation; 30-day re-verification of register rows; active counts in run summaries; provider departures review (Layer 4); GLOBAL country for ranking runs and scheduled checks; statistics edition rules, candidates and monthly discovery (Decision 134); country-scoped register identifiers (Decision 149); Layer 2 capture reuses identical files; ranking clean-up (THE 2016–2024 applied, THE "2015" withdrawn, QS 2025 restored).
- Edge functions: layer1-operations-scheduled v1.2.1, layer1-operations-control v1.6.0, ranking-publisher-control (internal apply of validated uploads), ranking-layer1-etl v1.6.1, qilt-au-etl v0.3.0, prisms-au-etl v0.2.0, statistics-edition-discovery v1.0.0 (new); allow-list updated.
- Layer 1 card: QILT family with survey tabs; new editions with Apply. Layer 4: Provider departures tab.
- v2.15.79 remains the accepted recovery release.

## 0.1.26 — 28 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.99** (Package 10: Decision 155 steps 2, 5, 6 and 7; R18–R21).
- Database (applied live): per-provider discovery links (evidence link index 188 MB emptied; candidates proven identical for all 648 providers); register fingerprints and run plans (change-based apply; bootstrap from the accepted file); automatic departures with a 2% hold and Platform Admin approval, reactivation and provider review list; duplicate register evidence clean-up (746 copies, 1.7 GB, sample verified byte for byte); automatic ingestion within the pass band (layer1-auto-ingest, CRICOS and NZQA).
- Edge functions: layer1-operations-control v1.5.0, layer1-au-depth v1.7.0, layer1-au-cricos-facts v1.2.0, evidence-storage-dedupe v1.0.0 (new); allow-list updated.
- Layer 1 card: register breakdown, departures and approval, automatic ingestion setting.
- v2.15.79 remains the accepted recovery release.

## 0.1.25 — 27 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.98** (Package 9b: Layer 1 background runs and live progress; Decision 155 part 1).
- Database (applied live): run lease and background driver (layer1-run-driver, every minute); automatic retry of temporary source errors (1, 2, 4, 8, 15 minutes); evidence reuse by content hash; system-queued runs; retirement of the 809 Australian courses no longer in CRICOS (audited in pipeline.layer1_course_retirements).
- Edge functions: layer1-operations-control v1.3.0, layer1-nz-live v1.2.0 (now in the repository), layer1-register-etl v1.5.0, layer1-au-depth v1.6.1; added to the deploy allow-list.
- Layer 1 card: live progress, retry and failure states, resume from the stopped item.
- Ranking family cards use the newest ingested edition and show its year in the title; newer editions without data show as pending (fixes CF-068 deployed UAT).
- v2.15.79 remains the accepted recovery release.

## 0.1.24 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.97** (Package 8: efficient, observable platform; Decisions 146 refined, 150, 152, 153).
- Platform resources and cost panel (Environment & Migration): hourly observations (size vs memory, cache hit, jobs, overlaps, acquisition and AI usage, largest tables), alerts, 30-day trends, cost model, admission lifecycle.
- Database (applied live): narrow evidence link index; Micro workload schedule; system automation identity; Layer 1 write-only-when-changed; capacity observation fix; hourly resource recorder and cost model; admission lifecycle policy (3,057 Layer 2 profiles aligned).
- v2.15.79 remains the accepted recovery release.

## 0.1.23 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.96** (Package 7, part 2: evidence-first onboarding, Decisions 146 and 147).
- Evidence link index: edge function evidence-link-index reads stored evidence (bucket "evidence") and records links; runs every minute, prioritised by providers waiting for onboarding; allow-listed in the deploy workflow (verify_jwt false, own authentication).
- Candidate ranking from the link index (security.layer2_catalogue_candidates_v1); automatic discovery job every 5 minutes within Platform Admin limits; attempts audited; submissions record origin person or automatic.
- Onboarding snapshot refreshed every 10 minutes: queue read 25.8 s to 1.2 s; discovery job 0.4 s.
- Panel: candidates with View evidence, automatic status, Qualified and Needs a person states. v2.15.79 remains the accepted recovery release.

## 0.1.22 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.95** (Package 7a: Layer 2 provider onboarding, Decision 141).
- New Layer 2 panel: provider onboarding queue (largest first, state per provider) with per-provider catalogue page submission: Check (dry run) then Validate & qualify (Pipeline Operator); three-course identity check 3 of 3 decides qualification.
- Database (already live): layer2_provider_onboarding_queue_v1, layer2_provider_catalogue_submit_v1 (audited), pipeline.layer2_provider_catalogue_submissions.
- Layer 2 automation settings (Decisions 141, 146): pipeline.layer2_auto_discovery_settings with audit; read (Curator+) and save (Platform Admin, reason required, providers in flight capped at Firecrawl concurrency); card in Scraper Config above dispatcher tuning. Automation off by default.
- Contract test cf-247-layer2-provider-onboarding (onboarding panel and automation card). v2.15.79 remains the accepted recovery release.

## 0.1.21 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.94** (Package 5, P3 screen review: Operations group).
- Decision 133 supersedes A24 (CF-CHG-20260830-048): Layer headers no longer repeat the page title (embedded Layer 1 and 2 keep a title only in pop-up mode; Layer 1 embedded region gets aria-label); slim light header style; a24 test rewritten to one title per screen; a21, layer2-operations-maturity and openLayer2 check the page title.
- Jobs (J1-J4): count columns only when present, UNSPECIFIED mode hidden, SUCCEEDED shown as Completed, compact table width; "Operational console" label removed.
- Layer 4 (L2-L4): queue scrolls in its column with a sticky decision panel; neutral Suggested reject wording; batch history loads only its summary until opened.
- Layer 3 (T1): paused notice while no model is qualified.
- A2/A3: developer eyebrow and CF build labels replaced with plain titles.
- Database (already live): provider rule fee-explanation pattern (Decision 131); one current provider tuition per course (Decision 132). v2.15.79 remains the accepted recovery release.

## 0.1.20 — 26 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.93** (P3 item 1).
- Regression fix: Jobs and Scheduled Tasks added to HIDDEN_ROUTES and a refresh-scheduling alias added, so #jobs, #scheduled-tasks and #refresh-scheduling resolve again after the v2.15.91 menu merge.
- Stale live-site test sweep (Decision 127): 430 literal UI expectations checked statically; stale ones updated to current wording (Schedule Configuration, Latest Refresh Queue, Profile routing, contact reconciliation, eligibility inference); drifting counts checked by pattern; every remaining expectation classified (database data, dynamic text, test input, or must-not-appear). v2.15.79 remains the accepted recovery release.

## 0.1.19 — 25 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.92** (Package 3).
- Deterministic provider-rule admission (Decisions 106, 124): security.provider_rule_admit_v1 with proof and apply modes, pipeline.provider_rule_admissions audit, review items marked superseded; scheduled every 15 minutes. First run admitted 160 UQ items (89 courses).
- Layer 3 status (Decision 125): enqueue runs; AI dispatch and admission stay paused until a model passes two clean runs.
- Administration: layer2-navigation-restore.js no longer injects Layer 1-4 buttons into the Administration tab row (Decision 116); cf-142-143 contract now asserts it does not.
- Notes include Packages 2b-2d (visible-text quotes, year selectors, fair benchmark, shared OpenRouter key). v2.15.79 remains the accepted recovery release.

## 0.1.18 — 25 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.91** (Package 2).
- Menu: Jobs and Scheduled Tasks merged into "Jobs & Schedules" (tabs); single pages kept as routes; test helper clickPrimaryNav maps the old labels to the tabs.
- Provider fee profiles: pipeline.provider_fee_profiles, security.apply_provider_fee_profiles_v1 (every 5 minutes), first rule uq-program-page-indicative-annual-v1; targets stamped basis_source provider_fee_rule:<code>.
- Layer 3 (binding change, requires re-qualification): validator accepts "annual" where an approved provider rule set "indicative_annual" (provider_rule_basis flag); interpreter records the rule's basis; benchmark case production_provider_rule_indicative_annual; manifest regenerated.
- P5a: pipeline.evidence_acquisition_provenance_v1 (tool, adapter, attempt per Evidence item).
- Scheduled Tasks: Layer 1-3 shortcut row removed; replay-safety sentence restored. Dashboard "Open Review Queue" relabelled "Open Layer 4".
- Stale tests fixed: cf-092 (terminalJob, menu), m2-5-platform-maturity-admin (Open PIM, version pin), admin-navigation order. v2.15.79 remains the accepted recovery release.

## 0.1.17 — 25 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.90** (Package 1: queue relief, Jobs simplification, release history).
- Layer 3: shared quoteComparable / evidenceQuotePresent in cf247-tuition-validation.ts (visible-text comparison: link targets, JSON escapes and formatting removed on both sides); used by layer3-work-interpret and the tuition benchmark; new production-shaped benchmark case production_markdown_link_annual; binding manifest regenerated (validator_source_sha256 9667690c...). Requires deploy and re-qualification before it runs.
- Layer 4: Send back to Layer 3 re-queues the tuition work item (trigger on layer4_decisions); gated "Send back" suggestion; official course link suggestion rules.
- Jobs: MiniCounts shows only recorded, non-zero counts.
- Release history: scripts/build-release-history.mjs (prebuild) generates public/release-history.json from legacy history, docs/release-notes and the manifest; public/release-history.html; the release overlay fills in missing releases and links to the history.
- .github/workflows/deploy-edge-functions.yml: guarded manual deployment. v2.15.79 remains the accepted recovery release.

## 0.1.16 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.89**: Layer 4 decision forms for official course links and scholarship scope.
- Backend: security.layer4_course_link_apply_impl records reviewer links in catalogue.course_links (https only; search, social and listing sites refused) and refreshes search; security.layer4_scholarship_scope_close_impl allows Mark as done only when no candidate courses need review; decisions routed by category; desk read adds per-category can_approve (never empty), scope_pending and provider_domain.
- New source "Layer 4 human review" (source_type layer4_human_review), approved for official_course_url in search (programme owner decision 24 Sep 2026, option A).
- Stale tests: cf-205, cf-208 and cf-142-143 updated to current names and the release-manifest authority; m245-release-currentness-ranking-fix-contract and m245-release-dialog-history-contract retired (superseded by m245-release-history-v21575-persistence-contract). v2.15.79 remains the accepted recovery release.

## 0.1.15 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.88**: Layer 4 team and forecast (L4-D: public.layer4_team_forecast_v1, read-only; managers rank 5+ see everyone, others their own row), plus Layer 4 task chips show waiting counts; tuition items without a proposed fee keep Edit and approve (main action).
- Notes include backend fixes merged without a version change: PERF-5 provider rankings index path (course detail timeouts) and the scoped search refresh WHERE clause required by pg_safeupdate for app-path approvals. v2.15.79 remains the accepted recovery release.

## 0.1.14 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.87**: Layer 4 approvals fixed.
- security.layer4_tuition_apply_impl: tuition Approve / Edit and approve record catalogue.course_fees with the Layer 3 admission key convention and refresh the course in search; strict value checks. layer4_review_decide_impl routes tuition decisions to it (previously refused as "field is not enabled for scalar Layer 4 editing").
- Desk read: approve suggestion and can_approve require a proposed fee already marked per year.
- Layer 4 screen: edit form carries its own note (no pop-up), errors shown in the panel, main actions hidden while editing. Floating OpenRouter key launcher removed from the shell. v2.15.79 remains the accepted recovery release.

## 0.1.13 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.86**: Layer 4 team working (L4-B).
- Claims: pipeline.layer4_review_items.claimed_at; public.layer4_claim_v1 (claim on open, 30-minute idle lapse, release); desk read adds claim fields; batch decisions refuse items actively claimed by another reviewer.
- Layer 4 screen: claim on open, "In review" marking with reviewer, All / Mine / Unassigned filter (remembered), keyboard keys R/A/E/N, tuition Edit and approve form, scholarship tools collapsed in Batches. v2.15.79 remains the accepted recovery release.

## 0.1.12 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.85**: Layer 4 batches (L4-C).
- New reads/actions: public.layer4_review_batches_v1 (groups by task and rule-based suggestion) and public.layer4_batch_decide_v1 (Pipeline Operator+, 2-100 previewed items of one kind, typed confirmation, no bulk edit, each item decided through layer4_review_decide_impl, batch logged as review_batch, all or nothing). pipeline.layer4_mass_operations accepts target_kind review_batch.
- Desk read: scholarship scope items named, plain reason, can_approve flag.
- Layer 4 screen: Review one by one / Batches switch (remembered); batch preview with untick, reason and confirmation; scholarship scope tools embedded in the Batches view. The mass-operations script no longer self-mounts via MutationObserver. v2.15.79 remains the accepted recovery release.

## 0.1.11 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.84**: the Layer 4 mass-operations panel mounts below the review desk and is collapsed by default (heading and count cards visible; "Open batch work" reveals the cohorts). Interim step before L4-C folds it into a Batches tab. v2.15.79 remains the accepted recovery release.

## 0.1.10 — 24 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.83**: Layer 4 review desk (L4-A).
- New read public.layer4_review_desk_v1 (additive; the existing queue is unchanged): course and provider names, plain task label, age, plain reason, recorded value, AI suggestion as text, cleaned page quote, links and web search, rule-based suggestion, queue summary; raw values under technical.
- Layer 4 screen: queue plus one decision panel, suggestion-led primary action, pre-filled decision note, More menu, collapsed technical detail, remembered status and task filters, next item after each decision. Provider-contact reconciliation actions unchanged.
- PERF-4 (no screen change of its own): Evidence filter options served from a background snapshot. v2.15.79 remains the accepted recovery release.
- m2-3-intelligence-deployed: stale placeholder assertion replaced with a Status filter check.

## 0.1.9 — 23 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.82**: Layer 4 review clarity and remembered filters (UI-5 batch 1), shared UI kit (UI-2), and the PERF-2 scoped search refresh fix.
- Layer 4: plain-English reason on every item, remembered status/field filters per reviewer with reset, plain status labels plus "All statuses", summarised automatic checks with technical detail behind a disclosure, queue limit raised from 100 to 250.
- Shared UI kit src/ui-kit.jsx: common components and one Pager (three copies removed, each screen keeps its look); useRememberedState generalises the Catalogue's saved state with the same storage key.
- PERF-2 (no screen change): admission refreshes only the courses it changes. v2.15.79 remains the accepted recovery release.

## 0.1.8 — 23 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.81** (PERF-1): Dashboard and layer-status summaries are pre-calculated every 2 minutes by a background job and served from a snapshot, with a live fallback if the snapshot is over 10 minutes old.
- Fixed intermittent Dashboard HTTP 500s caused by summary reads exceeding the 8-second statement limit.
- Open reviews and recent review activity now use Layer 4 review items instead of the retired, empty review queue.
- The Dashboard shows when its figures were last updated. v2.15.79 remains the accepted recovery release.

## 0.1.7 — 23 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.80**: first automated Layer 3 tuition admission, plain-English Layer 4 reasons and navigation clean-up (CF-247).
- Layer 3 validates Layer 2 tuition candidates on a schedule; confirmed fees are admitted to the catalogue, refresh the consumer projection and appear in search and the website API. The first run admitted fees with no wrong admissions.
- Added governed Layer 3 profile activation and pause (administrator only, reason required, append-only audit) and live Layer 3 queue status.
- Layer 4 reasons are plain English; admission holds now open a Layer 4 review; validated fees no longer open one.
- Navigation: Quality & Insights group; Review Queue retired with its address redirected to Layer 4; Dashboard review links fixed.
- Website API adds course and scholarship search. v2.15.79 remains the accepted recovery release until v2.15.80 is accepted.

## 0.1.6 — 14 Sep 2026

- Prepared visible PIM Admin release candidate **v2.15.79** for governed dispatcher tuning and recent-run decision metrics.
- Added Administration → Scraper Config dispatcher controls for batch size, run concurrency, stale recovery and paid-attempt limits while keeping vendor concurrency/rate/timeout/quota separate.
- Added sanitized comparable-run metrics for throughput, acquisition/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes, plus provider 24-hour performance.
- Added auditable tuning history with actor-bound governance reason and before/after policy; in-flight batches retain immutable policy snapshots.
- Retained the PR #84 transport safety cap of four ordinary items per invocation and two for scraper-first, with no change to Layer 1 identity, Layer 3 Evidence/model gating, Layer 4 authority or Search/Publication boundaries.

## 0.1.5 — 11 Sep 2026

- Published visible PIM Admin release **v2.15.78** for the accepted CF-093 governed Scheduled Tasks target-builder slice.
- Added server-authorised AU Course Facts Country/State/University preview and acquisition-only dispatch with exact-target preview receipts, profile/policy qualification and cross-operator idempotency.
- Retained v2.15.77 and earlier release history; generic Layer 3/Layer 4 orchestration, Evidence reprocessing and recurring scope construction remain separately gated.
- Reconciled the deployed-ranking UAT currentness assertion so it compares the deployed version against the maintained release-currentness source instead of the historical v2.15.74 literal.

## 0.1.4 — 11 Sep 2026

- Published visible PIM Admin release **v2.15.77** after CF-093 functional merge/deployed acceptance; retained v2.15.76 as canonical prior release history and left the separate target-builder/processing-mode/run-preview scope explicitly open.
- Began CF-093 Scheduled Workflow Orchestrator on top of the accepted v2.15.76 scheduler baseline.
- Added human-readable scheduled-task/source labels while retaining policy/source/profile UUIDs as secondary technical identifiers.
- Added task search across dataset, country, target, creator, owner and technical identifiers.
- Added per-user browser-local column visibility and ordering preferences with reset-to-default controls; UI preference state remains separate from governed execution policy.
- Added durable creator/action identity snapshots so historical scheduler attribution remains intelligible after a user is disabled or removed; browser task reads expose display attribution, not stored email snapshots.
- Added creator/owner status semantics for active, former, unassigned and system/legacy schedules without manufacturing a human creator for historical/system-created policies.
- Fixed Codex review findings so scheduler search treats `%` and `_` as literal operator text, profile identity stays visible when a source is also present, successful on-demand runs immediately refresh queue/Jobs panels, and independent supporting-read failures are surfaced without blocking policy search.
- Added request-generation sequencing to independent queue/context/Jobs panel refreshes so an older overlapping refresh cannot overwrite newer operational state.
- Aligned scheduler search with the humanised dataset labels presented by the UI, so values such as `course_facts` are searchable as `Course Facts` while preserving literal wildcard handling.
- Reconciled CF-093 migration history to deployed Pilot truth by retaining already-applied `20260910213556` and `20260910215546` identities and removing the duplicate later entity-label migration; no `--include-all` deployment bypass is used.
- Fixed the Codex-identified stale-search race by sequencing scheduler loads so superseded responses cannot replace newer policy/search results or clear/set busy/error state.
- Preserved rank-gated SECURITY INVOKER browser wrappers, exact bounded execution, Layer 3 Evidence/profile governance, Jobs/Evidence lineage and existing CF-092 schedule/run semantics.

## 0.1.3 — 10 Sep 2026

- Published visible PIM Admin release **v2.15.76** for the accepted Scheduled Tasks configuration and governed run-control change, while retaining v2.15.75 in canonical release history.
- Added a primary Scheduled Tasks workspace immediately before Evidence, with operator-friendly schedule columns, schedule editing, paged policy visibility, and direct Jobs/Evidence follow-through; removed the duplicate Scheduling entry from Administration.
- Added narrow authenticated scheduler action contracts. Public wrappers remain SECURITY INVOKER and delegate to independently rank-gated non-exposed security bridges.
- Direct Run on demand is limited to exact bounded Layer 1–2 policies and queues a `manual_governed` refresh request without changing recurring cadence or next-run time, while Layer 3 remains Evidence/profile/model-governed through its native workspace.
- Added durable scheduler action audit events recording operator, governance reason, before/after state, Change Control and associated refresh request; schedule edits also use optimistic concurrency to reject stale policy snapshots.
- Corrected whole-day PostgreSQL interval handling and browser-local `datetime-local` formatting, enforced cadence bounds, surfaced governed Jobs-read failures and avoided showing non-terminal jobs as completed.
- Browser Job reads remain on `public.admin_read`; historical Jobs are never replayed/reset by Scheduled Tasks.
- Reconciled canonical navigation UAT so acceptance follows the primary Scheduled Tasks route, current Layer 2 labels and no longer references the removed Administration Scheduling tab.

## 0.1.2 — 10 Sep 2026

- Preserved PIM Admin v2.15.75 inside the maintained `RELEASES` history rather than relying on the temporary currentness overlay.
- Synchronized the canonical `VERSION`, `UI_VERSION`, and HTML title at v2.15.75 so the Admin shell, release pill and retained release history report the same release.
- Added a regression contract for release-history persistence and cross-surface version synchronization.

## 0.1.1 — 10 Sep 2026

- Published PIM Admin v2.15.75 release-currentness metadata for the QS ranking corrective recovery.
- Added the QS ranking duplicate-edition cleanup and 2026/2027 acquisition correction to the release-notes pill under **Bug / UI fixes**.
- Recorded RLS remediation as pending security task #60 rather than changing access controls in the ranking bug-fix release.
