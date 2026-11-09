-- Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): captures what the five functions answer BEFORE migration 20261110020000 (the live text), on the seeded scheduler history and intake events.
create schema if not exists ols;
drop table if exists ols.old_out;
create table ols.old_out(k text primary key, j jsonb not null);
-- the answers that are compared: the cache-derived job fields and the time-derived next run are set aside (the first changes only within the cache's age, the second with the minute)
create or replace function ols.norm_lane(j jsonb) returns jsonb language sql stable as $$
  select (j - 'at' - 'job_history') || jsonb_build_object('lanes', (select coalesce(jsonb_agg(l || jsonb_build_object('jobs', (select coalesce(jsonb_agg(x - 'next_run' - 'history_known' order by x->>'job'), '[]'::jsonb) from jsonb_array_elements(l->'jobs') x)) order by l->>'lane'), '[]'::jsonb)
                                                       from jsonb_array_elements(j->'lanes') l))
$$;
create or replace function ols.norm_rec(j jsonb) returns jsonb language sql stable as $$
  select (j - 'measured_at' - 'window_since' - 'jobs') || jsonb_build_object('jobs', (select coalesce(jsonb_agg(x order by x->>'job'), '[]'::jsonb) from jsonb_array_elements(j->'jobs') x))
$$;
insert into ols.old_out values ('lane', security.lane_funnel_v1(null)), ('lane_int', security.lane_funnel_v1('int')), ('rep', security.intake_progress_repeats_v1()), ('rec', security.process_results_recovery_v1());
