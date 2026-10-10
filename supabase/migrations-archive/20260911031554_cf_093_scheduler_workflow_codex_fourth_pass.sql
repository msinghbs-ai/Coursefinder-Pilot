begin;

-- CF-CHG-20260910-093 Codex fourth-pass correction.
-- Keep preview-token ownership actor-bound, but deduplicate successful exact-scope
-- dispatches across all operators. Also reject an empty start result atomically so a
-- profile paused/disabled between the live preview and start cannot consume a token
-- as a successful no-op. Preserve all Layer 1-4, Evidence, Search/Publication, rank,
-- ACL, AU-only and acquisition-only boundaries.

create or replace function security.scheduler_workflow_run_now_v2_browser_bridge(
  p_preview_token uuid,
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
  v_preview pipeline.jobs%rowtype;
  v_prior pipeline.jobs%rowtype;
  v_live_preview jsonb;
  v_result jsonb;
  v_scope_key text;
  v_work integer:=0;
  v_live_work integer:=0;
  v_invalid_profiles integer:=0;
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
  if v_scope='country' and p_scope_id is not null then
    raise exception 'country scope must not include a scope id' using errcode='22023';
  end if;
  if v_mode <> 'acquisition_only' then
    raise exception 'processing mode is not yet qualified for generic Scheduled Tasks execution' using errcode='22023';
  end if;
  if p_preview_token is null then
    raise exception 'valid preview token required' using errcode='22023';
  end if;
  v_scope_key:=v_workflow||'|'||upper(p_country_code)||'|'||v_scope||'|'||coalesce(p_scope_id::text,'country')||'|'||v_mode;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_scope_key,0));
  select * into v_preview
  from pipeline.jobs j
  where j.id=p_preview_token
    and j.job_type='scheduler_workflow_preview'
    and j.requested_by=v_actor
    and j.created_at >= now()-interval '15 minutes'
  for update;
  if not found then raise exception 'preview token is missing, expired or belongs to another actor' using errcode='22023'; end if;
  if coalesce(v_preview.payload->>'workflow_key','')<>v_workflow
     or coalesce(v_preview.payload->>'country_code','')<>upper(p_country_code)
     or coalesce(v_preview.payload->>'scope_type','')<>v_scope
     or coalesce(v_preview.payload->>'scope_id','')<>coalesce(p_scope_id::text,'')
     or coalesce(v_preview.payload->>'processing_mode','')<>v_mode then
    raise exception 'preview token does not match the exact requested workflow target' using errcode='22023';
  end if;
  if v_preview.payload ? 'dispatch_result' then
    return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',true,'result',v_preview.payload->'dispatch_result');
  end if;
  v_work:=coalesce((v_preview.result->>'queueable_count')::integer,0)+coalesce((v_preview.result->>'needs_discovery_count')::integer,0);
  if v_work<=0 or coalesce((v_preview.result->>'executable')::boolean,false)=false then
    raise exception 'previewed scope has no executable Layer 2 work' using errcode='22023';
  end if;
  select count(distinct sc.profile_id)::integer into v_invalid_profiles
  from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc
  join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
  left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
  where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid';
  if v_invalid_profiles>0 then
    raise exception 'Layer 2 profile qualification changed after preview; preview again after requalification' using errcode='22023';
  end if;
  v_live_preview:=public.layer2_operator_scope_service(v_actor,'preview',upper(p_country_code),v_scope,p_scope_id);
  v_live_work:=coalesce((v_live_preview->>'queueable_count')::integer,0)+coalesce((v_live_preview->>'needs_discovery_count')::integer,0);
  if v_live_work<=0 then
    raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023';
  end if;
  select * into v_prior
  from pipeline.jobs j
  where j.id<>p_preview_token
    and j.job_type='scheduler_workflow_preview'
    and nullif(j.payload->>'consumed_at','') is not null
    and (j.payload->>'consumed_at')::timestamptz >= now()-interval '10 minutes'
    and coalesce(j.payload->>'workflow_key','')=v_workflow
    and coalesce(j.payload->>'country_code','')=upper(p_country_code)
    and coalesce(j.payload->>'scope_type','')=v_scope
    and coalesce(j.payload->>'scope_id','')=coalesce(p_scope_id::text,'')
    and coalesce(j.payload->>'processing_mode','')=v_mode
    and j.payload ? 'dispatch_result'
  order by (j.payload->>'consumed_at')::timestamptz desc
  limit 1;
  if found then
    update pipeline.jobs set payload=payload||jsonb_build_object('consumed_at',now(),'dispatch_result',v_prior.payload->'dispatch_result','deduplicated_against_preview',v_prior.id,'governance_reason',trim(p_reason)) where id=p_preview_token;
    return jsonb_build_object('ok',true,'preview_token',p_preview_token,'existing_recent_dispatch',true,'deduplicated_against_preview',v_prior.id,'result',v_prior.payload->'dispatch_result');
  end if;
  v_result:=public.layer2_operator_scope_service(v_actor,'start',upper(p_country_code),v_scope,p_scope_id);
  if jsonb_typeof(v_result->'profiles')<>'array' or jsonb_array_length(coalesce(v_result->'profiles','[]'::jsonb))=0 then
    raise exception 'Layer 2 runnable scope changed during dispatch; preview again before dispatch' using errcode='22023';
  end if;
  update pipeline.jobs
  set payload=payload||jsonb_build_object('consumed_at',now(),'dispatch_result',coalesce(v_result,'{}'::jsonb),'governance_reason',trim(p_reason)),
      result=result||jsonb_build_object('dispatch_result',coalesce(v_result,'{}'::jsonb))
  where id=p_preview_token;
  return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',false,'result',v_result);
end
$function$;
revoke all on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) from public,anon;
grant execute on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) to authenticated;
commit;
