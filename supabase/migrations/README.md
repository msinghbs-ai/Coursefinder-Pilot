# Migrations

New database changes go here, one file per change, as before.

A new project does not replay history: it starts from the baseline in
`supabase/live-capture/baseline/` (roles-apply.sql, then apply-preamble.sql + schema.sql +
apply-postscript.sql), proven by the "Database baseline rebuild test" workflow.
The 1,053 files that built the Pilot up to 10 Oct 2026 are kept in `supabase/migrations-archive/`.
