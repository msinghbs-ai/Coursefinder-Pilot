# Lean AI Input Phase 1b step 2 bundle: rolled-back rehearsal of 20261114071500

Bundle approved for one rehearsal and one CI cycle by the Platform Admin, 14 Nov 2026 14:32. Rollback only; no production change by this rehearsal.

| Check | Result |
|---|---|
| Verdict | **PASS**, no failed assertion |
| Transaction | txid 17223165, forced `REHEARSAL_RESULT`; independent read: `txid_status` **aborted**; insert md5 still `3f6d4ed9…`, 0 `sel_*` columns, 0 run c rows, batch still 120, report function absent |
| X1 migration text | `b37c27e01117d96e42987b56212b130d` = md5 of the migration file without its final newline (window ends before the newline that precedes the end marker); file md5 `00c18a785800b1fbed324d51ab5b259a` |
| G1 guard | live `public.svc_ai_input_observe_v1` was `3f6d4ed98c8055bdbd18adae4e09edf0` (as written against); after: `d191e1915b62541536b0e162da07c705` |
| S1–S4 settings | 5 new pipeline settings, each with label, range, unit and used_by; `batch.lean_sections_eval` 120 → 40; every other setting unchanged |
| O1–O3 insert | a v0.92.0 row with its shadow kept whole; a v0.91.0 row without one kept with nulls; a skipped-size row kept; a bad row skipped (kept 3) |
| Q1 report | `security.ai_input_selection_report_v1` returns the entry row (4,000 of 30,000 characters, 0 signal lost) and the campus skipped-size row |
| C1–C4 run c | the same 2,800 case keys as run b, pending and held 10 minutes; run b unchanged; the worker leases nothing in the window |
| N1–N2 | cron jobs and enrich items unchanged |

Files: `step2-rehearsal.sql` (the exact statement run), `step2-rehearsal-result.json`.
