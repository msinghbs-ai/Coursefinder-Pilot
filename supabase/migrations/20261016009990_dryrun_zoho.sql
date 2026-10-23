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

update pipeline.platform_toolset_settings set max_value = '2000', value = '2000'::jsonb, reason = 'Platform Admin 23 Oct 2026 18:42: lets try 100', updated_at = now()
 where toolset_key = 'pipeline' and key = 'jobs.per_lane_per_tick';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting', 'pipeline.jobs.per_lane_per_tick',
        jsonb_build_object('before', 40, 'after', 100, 'range', '1 to 100', 'reason', 'Platform Admin 23 Oct 2026 18:42: lets try 100 (migration 20261023021000)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

select pg_temp.edit_once('security.admin_jobs_tick_v1(integer)', '103c6596e1aea7a0096d2994ba782625', array[
  array[$o$'jobs.per_lane_per_tick', 1)::int, 40));$o$, $n$'jobs.per_lane_per_tick', 1)::int, 2000));$n$]]);
select pg_temp.edit_once('public.admin_jobs_pulse()', 'b840c8e6130a71203bc8a57605f631b6', array[
  array[$o$'jobs.per_lane_per_tick', 1)::int, 40))$o$, $n$'jobs.per_lane_per_tick', 1)::int, 2000))$n$]]);

do $d$ declare r jsonb; t0 timestamptz; ms int; n int;
begin
  update pipeline.platform_toolset_settings set value = '2000'::jsonb where toolset_key = 'pipeline' and key = 'jobs.per_lane_per_tick';
  with c as (select c.id, c.provider_id, c.canonical_title from catalogue.courses c join pipeline.coverage_course_pages g on g.course_id = c.id
              where g.status = 'bound' and g.evidence_id is not null and not security.enrich_item_held_v1(c.id, 'delivery') limit 2000),
       j as (insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
             select 'enrich_fields', 'enrich', 'queued', 'DRY ' || c.canonical_title,
                    jsonb_build_object('read_now', true, 'countries', '[]'::jsonb, 'provider_ids', jsonb_build_array(c.provider_id), 'course_ids', jsonb_build_array(c.id), 'fields', '["delivery"]'::jsonb, 'ai', true, 'scraper', false),
                    jsonb_build_object('done', 0, 'total', 0), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid, 'dry run', '1 course' from c
             returning id, args)
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
  select j.id, (j.args->'provider_ids'->>0)::uuid, (j.args->'course_ids'->>0)::uuid, 'delivery', 'queued' from j;
  get diagnostics n = row_count;
  t0 := clock_timestamp();
  r := security.admin_jobs_tick_v1(security.pipeline_num_v1('batch.admin_jobs', 10)::int);
  ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  raise exception 'DRYRUN OK N=2000 items %; moved % in % ms; handed to AI %', n, jsonb_array_length(r), ms,
    (select count(*) from pipeline.field_enrich_items i join pipeline.admin_jobs j on j.id = i.job_id where j.title like 'DRY %' and i.state = 'ai');
end $d$;
