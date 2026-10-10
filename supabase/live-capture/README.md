# Live capture

CF-247 production readiness review, phase 1 (10 Oct 2026; Platform Admin decision "Commit live as-is").

These files record database objects that existed only in the live Pilot project
(`fxcwkweaxjtknorudmwp`) with no source in git. They are **not migrations** and are never
applied: they are the exact live definitions, kept so git holds the code users run today.
They will be folded into the database baseline (production readiness phase 4).

| Folder | What | How captured |
|---|---|---|
| `baseline/` | Full live schema (no row data): `roles.sql` (role settings) and `schema.sql` (17 schemas, 400 tables, 1,257 functions, policies, grants, triggers) | "Database schema dump" workflow, run 38015733264 (`supabase db dump`); md5 values in `baseline/MD5SUMS` |
| `functions/` | 22 website search functions (`website_v2_*`, `website_edge_course_search_v3_1`) | "Database function snapshot" workflow, run 38014304853 (`pg_get_functiondef`, carriage returns removed) |

`functions/MANIFEST.tsv` lists each function's schema, name, arguments and the md5 of its
definition. The md5 of each file equals the live `md5(replace(pg_get_functiondef(oid), E'\r', ''))`
at capture time. Grants and ownership are not included; the baseline will carry them.

The live `website-course-api` and `wix-course-api` edge function source was captured the same
day by the "Edge drift check" workflow (run 38014044472) and replaces the older copies under
`supabase/functions/`.

## Baseline (phase 4)

`baseline/` is the starting point for any new project (Platform Admin decisions "Baseline from live",
"Dump + test project", "Move to archive folder"). It is proven by the "Database baseline rebuild
test" workflow, which builds an empty project named `coursefinder-baseline-test` from it and
compares the result with the Pilot. Not in the baseline (handled separately before Production):
row data, including reference and configuration tables; the 94 `cron.job` schedules; storage
buckets; edge function secrets; Auth settings.

`baseline/roles-apply.sql` is `roles.sql` without one line,
`GRANT SET ON PARAMETER "log_min_messages" TO "supabase_realtime_admin";`. That grant is
managed by Supabase itself and a project owner cannot issue it (rebuild run 38027911726 stopped
on it with "permission denied for parameter log_min_messages"). The role timeouts (anon 3s,
authenticated 8s, authenticator 8s) are kept. `roles.sql` stays exactly as captured.

`baseline/apply-preamble.sql` runs immediately before `schema.sql` on a new project. A new
Supabase project grants anon, authenticated and service_role everything on new objects in
`public` (default privileges); a schema dump writes each object's grants but never revokes those
defaults. Without the preamble, rebuild run 38028086660 let anon run 640 functions and read
10 tables that the Pilot does not expose, and gave authenticated functions the Pilot keeps to
service_role. The preamble removes the defaults while objects are created; the closing
`ALTER DEFAULT PRIVILEGES` lines of `schema.sql` put the Pilot's defaults back.
