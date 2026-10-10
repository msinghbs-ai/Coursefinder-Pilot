CREATE OR REPLACE FUNCTION public.admin_adapter_builder(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_id uuid; v_d pipeline.uni_adapter_drafts%rowtype; v_n int; v_b jsonb; v_samples jsonb; v_m jsonb; v_s jsonb; v_cid uuid; v_code text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object('budget', security.adapter_builder_budget(), 'can_manage', v_rank >= 6,
      'model', security.adapter_builder_model_for_v1(v_pid), 'models', case when v_rank >= 6 then security.adapter_builder_models_v1() else '[]'::jsonb end,
      'max_samples', 10,
      'pages', case when v_rank >= 6 then coalesce((select jsonb_agg(jsonb_build_object('course', x.title, 'code', x.code, 'url', x.url, 'read', x.read_status = 'read') order by x.title) from (
                 select distinct on (pg.url) coalesce(c.display_title, c.canonical_title) title, pg.url, pg.read_status,
                        (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code
                   from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
                  where pg.provider_id = v_pid and pg.url is not null limit 600) x), '[]'::jsonb) else '[]'::jsonb end,
      'drafts', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from (select * from pipeline.uni_adapter_drafts where provider_id = v_pid order by created_at desc limit 3) d), '[]'::jsonb));
  end if;
  if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'model' then
    if not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'unknown provider'; end if;
    v_code := nullif(btrim(coalesce(p_args->>'profile_code', '')), '');
    if v_code is null then
      delete from pipeline.uni_adapter_models where provider_id = v_pid;
    else
      if not exists (select 1 from jsonb_array_elements(security.adapter_builder_models_v1()) x where x->>'code' = v_code) then
        raise exception 'that model is not enabled and qualified for intake work (Models & services)';
      end if;
      insert into pipeline.uni_adapter_models(provider_id, profile_code, set_by, reason) values (v_pid, v_code, auth.uid(), v_reason)
        on conflict (provider_id) do update set profile_code = excluded.profile_code, set_by = excluded.set_by, set_at = now(), reason = excluded.reason;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_model', v_pid::text, jsonb_build_object('profile_code', v_code, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'model', security.adapter_builder_model_for_v1(v_pid));
  end if;
  if p_action = 'start' then
    v_n := least(greatest(coalesce((security.firecrawl_setting('builder_samples') #>> '{}')::int, 6), 1), 10);
    select coalesce(jsonb_agg(jsonb_build_object('course_id', x.course_id, 'course', x.title, 'code', x.code, 'url', x.url, 'kind', x.kind) order by x.kr, x.kind), '[]'::jsonb) into v_samples from (
      select q.*, row_number() over (partition by q.kind order by random()) kr from (
        select distinct on (pg.url) pg.course_id, coalesce(c.display_title, c.canonical_title) title, (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code, pg.url,
               case when coalesce(c.display_title, c.canonical_title) ~* '/|, bachelor|and bachelor|double' then 'double'
                    when coalesce(c.display_title, c.canonical_title) ~* 'master|graduate|doctor|postgrad' then 'postgraduate'
                    when coalesce(c.display_title, c.canonical_title) ~* 'certificate|diploma' then 'certificate or diploma'
                    else 'undergraduate' end kind
          from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status in ('active', 'inactive')
         where pg.provider_id = v_pid and pg.read_status = 'read' and pg.url is not null) q
      order by kr, kind limit v_n) x;
    if jsonb_array_length(coalesce(v_samples, '[]'::jsonb)) = 0 then raise exception 'no confirmed course page for this university yet - find pages first'; end if;
    insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, v_samples, v_reason, auth.uid()) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_start', v_pid::text, jsonb_build_object('draft_id', v_id, 'samples', v_samples, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  if p_action = 'add_sample' then
    v_cid := nullif(p_args->>'course_id', '')::uuid;
    select jsonb_build_object('course_id', pg.course_id, 'course', coalesce(c.display_title, c.canonical_title),
             'code', (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1),
             'url', pg.url, 'kind', 'chosen'), pg.provider_id
      into v_s, v_pid
      from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
     where pg.url is not null and (pg.course_id = v_cid or (v_cid is null and pg.provider_id = v_pid and pg.url = nullif(p_args->>'url', '')))
     order by (pg.read_status = 'read') desc limit 1;
    if v_s is null then raise exception 'this course has no stored page to sample'; end if;
    select * into v_d from pipeline.uni_adapter_drafts where provider_id = v_pid order by created_at desc limit 1;
    if v_d.id is not null and v_d.status in ('capturing', 'proposing') then raise exception 'the current samples are still being captured or proposed; try again in a minute'; end if;
    if v_d.id is null then
      insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, jsonb_build_array(v_s), v_reason, auth.uid()) returning id into v_id;
    else
      if exists (select 1 from jsonb_array_elements(v_d.samples) x where x->>'url' = v_s->>'url') then raise exception 'this page is already a sample'; end if;
      if jsonb_array_length(v_d.samples) >= 10 then raise exception 'a draft holds at most 10 samples: capture new samples to start again'; end if;
      update pipeline.uni_adapter_drafts set samples = samples || jsonb_build_array(v_s), status = 'capturing', updated_at = now() where id = v_d.id;
      v_id := v_d.id;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_add_sample', v_pid::text, jsonb_build_object('draft_id', v_id, 'sample', v_s, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  select * into v_d from pipeline.uni_adapter_drafts where id = (p_args->>'draft_id')::uuid;
  if v_d.id is null then raise exception 'unknown draft'; end if;
  if p_action = 'marks' then
    if jsonb_typeof(coalesce(p_args->'marks', '[]'::jsonb)) <> 'array' then raise exception 'marks must be a list'; end if;
    update pipeline.uni_adapter_drafts set marks = coalesce(p_args->'marks', '[]'::jsonb), comments = left(coalesce(p_args->>'comments', ''), 4000), updated_at = now() where id = v_d.id;
    return jsonb_build_object('ok', true);
  elsif p_action = 'propose' then
    if jsonb_array_length(v_d.captures) = 0 then raise exception 'capture the sample pages first'; end if;
    v_b := security.adapter_builder_budget();
    if (v_b->>'used_usd')::numeric >= (v_b->>'limit_usd')::numeric then raise exception 'the AI allowance for today is used (US$ % of %). It is a setting under Adapter builder', v_b->>'used_usd', v_b->>'limit_usd'; end if;
    if (v_b->>'proposals')::int >= (v_b->>'limit_proposals')::int then raise exception 'the proposals for today are used (% of %). It is a setting under Adapter builder', v_b->>'proposals', v_b->>'limit_proposals'; end if;
    v_m := security.adapter_builder_model_for_v1(v_d.provider_id);
    update pipeline.uni_adapter_drafts set status = 'proposing', marks = coalesce(p_args->'marks', marks), comments = coalesce(left(p_args->>'comments', 4000), comments), model = v_m->>'model', model_profile = v_m->>'code', updated_at = now() where id = v_d.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_propose', v_d.provider_id::text, jsonb_build_object('draft_id', v_d.id, 'budget', v_b, 'model', v_m), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_propose', 'draft_id', v_d.id));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $function$
