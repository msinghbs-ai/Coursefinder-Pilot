# Production-parity capture tool

Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026). Release validation uses production-representative constraints, grants, RLS, triggers and function signatures.

The intake releases passed simplified fixtures, and then production rejected the operation. The fixtures had no `admin_jobs_outcome_fkey` and no `manual_locks` mode check or primary key. This tool reads those shapes from production read-only and rebuilds them locally. It also proves that a fixture still matches production.

Owner: agent E (independent validation). Files: `scripts/prod-parity-capture.mjs`, `tests/fixtures/prod-parity/`.

## How it works

Agents cannot connect to production directly. They can only use `mcp__Supabase__execute_sql` on `fxcwkweaxjtknorudmwp`. So the tool never connects: it prints read-only SQL, and you run that SQL through the MCP tool.

| Step | Command | What it does |
|---|---|---|
| 1 | `node scripts/prod-parity-capture.mjs capture-sql --tables pipeline.admin_jobs,pipeline.manual_locks --functions 'security.f(uuid);security.g' --lookups pipeline.ops_outcome_codes` | Prints one `SELECT` built from `capture.sql`. Run it through `mcp__Supabase__execute_sql`. It is a light catalogue read: avoid minutes :35–:42 and :47–:48 Sydney time. |
| 2 | `node scripts/prod-parity-capture.mjs save output.txt manifests/<name>.json --source "..."` | Saves the tool output: MCP text, rows or the bare manifest. Every function definition must equal its captured md5, so a transcription error is refused. |
| 3 | `node scripts/prod-parity-capture.mjs check-sql manifests/<name>.json` | Prints one read-only `SELECT` that recomputes the facts and lists every difference. No rows means parity. Run it through the MCP tool against production. No rows proves the saved manifest is exact and still current. |
| 4 | `node scripts/prod-parity-capture.mjs fixture manifests/<name>.json \| psql -d e_x` | Builds the fixture in an isolated local database. It refuses a non-local server and a Supabase database. |
| 5 | `node scripts/prod-parity-capture.mjs check-sql ... \| psql -d <fixture db>` | Shows how far a fixture, yours or someone else's, is from production. |
| – | `subset <manifest> --tables a.b` | Keeps only part of a manifest. Use it to check a fixture that holds only some of the tables. |
| – | `diff a.json b.json` | Compares the facts of two manifests. |

## What a manifest holds

- **Tables.** For each target table: columns and types, defaults, identity and generated columns, primary, unique, check, foreign-key and exclusion constraints, other indexes, triggers (definition and enabled state), RLS enable and force, policies, and table grants.
- **Referenced tables.** Every table a foreign key points to. Only its key columns and its primary and unique keys are captured. No rows.
- **Lookup tables.** Only the tables you name. Their code rows are copied, so a foreign key to them behaves as in production. A lookup is refused if a column looks like personal data (`email`, `phone`, `*_by`, `user_id`, `actor`, `contact`, and similar names), or if it has more than `--max-lookup-rows` rows (500 by default). `auth`, `storage`, `vault` and `realtime` tables are never lookups.
- **Functions.** The named functions, every trigger function, and every function that a target table's trigger `WHEN` clause, default, check or policy calls. Each has its `md5(pg_get_functiondef)`, its definition and its EXECUTE grantees.
- **Other objects.** Enum and domain types used by the columns, USAGE on the schemas involved, and the `statement_timeout`, `lock_timeout` and idle time-out of `anon`, `authenticated`, `authenticator` and `service_role`.
- **Search path.** The session `search_path`. `pg_get_functiondef` and `format_type` print names relative to it, so the fixture sets the same path on its database. Production prints `"\$user", public, extensions`.

## Checks

- `tests/uat/cf-247-s310-prod-parity-tool-contract.spec.mjs` is the source contract, run in the default suite. It checks that the capture and check queries are single read-only `SELECT`s, the refusals, the committed manifest, the fixture's order and content, and subsets.
- `tests/fixtures/prod-parity/run.sh` is the database round trip. It is run by `.github/workflows/prod-parity.yml` on PostgreSQL 17.6. Locally, run `PGUSER=postgres PGHOST=/tmp bash tests/fixtures/prod-parity/run.sh`. Its databases use the prefix `e_pp_`.
  1. It captures from a local stand-in (`sample-source.sql`), builds the fixture and requires zero differences, with the check inside a `READ ONLY` transaction.
  2. It requires the outcome foreign key, the lock mode check, the composite key, RLS and grants to refuse what production refuses.
  3. It requires a simplified fixture to be caught fact by fact, and a personal-data lookup to be refused.
  4. For every committed production manifest, it rebuilds the fixture and re-checks it. For the intake-lessons manifest, it requires that `admin_jobs.outcome = 'run_now_queued'` and `manual_locks.mode = 'hold'` are rejected, as they were in production.

## Committed manifests

| File | Captured | Scope |
|---|---|---|
| `manifests/intake-lessons-admin-jobs-manual-locks.json` | 5 Nov 2026 19:28 AEDT, production (PostgreSQL 17.6), read only | Tables: `pipeline.admin_jobs`, `pipeline.manual_locks`, `pipeline.progress_transitions`. Lookups: `pipeline.ops_outcome_codes` (8 codes), `pipeline.admin_job_kinds` (16 kinds). Referenced: `pipeline.integration_issues`. Functions: `security.ops_guard_refuse_v1()` and `security.ops_remedy_guard_active_v1()`. |

## Limits

- Ownership is not reproduced. Local objects belong to the user who runs the fixture, and the owner's own privileges are left out on both sides.
- Column-level grants and default privileges are not captured.
- `MAINTAIN` (PostgreSQL 17) cannot be granted on PostgreSQL 16. The fixture warns about it and the check lists it. CI runs 17.6.
- Role-wide settings made by other databases on a shared local server can appear in `role|…` facts. A manifest can list such lines in `local_allowed_differences`.
- Function bodies are created with `check_function_bodies = off`. A body that needs objects outside the scope is created, but fails when it is called. Add the objects it needs to the scope.
