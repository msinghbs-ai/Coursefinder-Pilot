-- CF-247 (23 Oct 2026). Platform Admin 18:42: "We should try higher setting lets try 100". Tasks moved per lane each minute
-- (jobs.per_lane_per_tick) now goes up to 100 and is set to 100 (logged). The runner still stops taking more after 40 seconds, so a
-- minute's run ends before the next starts whatever the setting.
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

update pipeline.platform_toolset_settings set max_value = '100', value = '100'::jsonb, reason = 'Platform Admin 23 Oct 2026 18:42: lets try 100', updated_at = now()
 where toolset_key = 'pipeline' and key = 'jobs.per_lane_per_tick';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting', 'pipeline.jobs.per_lane_per_tick',
        jsonb_build_object('before', 40, 'after', 100, 'range', '1 to 100', 'reason', 'Platform Admin 23 Oct 2026 18:42: lets try 100 (migration 20261023021000)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

select pg_temp.edit_once('security.admin_jobs_tick_v1(integer)', '103c6596e1aea7a0096d2994ba782625', array[
  array[$o$'jobs.per_lane_per_tick', 1)::int, 40));$o$, $n$'jobs.per_lane_per_tick', 1)::int, 100));$n$]]);
select pg_temp.edit_once('public.admin_jobs_pulse()', 'b840c8e6130a71203bc8a57605f631b6', array[
  array[$o$'jobs.per_lane_per_tick', 1)::int, 40))$o$, $n$'jobs.per_lane_per_tick', 1)::int, 100))$n$]]);

select 'tasks moved per lane each minute: up to 100' ok;
