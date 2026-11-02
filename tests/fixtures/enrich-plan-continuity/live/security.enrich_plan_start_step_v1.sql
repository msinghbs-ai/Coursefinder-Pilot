CREATE OR REPLACE FUNCTION security.enrich_plan_start_step_v1(p_run uuid, p_step text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.enrich_plan_runs%rowtype; v jsonb; v_o record; v_fields jsonb;
begin
  select * into r from pipeline.enrich_plan_runs where id = p_run;
  -- the step runs as the person behind the run, with that person's role checks
  perform set_config('request.jwt.claims', json_build_object('sub', r.requested_by, 'role', 'authenticated')::text, true);
  if p_step = 'site' then
    v := public.admin_jobs('start', jsonb_build_object('kind', 'provider_fill', 'from', 'Enrichment plan', 'args', jsonb_build_object('provider_id', r.provider_id)));
    return jsonb_build_object('kind', 'job', 'id', v->>'id');
  elsif p_step = 'pages' then
    v := public.admin_jobs('start', jsonb_build_object('kind', 'course_page_find', 'from', 'Enrichment plan', 'args', jsonb_build_object('provider_id', r.provider_id)));
    return jsonb_build_object('kind', 'job', 'id', v->>'id');
  elsif p_step = 'scholarships' then
    v := public.admin_jobs('start', jsonb_build_object('kind', 'scholarship_provider_scan', 'from', 'Enrichment plan', 'args', jsonb_build_object('provider_ids', jsonb_build_array(r.provider_id))));
    return jsonb_build_object('kind', 'job', 'id', v->>'id');
  elsif p_step = 'fields' then
    v := public.admin_enrich_fields('start', jsonb_build_object('provider_ids', jsonb_build_array(r.provider_id), 'fields', to_jsonb(array(select e.field from security.enrich_fields_v1() e where e.field <> 'provider_address')),
                                    'ai', true, 'scraper', true, 'reason', 'Enrichment plan (' || r.mode || '): ' || r.reason));
    return jsonb_build_object('kind', 'job', 'id', v->>'job_id', 'items', v->'items');
  elsif p_step = 'adapter' then
    select o.id, o.status into v_o from pipeline.provider_onboarding o where o.provider_id = r.provider_id order by o.created_at desc limit 1;
    if v_o.status = 'stopped' then
      v := public.admin_provider_onboarding('retry', jsonb_build_object('ids', jsonb_build_array(v_o.id), 'reason', 'Enrichment plan (' || r.mode || '): ' || r.reason));
    elsif v_o.status is null or v_o.status in ('done', 'cancelled') then
      v := public.admin_provider_onboarding('start', jsonb_build_object('provider_ids', jsonb_build_array(r.provider_id), 'reason', 'Enrichment plan (' || r.mode || '): ' || r.reason));
    end if;
    return jsonb_build_object('kind', 'onboarding', 'id', (select o.id from pipeline.provider_onboarding o where o.provider_id = r.provider_id order by o.created_at desc limit 1));
  end if;
  raise exception 'unknown step %', p_step;
end $function$
