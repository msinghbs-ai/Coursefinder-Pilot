# Changelog

## 0.1.3 — 10 Sep 2026

- Added a primary Scheduled Tasks workspace immediately before Evidence, with operator-friendly schedule columns, schedule editing, bounded Layer 1–3 run-on-demand control, and direct Jobs/Evidence follow-through; removed the duplicate Scheduling entry from Administration.
- Added narrow authenticated scheduler action contracts for schedule edits and run-on-demand. Public wrappers remain SECURITY INVOKER and delegate to independently rank-gated non-exposed security bridges.
- Run-on-demand now queues an exact bounded `manual_governed` refresh request without changing the recurring cadence or next-run timestamp, prevents duplicate active requests, and never replays/resets historical Jobs.
- Added durable scheduler action audit events recording operator, governance reason, before/after state, Change Control and associated refresh request while keeping browser Job reads on `public.admin_read`.
- Corrected whole-day cadence handling for PostgreSQL time-only interval representations and browser-local `datetime-local` formatting so schedule edits do not erase hour-derived cadences or shift timestamps by the operator timezone.
- Reconciled canonical navigation UAT so acceptance follows the primary Scheduled Tasks route and no longer references the removed Administration Scheduling tab.

## 0.1.2 — 10 Sep 2026

- Preserved PIM Admin v2.15.75 inside the maintained `RELEASES` history rather than relying on the temporary currentness overlay.
- Synchronized the canonical `VERSION`, `UI_VERSION`, and HTML title at v2.15.75 so the Admin shell, release pill and retained release history report the same release.
- Added a regression contract for release-history persistence and cross-surface version synchronization.

## 0.1.1 — 10 Sep 2026

- Published PIM Admin v2.15.75 release-currentness metadata for the QS ranking corrective recovery.
- Added the QS ranking duplicate-edition cleanup and 2026/2027 acquisition correction to the release-notes pill under **Bug / UI fixes**.
- Recorded RLS remediation as pending security task #60 rather than changing access controls in the ranking bug-fix release.
