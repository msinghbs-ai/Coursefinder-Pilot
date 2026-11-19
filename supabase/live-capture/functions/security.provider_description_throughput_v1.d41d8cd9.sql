CREATE OR REPLACE FUNCTION security.provider_description_throughput_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_every numeric := security.pipeline_num_v1('pdesc.every_minutes', 60); v_target numeric := security.pipeline_num_v1('pdesc.target_hours', 12); v_batch int := security.pipeline_num_v1('batch.provider_description', 3)::int;
        v_disp int := security.pipeline_num_v1('pdesc.dispatch_max', 3)::int; v_cap int := security.pipeline_num_v1('pdesc.queue_cap', 60)::int; v_win numeric := security.pipeline_num_v1('pdesc.rate_window_hours', 3);
        v_back numeric := security.pipeline_num_v1('pdesc.backlog_hours', 2); v_by jsonb; v_total int; v_obs numeric; v_queued int; v_runs numeric; v_size int; v_room int; v_target_q int; v_share jsonb := '{}'::jsonb; c record;
begin
  select coalesce(jsonb_object_agg(z.cc, z.n), '{}'::jsonb), coalesce(sum(z.n), 0)::int into v_by, v_total from (
    select k.iso_alpha2::text cc, count(*) filter (where lr.state is null or lr.state in ('queued', 'reading')) n
      from catalogue.providers p join ref.countries k on k.id = p.country_id
      left join lateral (select x.state from pipeline.provider_description_reads x where x.provider_id = p.id order by x.created_at desc, x.id desc limit 1) lr on true
     where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null and security.provider_description_scope_v1(p.id)
     group by k.iso_alpha2) z;
  select count(*)::numeric / v_win into v_obs from pipeline.provider_description_reads x where x.updated_at > now() - make_interval(hours => v_win::int) and x.state in ('proposed', 'admitted', 'verified', 'held', 'dead_letter', 'rejected');
  select count(*) into v_queued from pipeline.provider_description_reads x where x.state = 'queued';
  v_runs := greatest(1, floor(v_target * 60 / greatest(v_every, 1)));
  v_size := least(v_cap, greatest(1, ceil(v_total / v_runs)::int));
  v_target_q := greatest(v_batch * v_disp * security.pipeline_num_v1('pdesc.queue_floor_runs', 2)::int, ceil(v_obs * v_back)::int);
  v_room := greatest(0, v_target_q - v_queued);
  v_size := least(v_size, v_room);
  if v_total > 0 and v_size > 0 then
    for c in select key cc, value::int n from jsonb_each_text(v_by) where value::int > 0 loop
      v_share := v_share || jsonb_build_object(c.cc, least(c.n, greatest(1, ceil(v_size::numeric * c.n / v_total)::int)));
    end loop;
  end if;
  return jsonb_build_object('remaining_total', v_total, 'remaining_by_country', v_by, 'observed_per_hour', round(v_obs, 2), 'queued_now', v_queued, 'runs_in_target', v_runs,
    'enqueue_size', v_size, 'queue_target', v_target_q, 'share', v_share, 'eta_hours', case when v_obs > 0 then round(v_total / v_obs, 1) end, 'target_hours', v_target);
end $function$
