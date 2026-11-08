# AER reader revision 1 to 2: prepared, NOT applied (lane aer2, 8 Nov 2026)

Nothing in this file has been applied. It is the prepared change, the evidence behind it and the checks for the Integration Controller. It is a Settings change by a
signed-in Platform Admin (`public.admin_toolsets_write('setting', ...)` needs `auth.uid()` and role rank 6, writes before, after and the reason to
`pipeline.admin_control_events`), so it is not a SQL paste. It is also not a migration: a migration would switch it on at deploy.

## The change

Settings › Pipeline settings › Layer 4 › "Layer 4: entry reader revision" (`layer4.reader_revision`, toolset `pipeline`, range 1 to 100000): **1 to 2**.
Suggested reason: `CF-247 AER: worker v0.59.11 reader behaviours switched on (course quote fragments, country aliases, minimum kept without its number); refused reads on an unchanged page may be asked again`.

## What the setting does (code: `security.layer4_reread_repeat_v1`, `security.aer_recovery_rule_v1`)

A corrected read the reader refused on an unchanged stored copy is a deterministic repeat, class `unchanged_evidence`, and is not offered again until the stored copy,
this revision, or a setting named in `layer4.reread_change_keys` (`entry.%` and `layer4.reader_revision`) changes. Raising it tells the platform "the reader changed".

## Evidence, read only, 8 Nov 2026 about 03:10 to 03:30 UTC (re-measure before acting)

| Measure | Value |
|---|---|
| Waiting course reads by recovery class | ready 197, row_limit 151, changed_conditions 98, human_assisted 54, stale 26, decision 24, reread_eligible 9, transient 5 (564) |
| Waiting course reads that are a deterministic repeat (`layer4_reread_repeat_v1.repeat = true`) | **0** |
| Waiting course reads in class `unchanged_evidence` | **0** |
| Reads with an ellipsis-joined `quote_not_on_page` drop (the fix `reading.course_quote_fragments_on` can only help these) | 113 drops in 81 waiting reads |
| ... of which that item's only `quote_not_on_page` drops are ellipsis-joined | 45 reads |
| ... by recovery class (items with an ellipsis drop) | row_limit 22, changed_conditions 32, human_assisted 13, stale 5, reread_eligible 1, ready 4, transient 2, decision 2 |
| Corrected reads asked since 5 Nov | none; 94 of the 98 `changed_conditions` reads are inside the 14-day retry wait (`aer.schedule_held_retry_days`, last request 3 to 5 Nov, so eligible again 17 to 19 Nov), 4 have used both tries (`aer.schedule_held_max_tries`) |

## Finding: raising the revision now releases nothing

No waiting read is a deterministic repeat, so a bump changes no class today. The 98 reads already count as `changed_conditions` (an `entry.%` setting changed since their
refusal); they are held only by the retry wait. The revision matters from the first read made with the new reader: a refusal after the switch-on is judged against it.
Raise it **when the three reader switches are on**, not before, so the platform does not read the same pages again under an unchanged reader.

## Order the Controller can follow

1. Confirm the worker is v0.59.11 on the live `coverage-sweep` (edge function version 243, updated 8 Nov 2026 01:09 UTC, matches PR #908 merge 12:08 AEDT).
2. Switch on `reading.course_quote_fragments_on`, `reading.entry_country_aliases_on`, `reading.entry_value_null_on` (Platform Admin or Controller, each with a reason).
3. Raise `layer4.reader_revision` to 2 with the reason above.
4. To let the 94 reads inside the retry wait be read with the new reader before 17 to 19 Nov, lower `aer.schedule_held_retry_days` (now 14) for a day, then set it back. Cost: one AI read each,
   `entry.course_read_cost_usd` 0.005 USD a course (94 reads about 0.47 USD, no Firecrawl). The hourly cap (`batch.aer_schedule_held` 10) makes it about 10 hours.
   This is a Platform Admin decision; this file does not make it.

## Checks after step 3 (SELECT only)

```sql
select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'layer4.reader_revision';          -- expect 2
select (security.aer_recovery_rule_v1(i.id))->>'class' cls, count(*) from pipeline.layer4_review_items i
 where i.status = 'pending' and i.field_code = 'course_entry_first_read' group by 1 order by 2 desc;                              -- classes unchanged today
select e.action, e.detail from pipeline.admin_control_events e where e.detail::text like '%reader_revision%' order by e.created_at desc limit 3;  -- the audited change
```

Rollback: set it back to 1 (a change of the setting is itself a "reader change" for items refused in between; nothing else depends on the number).
