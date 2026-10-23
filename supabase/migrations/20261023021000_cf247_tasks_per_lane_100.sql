-- CF-247 (23 Oct 2026). Platform Admin 18:42: "We should try higher setting lets try 100"; 18:45: "Keep incrementing to higher i want
-- to test the limits if the system, we can decrease if it start failing or stalled by system". Dry runs on the live database (one
-- minute's run, one-course Read with AI tasks): 100 in 1.6 s, 250 in 3.5 s, 500 in 4.4 s, 1,000 in 12.4 s, 2,000 in 25.2 s (about
-- 12 ms a task; the 40-second stop is reached near 3,000). Tasks moved per lane each minute (jobs.per_lane_per_tick) now goes up to
-- 2,000 and is set to 1,000 (logged). The runner still stops taking more after 40 seconds, so a minute's run ends before the next.
-- Replaces: nothing (security.admin_jobs_tick_v1 and public.admin_jobs_pulse edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

update pipeline.platform_toolset_settings set max_value = '2000', value = '1000'::jsonb, reason = 'Platform Admin 23 Oct 2026 18:45: keep incrementing to test the limits', updated_at = now()
 where toolset_key = 'pipeline' and key = 'jobs.per_lane_per_tick';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting', 'pipeline.jobs.per_lane_per_tick',
        jsonb_build_object('before', 40, 'after', 1000, 'range', '1 to 2000', 'reason', 'Platform Admin 23 Oct 2026 18:45: keep incrementing to test the limits; dry run 1,000 in 12.4 s, 2,000 in 25.2 s (migration 20261023021000)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

select pg_temp.edit_once('security.admin_jobs_tick_v1(integer)', '103c6596e1aea7a0096d2994ba782625', array[
  array[$o$'jobs.per_lane_per_tick', 1)::int, 40));$o$, $n$'jobs.per_lane_per_tick', 1)::int, 2000));$n$]]);
select pg_temp.edit_once('public.admin_jobs_pulse()', 'b840c8e6130a71203bc8a57605f631b6', array[
  array[$o$'jobs.per_lane_per_tick', 1)::int, 40))$o$, $n$'jobs.per_lane_per_tick', 1)::int, 2000))$n$]]);

select 'tasks moved per lane each minute: up to 2000, set to 1000' ok;
