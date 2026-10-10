-- CF-247 Phase 3: tuition joins the shadow run; capacity raised to finish the comparison in about 4 hours.
-- Platform Admin, 9 Oct 2026: "Add tuition to the shadow run or any other attribute as required, increase the capacity to
-- finish it 4 hours." Layer 3 reads three fields (intakes, English, tuition); with tuition all three are compared.
--
-- Tuition is read as Layer 3 reads it: the model picks one of the fee candidates the page reader found (the tuition task
-- contract: its prompt, its checks and its input length), here with the adapter's own pinned model. A tuition value is
-- "found" when a candidate amount is picked (Layer 3's own pick is used the same way, whatever its later checks said);
-- two picks agree when the amount (to the dollar), the fee year and the audience are the same.
--
-- Capacity: 1,500 reads a day (500 a field), 6 reads a field every 2 minutes (about 180 an hour a field), so each field
-- passes the 300-compared minimum in about 2 hours. The US$15 a day limit is unchanged (a read costs about US$0.0002).
-- Courses Layer 3 finished in the last 30 days are eligible (was 14), so tuition has enough to compare.
-- Each replaced function is checked against its live definition (md5) first. Nothing is admitted or deleted.

do $guard$
declare want jsonb := '{"security.adapter_shadow_found_v1(text,jsonb)":"cf90edc09f5b3d469f282d547ba0c728",
  "security.adapter_shadow_same_v1(text,jsonb,jsonb)":"04397f7e3335b46e4aa41dbf27a69962",
  "svc_adapter_shadow_claim(text,integer,text)":"8e531de76bb9cb1a218ab00153d7b747",
  "svc_adapter_shadow_complete(uuid,jsonb)":"483601f92cc234445875f8d33dbec7f9"}'; k text; v text;
begin
  for k, v in select * from jsonb_each_text(want) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v then raise exception 'live % differs from the definition this change replaces', k; end if;
  end loop;
end $guard$;

alter table pipeline.adapter_shadow_reads drop constraint adapter_shadow_reads_task_check;
alter table pipeline.adapter_shadow_reads add constraint adapter_shadow_reads_task_check check (task in ('intake','english','tuition'));

update pipeline.adapter_shadow_settings set daily_reads_max = 1500,
  reason = 'Platform Admin 9 Oct 2026: US$15/day; tuition added; capacity raised to finish in about 4 hours; retire at 95%+ agreement and at least as many found',
  updated_at = now() where id = 1;

create or replace function security.adapter_shadow_found_v1(p_task text, v jsonb)
returns boolean language sql immutable set search_path to '' as $$
  select case when v is null or jsonb_typeof(v) <> 'object' then false
              when p_task = 'intake' then jsonb_typeof(v->'months') = 'array' and jsonb_array_length(v->'months') > 0
              when p_task = 'tuition' then jsonb_typeof(v->'amount') = 'number' or (v->>'amount') ~ '^[0-9]+(\.[0-9]+)?$'
              else jsonb_typeof(v->'tests') = 'array' and jsonb_array_length(v->'tests') > 0 end
$$;

create or replace function security.adapter_shadow_same_v1(p_task text, a jsonb, b jsonb)
returns boolean language sql immutable set search_path to '' as $$
  select case
    when a is null or b is null then null
    when p_task = 'intake' then
      coalesce((select array_agg(distinct (m)::int order by (m)::int) from jsonb_array_elements_text(a->'months') m), '{}')
      = coalesce((select array_agg(distinct (m)::int order by (m)::int) from jsonb_array_elements_text(b->'months') m), '{}')
    when p_task = 'tuition' then
      round((a->>'amount')::numeric) = round((b->>'amount')::numeric)
      and nullif(substring(a->>'fee_year' from '[0-9]{4}'), '') is not distinct from nullif(substring(b->>'fee_year' from '[0-9]{4}'), '')
      and lower(coalesce(a->>'audience', '')) = lower(coalesce(b->>'audience', ''))
    else
      coalesce((select array_agg(distinct (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text order by (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text) from jsonb_array_elements(a->'tests') t), '{}')
      = coalesce((select array_agg(distinct (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text order by (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text) from jsonb_array_elements(b->'tests') t), '{}')
  end
$$;

create or replace function public.svc_adapter_shadow_claim(p_task text, p_limit int, p_worker text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare s pipeline.adapter_shadow_settings; v_spent numeric; v_reads int; v_task_reads int; v_cap int; v_limit int;
        v_class text; v_items jsonb := '[]'::jsonb; r record; v_prof jsonb; v_tp jsonb; v_id uuid; v_l3 jsonb; v_l3_found boolean;
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
  select coalesce(sum(cost_usd), 0), count(*), count(*) filter (where task = p_task) into v_spent, v_reads, v_task_reads
    from pipeline.adapter_shadow_reads where claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
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
                where p.code = security.adapter_builder_model_for_v1(r.provider_id)->>'code'
                  and p.enabled and not p.paused and p.retired_at is null);
    if v_prof is null then continue; end if;
    if p_task = 'tuition' then
      -- the adapter's model and credential; the tuition task's prompt, checks and limits
      v_prof := v_tp - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                || jsonb_build_object('id', v_prof->'id', 'code', v_prof->'code', 'model_identifier', v_prof->'model_identifier',
                                      'base_url', v_prof->'base_url', 'secret_env_key', v_prof->'secret_env_key', 'task_contract_profile', v_tp->'code');
      v_l3 := case when r.i_status <> 'provider_error' and security.adapter_shadow_found_v1('tuition', r.candidate_value) then r.candidate_value end;
      v_l3_found := v_l3 is not null;
    else
      v_l3 := case when r.i_status = 'validated' then r.candidate_value end;
      v_l3_found := r.i_status = 'validated' and security.adapter_shadow_found_v1(p_task, r.candidate_value);
    end if;
    insert into pipeline.adapter_shadow_reads(task, work_item_id, course_id, provider_id, evidence_id, profile_code, model, layer3_status,
           layer3_value, layer3_found, layer3_cost_usd)
    values (p_task, r.work_item_id, r.course_id, r.provider_id, r.evidence_id, v_prof->>'code', v_prof->>'model_identifier', r.l3_status,
           v_l3, v_l3_found, r.estimated_cost_usd)
    returning id into v_id;
    v_items := v_items || jsonb_build_object('shadow_id', v_id, 'course_id', r.course_id, 'provider_id', r.provider_id,
      'storage_path', r.storage_path, 'source_url', r.source_url, 'mime_type', r.mime_type,
      'context', case when p_task = 'tuition' then r.candidate_context end,
      'adapter', r.adapter - 'notes' - 'reason' - 'updated_by' - 'admit_reason', 'profile', v_prof);
  end loop;
  return jsonb_build_object('items', v_items, 'spent_today_usd', v_spent, 'reads_today', v_reads, 'worker', p_worker);
end $$;

create or replace function public.svc_adapter_shadow_complete(p_id uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v pipeline.adapter_shadow_reads; v_found boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v from pipeline.adapter_shadow_reads where id = p_id for update;
  if v.id is null or v.status <> 'claimed' then return jsonb_build_object('ok', false, 'reason', 'not an open shadow claim'); end if;
  -- tuition: the pick counts as found whatever its checks said, as for Layer 3; intake and English: a checked value
  v_found := case when v.task = 'tuition' then not (p_result ? 'worker_error') and security.adapter_shadow_found_v1(v.task, p_result->'admitted')
                  else coalesce((p_result->>'valid')::boolean, false) and security.adapter_shadow_found_v1(v.task, p_result->'admitted') end;
  update pipeline.adapter_shadow_reads set
    status = case when p_result ? 'worker_error' then 'error' else 'done' end,
    input_basis = p_result->>'input_basis', input_chars = (p_result->>'input_chars')::int,
    shadow_status = p_result->>'status', shadow_valid = (p_result->>'valid')::boolean,
    shadow_value = case when v_found then p_result->'admitted' end, shadow_found = v_found,
    agree = case when v_found and v.layer3_found then security.adapter_shadow_same_v1(v.task, p_result->'admitted', v.layer3_value) end,
    cost_usd = coalesce((p_result->>'cost_usd')::numeric, 0), input_tokens = (p_result->>'input_tokens')::int,
    output_tokens = (p_result->>'output_tokens')::int, latency_ms = (p_result->>'latency_ms')::int,
    errors = p_result->'errors', worker_version = p_result->>'worker_version', completed_at = now()
  where id = p_id returning * into v;
  return jsonb_build_object('ok', true, 'status', v.status, 'shadow_found', v.shadow_found, 'layer3_found', v.layer3_found, 'agree', v.agree);
end $$;

revoke all on function public.svc_adapter_shadow_claim(text, int, text) from public, anon, authenticated;
revoke all on function public.svc_adapter_shadow_complete(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_adapter_shadow_claim(text, int, text) to service_role;
grant execute on function public.svc_adapter_shadow_complete(uuid, jsonb) to service_role;

-- 6 a field every 2 minutes; tuition on its own minute
select cron.alter_job((select jobid from cron.job where jobname = 'adapter-shadow-intake'),
  command := $c$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"shadow","task":"intake","limit":6,"concurrency":4}'::jsonb)$c$);
select cron.alter_job((select jobid from cron.job where jobname = 'adapter-shadow-english'),
  command := $c$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"shadow","task":"english","limit":6,"concurrency":4}'::jsonb)$c$);
select cron.schedule('adapter-shadow-tuition', '*/2 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"shadow","task":"tuition","limit":6,"concurrency":4}'::jsonb)$c$);
