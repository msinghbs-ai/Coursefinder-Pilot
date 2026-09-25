# Changelog

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
