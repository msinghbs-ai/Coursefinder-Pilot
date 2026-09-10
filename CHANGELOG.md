# Changelog

## 0.1.3 — 10 Sep 2026

- Added a primary Scheduled Tasks workspace immediately before Evidence, with operator-friendly schedule columns, schedule editing, bounded Layer 1–3 due-now control, and direct Jobs/Evidence follow-through; removed the duplicate Scheduling entry from Administration.
- Reused the accepted `refresh_policy_upsert_v2` authority boundary for schedule edits and due-now requests; no new scheduler mutation RPC or generic historical retry/replay/reset was introduced.
- Added consolidated latest refresh-queue and recent Job result views while keeping browser Job reads on `public.admin_read`.
- Reconciled canonical navigation UAT so acceptance follows the primary Scheduled Tasks route and no longer references the removed Administration Scheduling tab.

## 0.1.2 — 10 Sep 2026

- Preserved PIM Admin v2.15.75 inside the maintained `RELEASES` history rather than relying on the temporary currentness overlay.
- Synchronized the canonical `VERSION`, `UI_VERSION`, and HTML title at v2.15.75 so the Admin shell, release pill and retained release history report the same release.
- Added a regression contract for release-history persistence and cross-surface version synchronization.

## 0.1.1 — 10 Sep 2026

- Published PIM Admin v2.15.75 release-currentness metadata for the QS ranking corrective recovery.
- Added the QS ranking duplicate-edition cleanup and 2026/2027 acquisition correction to the release-notes pill under **Bug / UI fixes**.
- Recorded RLS remediation as pending security task #60 rather than changing access controls in the ranking bug-fix release.
