# Production migration history in the repository

Production keeps every applied migration in `supabase_migrations.schema_migrations` (2,194 versions on 19 Nov 2026). The repository holds
the text of each one:

- `supabase/migrations/` (new changes), `supabase/migrations-archive/` and `supabase/held/` already hold 1,019 of them, under the same
  version and with the same text;
- `applied/` holds the rest, exactly as production applied them (statements joined by a newline): 1,022 versions that never had a file of
  that version (most were applied straight to the database in August and September 2026), and 153 whose file in `migrations-archive/`
  differs from what was applied (the file is kept as it is; `applied/` has what ran).

`MANIFEST.tsv` lists every history version with the file that holds its text, the text md5 (carriage returns and trailing newlines ignored)
and its status, plus the 736 repository files that have no history version (474 history texts match one of them under another version).

Nothing here is applied: Deploy on merge applies only `supabase/migrations/`, and a new project starts from the baseline in
`supabase/live-capture/baseline/`. To bring this folder up to date, run the workflow "Migration history sync (read only)" (it reads
production with read-only queries, refuses texts that look like they hold a key or password, and pushes a branch `db-history-sync/<run>`),
then open a PR from that branch. Guarded by `tests/uat/cf-247-s782-migration-history-sync-contract.spec.mjs`.

First sync: run 44522515754, 19 Nov 2026 23:22 AEDT, history head `20261119182000`.
