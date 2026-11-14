# Lean AI Input Phase 1b step 1 — recall matcher fix: rolled-back rehearsal of 20261114051500

Approved by the Platform Admin 14 Nov 2026 13:25 (option A). Rollback only; no production change by this rehearsal.

| Check | Result |
|---|---|
| Verdict | **PASS**, no failed assertion |
| Transaction | txid 17191547, forced `REHEARSAL_RESULT` exception; independent read: `txid_status` = **aborted**, 0 run-b rows, 0 superseded rows, run a unchanged (720 done, 2,080 pending) |
| X1 migration text | `b18783b29d549acc8e2e71fed07ab58e` = md5 of the migration file plus one trailing newline (the substr window includes the newline before the end marker); file md5 `b94bd34ebaa9c925a3473e9079da82f8` |
| A1–A4 run a | 2,800 cases kept; the 720 done cases byte-identical (id, state, recall flags); the 2,080 unread cases closed `failed` with the superseded note; none left pending |
| B1–B2 run b | same 2,800 case keys as run a (field, source, reference md5 equal); all pending and held for the 10-minute release window |
| W1 | the worker leases nothing during the release window |
| Q1 | report picks run b; 0 AI calls |
| N1–N3 | settings, cron jobs, enrich rows and labelled rows unchanged |

Run b by field: entry requirements 800, duration 400, campus 400, delivery 400, intakes 400, fees 400.
Files: `run-b-rehearsal.sql` (the exact statement run), `run-b-rehearsal-result.json`.
