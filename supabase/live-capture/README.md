# Live capture

CF-247 production readiness review, phase 1 (10 Oct 2026; Platform Admin decision "Commit live as-is").

These files record database objects that existed only in the live Pilot project
(`fxcwkweaxjtknorudmwp`) with no source in git. They are **not migrations** and are never
applied: they are the exact live definitions, kept so git holds the code users run today.
They will be folded into the database baseline (production readiness phase 4).

| Folder | What | How captured |
|---|---|---|
| `functions/` | 22 website search functions (`website_v2_*`, `website_edge_course_search_v3_1`) | "Database function snapshot" workflow, run 38014304853 (`pg_get_functiondef`, carriage returns removed) |

`functions/MANIFEST.tsv` lists each function's schema, name, arguments and the md5 of its
definition. The md5 of each file equals the live `md5(replace(pg_get_functiondef(oid), E'\r', ''))`
at capture time. Grants and ownership are not included; the baseline will carry them.

The live `website-course-api` and `wix-course-api` edge function source was captured the same
day by the "Edge drift check" workflow (run 38014044472) and replaces the older copies under
`supabase/functions/`.
