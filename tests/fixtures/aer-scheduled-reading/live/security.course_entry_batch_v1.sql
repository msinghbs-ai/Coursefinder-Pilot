CREATE OR REPLACE FUNCTION security.course_entry_batch_v1(p_provider uuid, p_size integer, p_reason text, p_actor uuid, p_preview boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_max int := security.pipeline_num_v1('entry.course_batch_size', 50)::int; v_n int; v_ids uuid[]; v_cost numeric := security.course_entry_cost_v1();
        v_bal numeric; v_floor numeric; v_est numeric; v_job uuid; v_reason text := btrim(coalesce(p_reason, '')); v_prov jsonb; v_wait int;
begin
  v_n := greatest(1, least(coalesce(p_size, v_max), v_max));
  select array_agg(z.course_id order by z.prio, z.title, z.course_id), jsonb_object_agg(z.pname, z.k) into v_ids, v_prov from (
    select q.course_id, q.prio, q.title, coalesce(p.display_name, p.canonical_name) pname, count(*) over (partition by q.provider_id) k
      from (select el.* from security.course_entry_eligible_v1() el
             where (p_provider is null or el.provider_id = p_provider)
               and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = el.course_id and f.field = 'entry_requirements')
             order by el.prio, el.title, el.course_id limit v_n) q
      join catalogue.providers p on p.id = q.provider_id) z;
  v_est := round(coalesce(array_length(v_ids, 1), 0) * v_cost, 4);
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  select count(*) into v_wait from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if p_preview then
    return jsonb_build_object('preview', true, 'courses', coalesce(array_length(v_ids, 1), 0), 'providers', coalesce(v_prov, '{}'::jsonb), 'estimate_usd', v_est,
      'cost_per_course_usd', round(v_cost, 5), 'balance_usd', v_bal, 'floor_usd', v_floor, 'batch_size', v_max, 'waiting', v_wait,
      'refusal', case when coalesce(array_length(v_ids, 1), 0) = 0 then 'no course is left to read for this choice'
                      when v_wait > 0 then 'an earlier course read is still waiting; the next batch follows it'
                      when not security.ai_use_allowed_v1('enrich_fields') then 'AI reading is stopped (AI limits)'
                      when v_bal is not null and v_bal - v_est < v_floor then 'the estimate would take the OpenRouter balance below its floor (Toolsets & limits)' end);
  end if;
  if length(v_reason) < 5 then raise exception 'give a reason (kept in the history)' using errcode = '22023'; end if;
  if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no course is left to read for this choice' using errcode = '22023'; end if;
  if v_wait > 0 then raise exception 'an earlier course read is still waiting (% courses); the next batch follows it', v_wait using errcode = '22023'; end if;
  if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'AI reading is stopped (AI limits); nothing was asked' using errcode = '22023'; end if;
  if v_bal is not null and v_bal - v_est < v_floor then
    raise exception 'the estimate (US$%) would take the OpenRouter balance (US$%) below its floor (US$%); nothing was asked', v_est, round(v_bal, 2), v_floor using errcode = '22023'; end if;
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'queued', left('Entry requirements · ' || array_length(v_ids, 1) || ' courses', 200),
          jsonb_build_object('read_now', true, 'entry_read', true, 'entry_batch', true, 'countries', '[]'::jsonb,
                             'provider_ids', (select jsonb_agg(distinct c.provider_id) from catalogue.courses c where c.id = any (v_ids)), 'course_ids', to_jsonb(v_ids),
                             'fields', jsonb_build_array('entry_requirements'), 'ai', true, 'scraper', false, 'estimate_usd', v_est),
          jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), p_actor, v_reason, array_length(v_ids, 1) || ' courses')
  returning id into v_job;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
  select v_job, c.provider_id, c.id, 'entry_requirements', 'queued' from catalogue.courses c where c.id = any (v_ids)
  on conflict do nothing;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_requirements', 'course_batch', v_job::text, jsonb_build_object('courses', array_length(v_ids, 1), 'providers', v_prov, 'estimate_usd', v_est, 'reason', v_reason), p_actor);
  return jsonb_build_object('ok', true, 'job_id', v_job, 'courses', array_length(v_ids, 1), 'providers', v_prov, 'estimate_usd', v_est);
end $function$
