# Lean AI Input Phase 1b-3 bundle: rolled-back rehearsal of 20261114091500

Approved by the Platform Admin 14 Nov 2026 17:20 (one PR, one rehearsal, one CI cycle). Rollback only; no worker called, no AI spend.

| Check | Result |
|---|---|
| Verdict | **PASS**, no failed assertion |
| Transaction | txid 17262484, forced `REHEARSAL_RESULT`; independent read: `txid_status` **aborted**, no table, no job, no settings |
| X1 migration text | `4057267638a6df08880a6dbe51df7c74` = md5 of the migration file without its final newline; file md5 `cef0eab41fd626efb172cc6f29d77e40` |
| S settings | 4 new pipeline settings; ships off (`reading.lean_qualify_on` 0); ceiling US$2 |
| C seed | fees 257 positives + 100 negatives; intakes 228 positives + 100 negatives |
| N off | nothing handed out and the fire does nothing while off |
| L on (in the transaction only) | 6 pages handed out with provider, course, URL, label and the pinned route (qwen/qwen3-30b-a3b-instruct-2507); fees carry the country profile and the one course |
| R record | both arms kept and their cost added (US$0.0011); a page out of time goes back to pending |
| K ceiling | with the run's cost at the ceiling, nothing more is handed out |
| Q report | criteria per field; admitted 0 |
| J/N | job `lean-qualify` scheduled and catalogued (+1 cron job); enrich items, fee queue, recall cases and AI invocations unchanged |

The first attempt stopped on a parenthesis error in the rehearsal's own check (`v->0 - 'gold'`) after every migration statement had run; it was fixed and re-run.
Files: `qualify-rehearsal.sql` (the exact statement run), `qualify-rehearsal-result.json`.
