-- CF-247 s710: scholarship round states are decided on the Melbourne date and refreshed by rollup-scheduler (S2-Build; Platform Admin
-- 18 Nov 2026 17:55 and 21:58: "Melbourne-date Australia/Melbourne scholarship status refresh on rollup-scheduler if not already covered").
--
-- What was read live (19 Nov 2026 03:45 AEDT): security.scholarship_round_state_refresh_v1 compares the close and open dates with
-- current_date, which is the UTC date (from 11:00 AEDT the previous day until midnight it is a day behind Melbourne), and its only caller,
-- job scholarship-discover-refill, is paused, so round states have not been refreshed since 17 Nov 2026 00:23 UTC (S2-BOOST read: two
-- withdrawn rounds still show "open" past closing).
--
-- What it changes
--   * scholarship_round_state_refresh_v1 decides open, opening soon and closed on the Melbourne date ((now() at time zone
--     'Australia/Melbourne')::date) instead of the UTC date (md5-guarded edit of every current_date in the body; nothing else changes).
--   * A rollup-scheduler target scholarship-round-state-refresh (hourly at :23, group A, live, no legacy job) runs it with the batch setting
--     batch.scholarship_round_state ("records classified an hour"); its command holds no number. The paused discovery job is left as it is.
-- The round states are read by the scholarship screens and the v3 scholarship status; no v2 feed and no updated_at of a consumer table is
-- touched. Nothing is dropped or deleted. G3 untouched.
-- Replaces: the UTC-date comparison; the refresh's dependency on the paused scholarship-discover-refill job.
-- Retires: nothing.

do $e$
declare
  v_sig constant regprocedure := 'security.scholarship_round_state_refresh_v1(integer)'::regprocedure;
  v_src text := (select prosrc from pg_proc where oid = 'security.scholarship_round_state_refresh_v1(integer)'::regprocedure);
  v_new constant text := '(now() at time zone ''Australia/Melbourne'')::date';
  v_def text;
begin
  if position('Australia/Melbourne' in v_src) > 0 then raise notice 'already on the Melbourne date'; return; end if;
  if md5(v_src) <> '09b6bce7b2eea9d25872af4fc9ed9cc0' then raise exception 'live scholarship_round_state_refresh_v1 differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  if (length(v_src) - length(replace(v_src, 'current_date', ''))) / length('current_date') <> 6 then raise exception 'expected six current_date comparisons'; end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  execute replace(v_def, 'current_date', v_new);
  if md5((select prosrc from pg_proc where oid = v_sig)) <> md5(replace(v_src, 'current_date', v_new)) then raise exception 'scholarship_round_state_refresh_v1 after the edit is not the expected body'; end if;
end $e$;

insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
values ('scholarship-round-state-refresh', null,
        'select security.scholarship_round_state_refresh_v1(security.pipeline_num_v1(''batch.scholarship_round_state'', 1000)::int)',
        md5('select security.scholarship_round_state_refresh_v1(security.pipeline_num_v1(''batch.scholarship_round_state'', 1000)::int)'),
        '23 * * * *', 'A', 75, true, 'live', 3000,
        'CF-247 19 Nov 2026 (s710; Platform Admin 18 Nov 17:55 and 21:58): new target, no legacy job; scholarship round states on the Melbourne date, hourly')
on conflict (target_code) do nothing;

do $$
declare v_src text := (select prosrc from pg_proc where oid = 'security.scholarship_round_state_refresh_v1(integer)'::regprocedure);
begin
  if position('current_date' in v_src) > 0 or position('Australia/Melbourne' in v_src) = 0 then raise exception 'post-check: the Melbourne date'; end if;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'scholarship-round-state-refresh' and enabled and mode = 'live') then raise exception 'post-check: target'; end if;
  if (select call_sql from pipeline.rollup_targets where target_code = 'scholarship-round-state-refresh') ~ '\(\s*[0-9]+\s*[,)]' then raise exception 'post-check: a number as an argument in the command'; end if;
end $$;
