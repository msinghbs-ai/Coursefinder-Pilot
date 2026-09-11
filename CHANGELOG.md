# Changelog

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
