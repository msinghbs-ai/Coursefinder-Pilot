# English requirements: faculty and course-group rules, provider scope, "why no rule"

CF-247, Platform Admin direction of 6 Nov 2026 09:44 (section 3 and the permanent compatibility gate, section 4). Migration `20261106550000_cf247_english_requirements_complete.sql`,
coverage-sweep Worker v0.59.10 (after course descriptions v0.59.9) (parser `provider-policy-v0.3.0`). Plan: admin repo `docs/platform/work-packages/2026-11-06-english-requirements-implementation-plan.md`.

## What it does

A university that publishes English scores by faculty or course group (UNSW) has no single default, so the parser used to decline the table and 658 UNSW courses had no English.
Parser v0.3.0 now returns each faculty or group row as a group. A reading with groups is filed as `proposed`, never approved automatically. A Platform Admin approves it and binds each group
to courses by field of education (ASCED) and/or a title pattern. The existing plan then writes the group's score only to courses that have no reading of their own.

## Reuses

- The whole existing route: `central-find`, `central-attach`, `central-ai`, `provider-facts`, `policy-auto-approve`, `provider-english-defaults`, `policy-add-tests`; `pipeline.provider_policy_proposals`, `provider_fact_sources`.
- Admission through `security.coverage_apply_course_v1` into `catalogue.course_english_requirements` (unique key `course_id, english_test_id`; a withdrawn row is reused).
- The English policies screen (Coverage > Attributes), `admin_provider_policies_read`, `admin_provider_policy_decide`, `admin_automation_control` (Run now), `admin_control_events` (log).
- Settings in `pipeline.platform_toolset_settings` (G2), job catalogue (G1).

## Changes

- `policy.ts` v0.3.0: `groups` for faculty and course-group tables (defaults, exceptions, caveats, signals unchanged; compat test against v0.2.5 outputs).
- `svc_provider_policy_record`: a group reading is `proposed`; a re-read by the same parser keeps a person's bindings.
- `policy_auto_approve_v1`: never approves or closes a group reading (D2). `admin_provider_policy_decide`: approving closes only waiting readings of the same family.
- `provider_english_plan_v1` / `provider_english_apply_v1`: new plan `group` after the held cases and before the default; ambiguity (two groups, different scores) is held.
- New: `admin_provider_english_groups_set_v1` (Platform Admin, reason mandatory, logged), `admin_provider_english_status_read` (stage, pages tried, why, next try, jobs, spend), `svc_provider_policy_reparse_next`, `english_provider_in_scope_v1`, `english_group_match_v1`.
- Settings: `central.english_provider_types` (`["*"]`, D1), `batch.policy_reparse` (20, D5), `central.english_search_non_university` (0, D3), `batch.english_search_non_university` (10).
- `policy-add-tests` gains `reparse_limit` (one more argument; no new job). Screen: course-group binding editor, group counts, "No rule yet".

## Replaces

Nine functions are replaced in place with the old behaviour kept, each guarded on its live md5 (listed in the migration, section 0). Nothing else.

## Retires

Nothing. The older `svc_english_table_*` functions and fee-schedule-etl English modes are not touched (separate housekeeping item).

## Conflicts handled

- Course's own page reading, named courses, held cases (research, double degree, exit award), manual locks, in-review and waiting rows always win over a group.
- Decision 262 (one policy in force per university and level): another approved policy of the same provider that names or groups a course keeps it; this policy's default does not take it.
- Group rows are keyed `policy:<proposal>:<test>`; the add-tests job ignores them. A binding change withdraws (keeps) rows no longer reached.
- D3: the non-university search ships OFF; while 0 nothing is queued, searched or spent. D6: VET-level English is not added.

## Protects

- Consumer API (G3): untouched. Rows go only into `course_english_requirements`, the table the website and Zoho already read; no function, column or edge function of the consumer API is named or changed.
- No drops or deletes. No new scheduler. No automatic activation.

## Validates

`tests/fixtures/english-requirements/run.sh` executes the production-parity fixture, its function-hash checks and the migration, then requires all 71 group/scope/search/reparse/status assertions and all 17 named-exception/own-reading/manual-lock assertions to emit their actual Postgres PASS notices. Producer, fixture, parity SQL and scenario errors stop the run; a green shell pipeline alone is not evidence.

The six governed verbatim stored pages are now present under `tests/fixtures/english-requirements/pages/`. Their hashes and real UNSW faculty/exception parsing are checked by `cf-247-english-verbatim-pages-contract`; missing or altered evidence still fails. Do not repeat the source inspection merely because an older PR description says the pages are absent.

CI uses PostgreSQL 17.6 with a Unix socket shared only between the isolated job and service containers. The generated local-only and Supabase-project refusal guards remain unchanged. The workflow propagates SQL failures through `tee`; the baseline contract also injects producer/SQL errors into the real shell entry point and requires failure before any parity PASS.

Existing specs `cf-247-english-baseline-contract`, `cf-247-english-groups-contract`, `cf-247-english-verbatim-pages-contract`, and the central governance specs s32, s42, s57, s120 remain applicable. Actual run IDs and results belong in the canonical Admin checkpoint; scenario definitions alone do not establish that they executed.


## Integration recovery, 6 November 2026

False-green execution fixed at `9b54c741`: genuine isolated PostgreSQL17.6 over Unix socket, no parity differences, live function md5 guards, migration applied and **71/71 group +17/17 exception scenarios** passed in run [42209417333](https://github.com/msinghbs-ai/Coursefinder-Pilot/actions/runs/42209417333).

This branch now incorporates repaired #894 head `12216778` as an explicit development dependency. A real three-way Worker merge retained both the strict one-reask path and stored English reparse; only the Worker version/comment line conflicted. English uses unique worker **v0.59.10**; #894 remains **v0.59.9**. The course-description currentness assertion is updated to this combined worker version. The full governed suite will validate the combined tree. No production merge, release, admission or paid search is implied. Human group approval/binding and review-first descriptions remain in force. Release #894 before this dependent English capability, subject to ownership and all documented gates.
