# PR #1136: rolled-back rehearsal on Pilot (final: 14 Nov 2026, 12:30 AEDT)

**Verdict: PASS.** No assertion failed. The transaction was aborted (txid 17172230), and an independent read confirms nothing persisted.

**This is the final run on the final head.** #1137 took worker v0.88.0 on main, so #1136 was rebased and renumbered:
- worker **v0.89.0**;
- migration renamed to **`20261114031500`** (after #1137's `20261114011500` and `…021500`);
- the migration text changed only in the worker version and the register's `introduced_in`.

The earlier run of 11:58 AEDT on the `20261114010000` text (md5 `d45d9e6e…`, txid 17161597) also passed and also aborted. It is superseded by this run.

**Reconciled with #1137:** the selector now uses #1137's `[B#]` blocks (`aerV3Blocks`, `AER_V3_INPUT` "lean-blocks-v1") and has no block format of its own. The migration text did not change for this.

- **Migration:** `20261114031500_cf247_lean_sections_eval.sql`, md5 `3ed1b03e2ba4c964ee0053c5084be8e8`. Inside the transaction, `md5(substr(current_query()))` proves the executed text is byte-identical to the PR file.
- **Script:** [`lean-sections-rehearsal.sql`](lean-sections-rehearsal.sql). **Raw result:** [`lean-sections-rehearsal-result.json`](lean-sections-rehearsal-result.json).
- **First attempt:** at 11:56 AEDT it stopped on an ambiguous column alias in the check block, after every migration statement had already succeeded. That transaction aborted and nothing persisted. The alias was fixed and the script run again.

| Check | Result |
|---|---|
| Seeded cases | 2,800: 400 each for `aer_accepted:entry_requirements` and adapter `campus`, `delivery`, `duration`, `entry_requirements`, `fees`, `intakes`. Every label comes from a person or a tested adapter |
| Settings | Exactly 3 added. Job `lean-sections-eval` is scheduled with a command that contains no number, and it is catalogued |
| ACL | `next`, `record`, `seed` and `report`, and the table itself, are denied to authenticated users and anon. `next` is allowed for service_role |
| Re-seed | Running the same seed again adds 0 rows |
| Lease, record | Lease 3; record 2 (one done, one failed, unknown case ignored); a done case is never overwritten |
| Report | Computed; `ai_calls` 0 |
| Switch off | The fire sends nothing and the lease hands over nothing |
| Regression | `field_enrich_items` and the AER labels unchanged; exactly one cron job added |

**Independent reads afterwards:**
- **12:38:35 AEDT, for the final run:** table absent, 0 functions, 0 `lean_sections_eval` settings, no cron, catalogue or register rows. `txid_status(17172230)` = aborted. The settings total was 1,422; it moved from 1,420 between the two runs because of #1137's own deploy, and none of the new settings are this PR's.
- **11:58:52, for the earlier run:** all the same, with a total of 1,420 and `txid_status(17161597)` = aborted.
