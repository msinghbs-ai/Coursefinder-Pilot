CREATE OR REPLACE FUNCTION public.svc_adapter_shadow_claim(p_task text, p_limit integer, p_worker text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s pipeline.adapter_shadow_settings; v_spent numeric; v_reads int; v_task_reads int; v_cap int; v_limit int;
        v_class text; v_items jsonb := '[]'::jsonb; r record; v_prof jsonb; v_esc jsonb; v_tp jsonb; v_id uuid; v_l3 jsonb; v_l3_found boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_task not in ('intake','english','tuition') then raise exception 'task must be intake, english or tuition'; end if;
  v_class := case p_task when 'intake' then 'provider_intake_validation' when 'english' then 'provider_english_validation' else 'provider_current_tuition_validation' end;
  select * into s from pipeline.adapter_shadow_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('items', v_items, 'reason', 'shadow run switched off'); end if;
  perform pg_advisory_xact_lock(hashtext('adapter-shadow-claim'));
  -- a claim left by a lost worker is closed as an error after 30 minutes
  update pipeline.adapter_shadow_reads set status = 'error', errors = '["stale claim released"]'::jsonb, completed_at = now()
   where status = 'claimed' and claimed_at < now() - interval '30 minutes';
  -- spend counts every round today; the read limit counts the current round only
  select coalesce(sum(cost_usd), 0) into v_spent
    from pipeline.adapter_shadow_reads where claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  select count(*), count(*) filter (where task = p_task) into v_reads, v_task_reads
    from pipeline.adapter_shadow_reads where round = s.round and claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  if v_spent >= s.daily_usd_max then return jsonb_build_object('items', v_items, 'reason', format('daily spend limit: %s of %s USD', round(v_spent, 4), s.daily_usd_max)); end if;
  v_cap := s.daily_reads_max / 3;
  if v_task_reads >= v_cap or v_reads >= s.daily_reads_max then return jsonb_build_object('items', v_items, 'reason', format('daily read limit: %s of %s for %s', v_task_reads, v_cap, p_task)); end if;
  v_limit := greatest(1, least(coalesce(p_limit, 3), 10, v_cap - v_task_reads));
  -- tuition: the tuition task's own contract (prompt, checks, input length) with the adapter's model
  if p_task = 'tuition' then
    v_tp := (select to_jsonb(p) from pipeline.layer3_routed_profile(v_class) p where p.id is not null);
    if v_tp is null then return jsonb_build_object('items', v_items, 'reason', 'no routed tuition profile for the task contract'); end if;
  end if;
  for r in
    select w.id work_item_id, w.status l3_status, w.candidate_context, co.id course_id, co.provider_id, i.evidence_id, e.storage_path,
           e.source_url, e.mime_type, i.candidate_value, i.status i_status, i.estimated_cost_usd, to_jsonb(ua) adapter
      from pipeline.layer3_work_items w
      join pipeline.layer3_interpretations i on i.id = w.interpretation_id
      join pipeline.evidence_artifacts e on e.id = i.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id = w.entity_id
      join pipeline.uni_adapters ua on ua.provider_id = co.provider_id and ua.enabled
     where w.task_class = v_class and w.entity_type = 'course'
       and w.status in ('admitted','no_candidate','layer4_required','validated')
       and w.completed_at > now() - interval '30 days'
       and not exists (select 1 from pipeline.adapter_shadow_reads x where x.work_item_id = w.id)
     order by w.completed_at desc
     limit v_limit
  loop
    v_prof := (select to_jsonb(p) - 'prompt_system' - 'structured_output_schema' - 'deterministic_validators' - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                 from pipeline.layer3_model_profiles p
                where p.code = coalesce(s.model_profile_code, security.adapter_builder_model_for_v1(r.provider_id)->>'code')
                  and p.enabled and not p.paused and p.retired_at is null);
    if v_prof is null then continue; end if;
    -- round 3: one stronger model, asked once only when the first model found nothing and the page clearly shows the field
    v_esc := (select to_jsonb(p) - 'prompt_system' - 'structured_output_schema' - 'deterministic_validators' - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                from pipeline.layer3_model_profiles p
               where p.code = s.escalation_profile_code and p.enabled and not p.paused and p.retired_at is null);
    if p_task = 'tuition' then
      -- the adapter's model and credential; the tuition task's prompt, checks and limits
      v_prof := v_tp - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                || jsonb_build_object('id', v_prof->'id', 'code', v_prof->'code', 'model_identifier', v_prof->'model_identifier',
                                      'base_url', v_prof->'base_url', 'secret_env_key', v_prof->'secret_env_key', 'task_contract_profile', v_tp->'code');
      if v_esc is not null then
        v_esc := v_tp - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                 || jsonb_build_object('id', v_esc->'id', 'code', v_esc->'code', 'model_identifier', v_esc->'model_identifier',
                                       'base_url', v_esc->'base_url', 'secret_env_key', v_esc->'secret_env_key', 'task_contract_profile', v_tp->'code');
      end if;
      v_l3 := case when r.i_status <> 'provider_error' and security.adapter_shadow_found_v1('tuition', r.candidate_value) then r.candidate_value end;
      v_l3_found := v_l3 is not null;
    else
      v_l3 := case when r.i_status = 'validated' then r.candidate_value end;
      v_l3_found := r.i_status = 'validated' and security.adapter_shadow_found_v1(p_task, r.candidate_value);
    end if;
    insert into pipeline.adapter_shadow_reads(task, work_item_id, course_id, provider_id, evidence_id, profile_code, model, layer3_status,
           layer3_value, layer3_found, layer3_cost_usd, round)
    values (p_task, r.work_item_id, r.course_id, r.provider_id, r.evidence_id, v_prof->>'code', v_prof->>'model_identifier', r.l3_status,
           v_l3, v_l3_found, r.estimated_cost_usd, s.round)
    returning id into v_id;
    v_items := v_items || jsonb_build_object('shadow_id', v_id, 'course_id', r.course_id, 'provider_id', r.provider_id,
      'storage_path', r.storage_path, 'source_url', r.source_url, 'mime_type', r.mime_type,
      'context', case when p_task = 'tuition' then r.candidate_context end,
      'adapter', r.adapter - 'notes' - 'reason' - 'updated_by' - 'admit_reason', 'profile', v_prof, 'escalation', v_esc);
  end loop;
  return jsonb_build_object('items', v_items, 'round', s.round, 'spent_today_usd', v_spent, 'reads_today', v_reads, 'worker', p_worker);
end $function$
