-- CF-CHG-20260915-247 — Stage 1 of the path to Production handover.
-- Governed activation gate for Layer 3 model profiles, automatic pause on
-- binding drift, deterministic Layer 3 tuition admission, and the enqueue /
-- dispatch / admission schedules (created switched off).
--
-- Governance note: applied directly to the live Pilot Supabase project
-- (as migrations cf247_stage1_activation_gate_and_tuition_admission and
-- cf247_stage1_layer3_tuition_schedules_disabled) before being committed
-- here. Every function in this file was verified byte-identical to the
-- live definition by checksum of pg_get_functiondef after apply.

-- ========== 1. Append-only activation audit ==========
create table if not exists pipeline.layer3_profile_activation_events(
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references pipeline.layer3_model_profiles(id),
  action text not null check (action in ('activated','activation_refused','paused','auto_paused_binding_drift')),
  actor_id uuid,
  reason text,
  binding_hash text,
  benchmark_run_id text,
  checks jsonb not null default '{}'::jsonb,
  change_control_ref text not null default 'CF-CHG-20260915-247',
  created_at timestamptz not null default now()
);
alter table pipeline.layer3_profile_activation_events enable row level security;
revoke all on table pipeline.layer3_profile_activation_events from public, anon, authenticated;

create or replace function pipeline.layer3_profile_activation_events_append_only()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
begin raise exception 'layer3 profile activation events are append-only'; end $$;
drop trigger if exists layer3_profile_activation_events_append_only on pipeline.layer3_profile_activation_events;
create trigger layer3_profile_activation_events_append_only
  before update or delete on pipeline.layer3_profile_activation_events
  for each row execute function pipeline.layer3_profile_activation_events_append_only();

-- ========== 2. Governed activation ==========
create or replace function security.layer3_profile_activate_impl(p_profile_id uuid, p_reason text)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','auth','vault' as $$
declare
  p pipeline.layer3_model_profiles%rowtype;
  v_fail text[] := '{}';
  v_completed timestamptz;
  v_hash text;
  v_conflict text;
  v_checks jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then
    raise exception 'administrator role required to activate a Layer 3 profile' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_reason,''))) < 8 then raise exception 'activation reason required (8+ characters)'; end if;
  select * into p from pipeline.layer3_model_profiles where id = p_profile_id for update;
  if not found then raise exception 'profile not found'; end if;

  v_completed := nullif(p.quality_benchmark->>'completed_at','')::timestamptz;
  v_hash := p.quality_benchmark->>'binding_hash';
  if not p.enabled then v_fail := array_append(v_fail, 'profile is disabled'); end if;
  if not p.paused then v_fail := array_append(v_fail, 'profile is already active'); end if;
  if coalesce((p.quality_benchmark->>'pass')::boolean,false) is not true then v_fail := array_append(v_fail, 'quality benchmark has not passed'); end if;
  if v_completed is null or v_completed < now() - interval '14 days' then
    v_fail := array_append(v_fail, 'benchmark pass is missing or older than 14 days; re-benchmark required');
  end if;
  if 'provider_current_tuition_validation' = any(p.allowed_task_classes) and coalesce(v_hash,'') !~ '^[0-9a-f]{64}$' then
    v_fail := array_append(v_fail, 'no qualified binding hash on record');
  end if;
  if not exists(select 1 from vault.secrets s where s.name = security.layer3_provider_credential_name(p.id)) then
    v_fail := array_append(v_fail, 'provider credential not configured');
  end if;
  select string_agg(o.code, ', ' order by o.code) into v_conflict
  from pipeline.layer3_model_profiles o
  where o.id <> p.id and o.enabled and not o.paused and o.allowed_task_classes && p.allowed_task_classes;
  if v_conflict is not null then v_fail := array_append(v_fail, ('another profile is already active for this task class: ' || v_conflict)); end if;

  v_checks := jsonb_build_object('benchmark_completed_at', v_completed, 'benchmark_pass', p.quality_benchmark->'pass',
    'binding_hash', v_hash, 'model_identifier', p.model_identifier, 'failed', to_jsonb(v_fail));

  if cardinality(v_fail) > 0 then
    insert into pipeline.layer3_profile_activation_events(profile_id, action, actor_id, reason, binding_hash, benchmark_run_id, checks)
    values (p.id, 'activation_refused', auth.uid(), btrim(p_reason), v_hash, p.quality_benchmark->>'run_id', v_checks);
    return jsonb_build_object('ok', false, 'profile_id', p.id, 'refused', to_jsonb(v_fail));
  end if;

  update pipeline.layer3_model_profiles
  set paused = false,
      last_validation_result = coalesce(last_validation_result,'{}'::jsonb) || jsonb_build_object(
        'activated_at', now(), 'activated_by', auth.uid(), 'activation_reason', btrim(p_reason), 'activated_binding_hash', v_hash),
      updated_at = now()
  where id = p.id;
  insert into pipeline.layer3_profile_activation_events(profile_id, action, actor_id, reason, binding_hash, benchmark_run_id, checks)
  values (p.id, 'activated', auth.uid(), btrim(p_reason), v_hash, p.quality_benchmark->>'run_id', v_checks);
  return jsonb_build_object('ok', true, 'profile_id', p.id, 'activated', true, 'binding_hash', v_hash);
end $$;

create or replace function security.layer3_profile_pause_impl(p_profile_id uuid, p_reason text)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','auth' as $$
declare p pipeline.layer3_model_profiles%rowtype;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required to pause a Layer 3 profile' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_reason,''))) < 5 then raise exception 'governance reason required'; end if;
  select * into p from pipeline.layer3_model_profiles where id = p_profile_id for update;
  if not found then raise exception 'profile not found'; end if;
  if not p.paused then
    update pipeline.layer3_model_profiles set paused = true,
      last_validation_result = coalesce(last_validation_result,'{}'::jsonb) || jsonb_build_object('paused_at', now(), 'paused_by', auth.uid(), 'pause_reason', btrim(p_reason)),
      updated_at = now() where id = p.id;
    insert into pipeline.layer3_profile_activation_events(profile_id, action, actor_id, reason, binding_hash, benchmark_run_id)
    values (p.id, 'paused', auth.uid(), btrim(p_reason), p.quality_benchmark->>'binding_hash', p.quality_benchmark->>'run_id');
  end if;
  return jsonb_build_object('ok', true, 'profile_id', p.id, 'paused', true);
end $$;

create or replace function public.layer3_profile_activate(p_profile_id uuid, p_reason text)
returns jsonb language sql set search_path to 'pg_catalog','security'
as $$ select security.layer3_profile_activate_impl(p_profile_id, p_reason) $$;
create or replace function public.layer3_profile_pause(p_profile_id uuid, p_reason text)
returns jsonb language sql set search_path to 'pg_catalog','security'
as $$ select security.layer3_profile_pause_impl(p_profile_id, p_reason) $$;
revoke all on function security.layer3_profile_activate_impl(uuid,text), security.layer3_profile_pause_impl(uuid,text),
  public.layer3_profile_activate(uuid,text), public.layer3_profile_pause(uuid,text) from public, anon;
grant execute on function security.layer3_profile_activate_impl(uuid,text), security.layer3_profile_pause_impl(uuid,text),
  public.layer3_profile_activate(uuid,text), public.layer3_profile_pause(uuid,text) to authenticated, service_role;

-- ========== 3. Close the ungoverned unpause path (setter may still pause/disable) ==========
create or replace function security.layer3_model_profile_set_state_impl(p_profile_id uuid, p_enabled boolean, p_paused boolean, p_reason text)
 returns jsonb language plpgsql security definer
 set search_path to 'pg_catalog', 'security', 'pipeline', 'auth'
as $function$
begin
  if auth.uid() is null or security.current_role_rank()<4 then raise exception 'administrator role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'governance reason required'; end if;
  if p_paused is false and exists(select 1 from pipeline.layer3_model_profiles where id=p_profile_id and paused) then
    raise exception 'unpausing a Layer 3 profile requires the governed activation gate (layer3_profile_activate)' using errcode='42501';
  end if;
  update pipeline.layer3_model_profiles set enabled=p_enabled,paused=p_paused,
    last_validation_result=coalesce(last_validation_result,'{}'::jsonb)||jsonb_build_object('state_change_reason',trim(p_reason),'state_changed_at',now(),'state_changed_by',auth.uid()),
    updated_at=now() where id=p_profile_id;
  if not found then raise exception 'profile not found'; end if;
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'enabled',p_enabled,'paused',p_paused);
end $function$;

-- ========== 4. Auto-pause on binding drift at execution ==========
create or replace function public.layer3_fail_interpretation_service(p_interpretation_id uuid, p_error text, p_external_call_count integer, p_call_latency_ms integer)
 returns void language plpgsql security definer
 set search_path to 'pg_catalog', 'pipeline'
as $function$
declare v_profile uuid; v_hash text; v_run text;
begin
  if p_external_call_count is not null and p_external_call_count<0 then raise exception 'invalid external call count'; end if;
  if p_call_latency_ms is not null and p_call_latency_ms<0 then raise exception 'invalid call latency'; end if;
  update pipeline.layer3_interpretations
  set status='provider_error',
      validator_result=jsonb_build_object('provider_error',left(coalesce(p_error,'unknown'),2000)),
      external_call_count=p_external_call_count,
      call_latency_ms=p_call_latency_ms,
      call_completed_at=now()
  where id=p_interpretation_id and status in ('reserved','calling');
  -- CF-247: a binding mismatch means the deployed code or profile no longer matches
  -- what was qualified. Execution already refuses; pause the profile so its state
  -- never shows "active" while it is refusing every item.
  if coalesce(p_error,'') ilike '%binding hash does not match%' then
    select profile_id into v_profile from pipeline.layer3_interpretations where id=p_interpretation_id;
    if v_profile is not null then
      update pipeline.layer3_model_profiles
      set paused=true,
          last_validation_result=coalesce(last_validation_result,'{}'::jsonb)||jsonb_build_object('auto_paused_at',now(),'auto_pause_reason','binding hash drift detected at execution'),
          updated_at=now()
      where id=v_profile and not paused
      returning quality_benchmark->>'binding_hash', quality_benchmark->>'run_id' into v_hash, v_run;
      if found then
        insert into pipeline.layer3_profile_activation_events(profile_id, action, reason, binding_hash, benchmark_run_id, checks)
        values (v_profile, 'auto_paused_binding_drift', 'binding hash drift detected at execution', v_hash, v_run,
                jsonb_build_object('interpretation_id', p_interpretation_id, 'error', left(p_error,500)));
      end if;
    end if;
  end if;
end $function$;

-- ========== 5. Deterministic Layer 3 tuition admission ==========
create or replace function security.layer3_tuition_admit_validated_v1(p_limit integer default 25)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','pipeline','catalogue','security','search','ref' as $$
declare
  v_caller text; r record; v_hold text; v_key text; v_min numeric; v_cand jsonb;
  v_amount numeric; v_cur text; v_basis text; v_year int; v_aud text; v_fee uuid;
  v_ex_amount numeric; v_ex_cur text;
  v_admitted int := 0; v_already int := 0; v_held int := 0; v_refresh jsonb; v_items jsonb := '[]'::jsonb;
begin
  v_caller := coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;

  for r in
    select w.id wid, w.entity_id course_id, w.evidence_id, w.interpretation_id,
           i.candidate_value cv, i.confidence, i.validator_result vr, i.aggregator_response_model model,
           p.deterministic_validators dv, c.course_code, e.source_id
    from pipeline.layer3_work_items w
    join pipeline.layer3_interpretations i on i.id = w.interpretation_id
    join pipeline.layer3_model_profiles p on p.id = i.profile_id
    left join catalogue.courses c on c.id = w.entity_id
    left join pipeline.evidence_artifacts e on e.id = w.evidence_id
    where w.task_class = 'provider_current_tuition_validation' and w.status = 'validated'
    order by w.completed_at nulls last, w.id
    limit least(greatest(coalesce(p_limit,25),1),100)
    for update of w skip locked
  loop
    v_hold := null; v_cand := r.cv;
    v_min := coalesce(nullif(r.dv->>'review_confidence_min','')::numeric, 0.9);
    v_amount := nullif(v_cand->>'amount','')::numeric;
    v_cur := upper(nullif(btrim(coalesce(v_cand->>'currency_code', v_cand->>'currency')),''));
    v_basis := nullif(btrim(v_cand->>'basis'),'');
    v_year := nullif(v_cand->>'fee_year','')::int;
    v_aud := lower(coalesce(nullif(btrim(v_cand->>'audience'),''),''));

    if v_cand is null or jsonb_typeof(v_cand) <> 'object' then v_hold := 'no candidate value';
    elsif coalesce((r.vr->>'valid')::boolean,false) is not true or coalesce((r.vr->>'candidate_bound')::boolean,false) is not true then v_hold := 'validator result is not valid and candidate-bound';
    elsif r.confidence is null or r.confidence < v_min then v_hold := format('confidence %s is below the admission threshold %s', r.confidence, v_min);
    elsif v_amount is null or v_amount <= 0 then v_hold := 'amount is not positive';
    elsif v_aud <> 'international' then v_hold := 'audience is not international';
    elsif r.dv ? 'allowed_currencies' and not (r.dv->'allowed_currencies' ? coalesce(v_cur,'')) then v_hold := format('currency %s is not allowed', v_cur);
    elsif r.dv ? 'allowed_basis' and not (r.dv->'allowed_basis' ? coalesce(v_basis,'')) then v_hold := format('basis %s is not allowed', v_basis);
    elsif r.dv ? 'amount_max' and v_amount > (r.dv->>'amount_max')::numeric then v_hold := 'amount is above the profile ceiling';
    elsif r.course_code is null then v_hold := 'course code unavailable';
    elsif r.source_id is null then v_hold := 'Evidence has no source';
    elsif not exists(select 1 from ref.currencies where code = v_cur) then v_hold := format('currency %s is not seeded', v_cur);
    end if;

    if v_hold is null then
      -- same fee key convention as the Layer 2 writer (svc_coursefacts_apply_record)
      v_key := lower(upper(btrim(r.course_code))||':'||v_aud||':'||coalesce(v_year::text,'current')||':'||coalesce(v_basis,'tuition'));
      v_fee := null;
      insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
      values (r.course_id,v_year,v_aud,'provider_current_tuition',v_amount,v_cur,v_basis,
              format('CF-247 Layer 3 admission; interpretation %s; model %s', r.interpretation_id, coalesce(r.model,'unknown')),
              r.source_id,r.evidence_id,r.confidence,null,v_key,'active',now(),now(),now())
      on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do nothing
      returning id into v_fee;
      if v_fee is null then
        select amount, currency_code into v_ex_amount, v_ex_cur from catalogue.course_fees
        where course_id = r.course_id and source_id = r.source_id and source_fee_key = v_key;
        if v_ex_amount = v_amount and btrim(v_ex_cur) = v_cur then
          update pipeline.layer3_work_items set status='admitted', completed_at=now(), updated_at=now(),
            last_error='admitted: identical fee already present' where id = r.wid;
          v_already := v_already + 1;
          v_items := v_items || jsonb_build_object('work_item_id', r.wid, 'result', 'already_present');
          continue;
        end if;
        v_hold := format('conflicts with existing fee %s %s for the same key', v_ex_amount, v_ex_cur);
      end if;
    end if;

    if v_hold is not null then
      update pipeline.layer3_work_items set status='admission_pending', updated_at=now(),
        last_error=left('admission held for human review: '||v_hold,500) where id = r.wid;
      v_held := v_held + 1;
      v_items := v_items || jsonb_build_object('work_item_id', r.wid, 'result', 'held', 'reason', v_hold);
      continue;
    end if;

    update pipeline.layer3_work_items set status='admitted', completed_at=now(), updated_at=now(), last_error=null where id = r.wid;
    v_admitted := v_admitted + 1;
    v_items := v_items || jsonb_build_object('work_item_id', r.wid, 'result', 'admitted', 'course_fee_id', v_fee, 'amount', v_amount, 'currency', v_cur, 'basis', v_basis);
  end loop;

  if v_admitted > 0 then v_refresh := search.refresh_course_enrichment_v1(true); end if;
  return jsonb_build_object('ok', true, 'admitted', v_admitted, 'already_present', v_already, 'held_for_review', v_held,
    'projection_refreshed', v_refresh is not null, 'items', v_items, 'change_control_ref', 'CF-CHG-20260915-247');
end $$;
revoke all on function security.layer3_tuition_admit_validated_v1(integer) from public, anon, authenticated;
grant execute on function security.layer3_tuition_admit_validated_v1(integer) to service_role;

-- ========== 6. Schedules — created SWITCHED OFF; enabled only after a supervised run ==========
-- Enqueue and dispatch do nothing unless a qualified profile is active (activation is the master switch).
select cron.schedule('layer3-tuition-enqueue',   '*/15 * * * *',     $$select public.layer3_enqueue_eligible_layer2_service(25)$$);
select cron.schedule('layer3-tuition-dispatch',  '5-59/10 * * * *',  $$select pipeline.svc_pilot_submit_nonce('layer3-work-dispatch', jsonb_build_object('limit',5,'worker','cron-layer3-dispatch'))$$);
select cron.schedule('layer3-tuition-admission', '8-59/15 * * * *',  $$select security.layer3_tuition_admit_validated_v1(25)$$);
select cron.alter_job(jobid, active := false) from cron.job
where jobname in ('layer3-tuition-enqueue','layer3-tuition-dispatch','layer3-tuition-admission');
