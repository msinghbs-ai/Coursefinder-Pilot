begin;

-- CF-CHG-20260910-093 — safe target-builder slice.
-- Browser surface is limited to the already-governed Layer 2 course_facts scope service.
-- Unsupported automatic L3/L4 and Evidence-reprocess modes are deliberately not executable here.

create or replace function security.scheduler_workflow_scope_options_v1_browser_bridge(
  p_country_code text default null,
  p_kind text default 'country',
  p_state_id uuid default null,
  p_query text default null,
  p_limit integer default 10,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_kind text:=lower(coalesce(nullif(trim(p_kind),''),'country'));
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if v_kind='country' then
    return public.layer2_scope_countries_service(v_actor);
  elsif v_kind in ('state','university') then
    return public.layer2_scope_options_page_service(v_actor,p_country_code,v_kind,p_state_id,p_query,p_limit,p_offset);
  end if;
  raise exception 'unsupported scope option kind' using errcode='22023';
end
$function$;

create or replace function public.scheduler_workflow_scope_options_v1(
  p_country_code text default null,
  p_kind text default 'country',
  p_state_id uuid default null,
  p_query text default null,
  p_limit integer default 10,
  p_offset integer default 0
) returns jsonb
language sql
stable
security invoker
set search_path=''
as $function$
  select security.scheduler_workflow_scope_options_v1_browser_bridge(p_country_code,p_kind,p_state_id,p_query,p_limit,p_offset)
$function$;

create or replace function security.scheduler_workflow_preview_v1_browser_bridge(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_workflow text:=lower(coalesce(trim(p_workflow_key),''));
  v_scope text:=lower(coalesce(trim(p_scope_type),''));
  v_result jsonb;
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if v_workflow <> 'course_facts_l2' then
    raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023';
  end if;
  if upper(coalesce(trim(p_country_code),'')) <> 'AU' then
    raise exception 'only AU Layer 2 Course Facts is currently authorised for this builder' using errcode='22023';
  end if;
  if v_scope not in ('country','state','university') then
    raise exception 'unsupported scope type' using errcode='22023';
  end if;
  if v_scope in ('state','university') and p_scope_id is null then
    raise exception 'scope id required' using errcode='22023';
  end if;

  v_result:=public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'workflow_key','course_facts_l2',
    'workflow_label','Course Facts enrichment',
    'processing_modes',jsonb_build_array(
      jsonb_build_object('key','acquisition_only','label','Acquisition + deterministic Layer 2','enabled',true),
      jsonb_build_object('key','automatic_governed_pipeline','label','Automatic governed pipeline','enabled',false,'reason','Conditional Layer 3/L4 orchestration is not yet qualified for generic Scheduled Tasks execution.'),
      jsonb_build_object('key','reprocess_governed_evidence','label','Reprocess governed Evidence','enabled',false,'reason','Use the governed Layer 3 workspace until an Evidence/profile-specific scheduler contract is accepted.')
    ),
    'schedule_supported',v_scope='university',
    'schedule_reason',case when v_scope='university' then 'University scope can resolve to an existing qualified Layer 2 source profile; schedule creation remains a separate governed action.' else 'Country/state schedules are not advertised because the current Layer 2 scheduler dispatches profile-wide and cannot enforce a multi-profile scope policy.' end
  );
end
$function$;

create or replace function public.scheduler_workflow_preview_v1(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language sql
security invoker
set search_path=''
as $function$
  select security.scheduler_workflow_preview_v1_browser_bridge(p_workflow_key,p_country_code,p_scope_type,p_scope_id)
$function$;

create or replace function security.scheduler_workflow_run_now_v1_browser_bridge(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid,
  p_processing_mode text,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_workflow text:=lower(coalesce(trim(p_workflow_key),''));
  v_scope text:=lower(coalesce(trim(p_scope_type),''));
  v_mode text:=lower(coalesce(trim(p_processing_mode),''));
  v_result jsonb;
  v_job uuid;
begin
  if v_actor is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'governance reason required' using errcode='22023';
  end if;
  if v_workflow <> 'course_facts_l2' or upper(coalesce(trim(p_country_code),'')) <> 'AU' then
    raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023';
  end if;
  if v_scope not in ('country','state','university') then
    raise exception 'unsupported scope type' using errcode='22023';
  end if;
  if v_scope in ('state','university') and p_scope_id is null then
    raise exception 'scope id required' using errcode='22023';
  end if;
  if v_mode <> 'acquisition_only' then
    raise exception 'processing mode is not yet qualified for generic Scheduled Tasks execution' using errcode='22023';
  end if;

  v_result:=public.layer2_operator_scope_service(v_actor,'start',upper(p_country_code),v_scope,p_scope_id);

  insert into pipeline.jobs(job_type,domain,status,requested_by,started_at,completed_at,payload,result)
  values(
    'scheduler_workflow_run','course_facts','completed',v_actor,now(),now(),
    jsonb_build_object('workflow_key',v_workflow,'country_code',upper(p_country_code),'scope_type',v_scope,'scope_id',p_scope_id,'processing_mode',v_mode,'governance_reason',trim(p_reason),'change_control_ref','CF-CHG-20260910-093'),
    coalesce(v_result,'{}'::jsonb)
  ) returning id into v_job;

  return jsonb_build_object('ok',true,'job_id',v_job,'workflow_key',v_workflow,'processing_mode',v_mode,'result',v_result);
end
$function$;

create or replace function public.scheduler_workflow_run_now_v1(
  p_workflow_key text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid,
  p_processing_mode text,
  p_reason text
) returns jsonb
language sql
security invoker
set search_path=''
as $function$
  select security.scheduler_workflow_run_now_v1_browser_bridge(p_workflow_key,p_country_code,p_scope_type,p_scope_id,p_processing_mode,p_reason)
$function$;

revoke all on function security.scheduler_workflow_scope_options_v1_browser_bridge(text,text,uuid,text,integer,integer) from public,anon,authenticated;
revoke all on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) from public,anon,authenticated;
revoke all on function security.scheduler_workflow_run_now_v1_browser_bridge(text,text,text,uuid,text,text) from public,anon,authenticated;

revoke all on function public.scheduler_workflow_scope_options_v1(text,text,uuid,text,integer,integer) from public,anon;
revoke all on function public.scheduler_workflow_preview_v1(text,text,text,uuid) from public,anon;
revoke all on function public.scheduler_workflow_run_now_v1(text,text,text,uuid,text,text) from public,anon;
grant execute on function public.scheduler_workflow_scope_options_v1(text,text,uuid,text,integer,integer) to authenticated;
grant execute on function public.scheduler_workflow_preview_v1(text,text,text,uuid) to authenticated;
grant execute on function public.scheduler_workflow_run_now_v1(text,text,text,uuid,text,text) to authenticated;

commit;
