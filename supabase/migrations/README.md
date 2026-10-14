# Migrations

New database changes go here, one file per change, as before.

A new project does not replay history: it starts from the baseline in
`supabase/live-capture/baseline/` (roles-apply.sql, then apply-preamble.sql + schema.sql +
apply-postscript.sql), proven by the "Database baseline rebuild test" workflow.
The 1,062 files that built the Pilot up to 10 Oct 2026 are kept in `supabase/migrations-archive/` (1,053 at capture, plus the nine website API v2 files of 8 Oct 2026, applied live before the baseline and added on 14 Oct; their objects were already in the baseline).
