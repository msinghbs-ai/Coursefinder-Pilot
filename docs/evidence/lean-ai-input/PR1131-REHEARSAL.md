# PR #1131: rolled-back migration rehearsal on Pilot (14 Nov 2026)

**Verdict: PASS.** All assertions passed and no failures were listed. The transaction aborted, and an independent check confirms nothing persisted.

| | |
|---|---|
| Approval | Platform Admin, 14 Nov 2026 10:42 AEDT. The approval covered the rollback rehearsal only. It is not approval to deploy. |
| Project | Pilot `fxcwkweaxjtknorudmwp` |
| PR head | `c60a316bb1251b1c2d22610b1f6db449a8e588fd` |
| Migration | `20261113400000_cf247_lean_ai_input_observations.sql`, md5 `df7a7055cfc8ab2940ab74eaf49614d8` |
| Script | [`pr1131-rehearsal.sql`](pr1131-rehearsal.sql), md5 `31622f7b4247a35f18ac081cbdefc675`, run verbatim through the Supabase connector after its approval prompt was approved |
| Raw result | [`pr1131-rehearsal-result.json`](pr1131-rehearsal-result.json) |
| Ran | Transaction start 2026-11-13 23:46:16 UTC (10:46 AEDT 14 Nov), txid 17137876 |

## How the script works

1. `BEGIN ISOLATION LEVEL REPEATABLE READ`.
2. Take a snapshot of the starting state into a temp table that is dropped at commit:
   - settings count, plus an md5 of every other setting;
   - `field_enrich_items` row count, plus an md5 of the last 5,000 rows (id, state, updated);
   - the number of tables in the `pipeline` schema.
3. Apply the **exact migration**.
4. Apply the **same file again**, to test that re-running it is harmless.
5. A `DO` block asserts every check and always ends in `RAISE EXCEPTION`. Nothing can commit.

## Checks

| ID | Check | Result |
|---|---|---|
| X1 | The executed migration text is byte-identical to the PR file. Proven with `md5(substr(current_query()))` = `df7a7055…` | PASS |
| S1–S5 | 26 columns; 4 indexes (primary key plus 3); RLS on; purpose comment; no policies, so only the definer functions reach the table | PASS |
| P1–P3 | `svc_ai_input_observe_v1`: anon and authenticated cannot execute; service_role can. The report cannot be executed by anon or authenticated. Table SELECT is denied to anon and authenticated. Both functions are `SECURITY DEFINER` with `search_path=""` | PASS |
| P4 | A call as role `authenticated` is refused: "permission denied for function svc_ai_input_observe_v1" | PASS |
| G1 | The 3 settings are present with label, range, unit and used_by: `input_observe_on` 1 (0–1), `retention_days` 30 (7–365), `purge_batch` 2000 (100–20000) | PASS |
| I1–I3 | After two applies: exactly 3 settings added, exactly 1 table added, no other setting changed | PASS |
| W1 | 4 rows sent, 2 kept: one row without `read` and one without `contract` were rejected | PASS |
| W2–W4 | An invalid preflight value is stored as null. An invalid UUID is stored as null. The worker string is capped at 60 characters | PASS |
| W5–W7 | `[]`, `{}` and `null` input each return `kept 0` without raising | PASS |
| W8 | A non-numeric count raises "invalid input syntax for type integer". This is expected: the worker catches it (`.catch`), so a failure to record never fails a read | Recorded |
| R1–R3 | Bounded retention: with the batch set to 2 (inside the transaction only), 3 expired rows are removed as 2 then 1. Fresh rows are kept | PASS |
| Q1 | The report gives the expected figures: deadline reads 2, cut 1, signal only beyond the cut 1, no-signal-but-filled 1, repeated fingerprints 1 | PASS |
| N1–N2 | `field_enrich_items` count and the last 5,000 rows are unchanged, so no reader or canonical data was touched | PASS |
| D | Function definition md5 inside the transaction: observe `3f6d4ed98c8055bdbd18adae4e09edf0`, report `e23e4bd5ceb9f254f7887a3f7bb67f3e`. **These are the expected values for the post-deploy checksum check** | Recorded |

## Independent check that nothing persisted (separate query, 23:46:29 UTC)

| Item | Before (23:43:14) | After | |
|---|---|---|---|
| `pipeline.ai_input_observations` | absent | absent | ✓ |
| `svc_ai_input_observe_v1`, `ai_input_observation_report_v1` | absent | absent (0 by name) | ✓ |
| `reading.input_observ*` settings | 0 | 0 | ✓ |
| Settings total / md5 of all settings | 1,417 / `1d999f1c…` | 1,417 / `1d999f1c…` | ✓ |
| `pipeline` tables | 525 | 525 | ✓ |
| public + security functions | 2,481 | 2,481 | ✓ |
| Temp table `_rh_pre` | — | 0 | ✓ |
| Admin control events naming the settings | — | 0 | ✓ |
| `txid_status(17137876)` | — | **aborted** | ✓ |

## No external or non-transactional side effects

- The rehearsal calls no HTTP, `pg_net`, Storage, Firecrawl, OpenRouter or edge function.
- `pg_net` showed 8 responses after 23:45 UTC. All were created at 23:45:30 and 23:46:00, **before** the rehearsal transaction began at 23:46:16, so they belong to scheduled work.
- The schema-change event triggers only `NOTIFY pgrst`, and `NOTIFY` is delivered only on commit.
- The other event triggers grant access on extension creation; no extension was created.
- The settings trigger `ops_guard_settings` only guards remedy runs, and it raised nothing.
- Identity-sequence values belong to a table that was created and rolled back.
- No paid AI or Firecrawl call was made.

## Residual items, not covered by a single transaction

- **Concurrent writers:** covered by CI database fixtures and the post-deploy check.
- **The live worker path (v0.87.0):** checked after deployment, on the next legitimately authorised Enrich-fields run. No paid run is started for this check.
