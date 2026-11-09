-- CF-247 AER selector fix fixture: the pieces of first-run verification (20261104460000) the measure needs, as live. The transition table is the
-- live table's columns this change reads or writes (key, chain, step, title, producer_jobs, next_key, switch_keys); its AER rows as live.
create table if not exists pipeline.progress_transitions (
  key text primary key, chain text not null, step int not null, title text not null, producer_jobs text[] not null default '{}',
  next_key text references pipeline.progress_transitions(key), switch_keys text[] not null default '{}', unique (chain, step));
insert into pipeline.progress_transitions(key, chain, step, title, producer_jobs, switch_keys) values
 ('aer_extraction', 'aer', 20, 'Extraction', '{aer-scheduled-read,entry-matrix-read}', '{}'),
 ('aer_completeness', 'aer', 30, 'Completeness validation', '{aer-scheduled-read}', '{}'),
 ('aer_technical_correction', 'aer', 40, 'Technical correction where needed', '{work-continuity}', '{}'),
 ('aer_layer4_review', 'aer', 50, 'Layer 4 review', '{}', '{}')
on conflict (key) do nothing;
update pipeline.progress_transitions set next_key = 'aer_layer4_review' where key = 'aer_technical_correction';
-- the row limit as live (entry.max_rows_per_course 6, set 28 Oct 2026 21:38 AEDT; entry.max_rows_by_provider [] set 2 Nov 06:43)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, used_by)
values ('pipeline', 'entry.max_rows_per_course', 'Course entry requirements: rows a course', 'number', '6'::jsonb, 1, 20, 'rows', 'security.course_entry_max_rows_v1')
on conflict (toolset_key, key) do nothing;
