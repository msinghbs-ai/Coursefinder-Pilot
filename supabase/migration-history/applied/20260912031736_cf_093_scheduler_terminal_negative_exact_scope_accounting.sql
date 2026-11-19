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
set search_path to ''
as $function$
declare
 v_actor uuid:=auth.uid(); v_workflow text:=lower(coalesce(trim(p_workflow_key),'')); v_scope text:=lower(coalesce(trim(p_scope_type),'')); v_mode text:=lower(coalesce(trim(p_processing_mode),''));
 v_preview pipeline.jobs%rowtype; v_prior pipeline.jobs%rowtype; v_live_snapshot jsonb; v_post_snapshot jsonb; v_result jsonb; v_scope_key text; v_invalid_profiles integer:=0; v_policy_gaps integer:=0; v_oversized_profiles integer:=0; v_route_gaps integer:=0; v_discovery_config_gaps integer:=0;
 v_preview_profiles uuid[]:='{}'::uuid[]; v_live_profiles uuid[]:='{}'::uuid[]; v_started_profiles uuid[]:='{}'::uuid[]; v_preview_fingerprint text; v_live_fingerprint text; v_dedupe_minutes integer:=10;
begin
 if v_actor is null or security.current_role_rank() < 4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'governance reason required' using errcode='22023'; end if;
 if v_workflow <> 'course_facts_l2' or upper(coalesce(trim(p_country_code),'')) <> 'AU' then raise exception 'workflow is not executable from Scheduled Tasks' using errcode='22023'; end if;
 if v_scope not in ('country','state','university') then raise exception 'unsupported scope type' using errcode='22023'; end if;
 if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
 if v_scope='country' and p_scope_id is not null then raise exception 'country scope must not include a scope id' using errcode='22023'; end if;
 if v_mode <> 'acquisition_only' then raise exception 'processing mode is not yet qualified for generic Scheduled Tasks execution' using errcode='22023'; end if;
 if p_preview_token is null then raise exception 'valid preview token required' using errcode='22023'; end if;
 v_scope_key:=v_workflow||'|'||upper(p_country_code)||'|'||v_scope||'|'||coalesce(p_scope_id::text,'country')||'|'||v_mode; perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_scope_key,0));
 select * into v_preview from pipeline.jobs j where j.id=p_preview_token and j.job_type='scheduler_workflow_preview' and j.requested_by=v_actor and j.created_at>=now()-interval '15 minutes' for update;
 if not found then raise exception 'preview token is missing, expired or belongs to another actor' using errcode='22023'; end if;
 if coalesce(v_preview.payload->>'workflow_key','')<>v_workflow or coalesce(v_preview.payload->>'country_code','')<>upper(p_country_code) or coalesce(v_preview.payload->>'scope_type','')<>v_scope or coalesce(v_preview.payload->>'scope_id','')<>coalesce(p_scope_id::text,'') or coalesce(v_preview.payload->>'processing_mode','')<>v_mode then raise exception 'preview token does not match the exact requested workflow target' using errcode='22023'; end if;
 if v_preview.payload ? 'dispatch_result' then return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',true,'result',v_preview.payload->'dispatch_result'); end if;
 select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_preview_profiles from jsonb_array_elements_text(coalesce(v_preview.result->'profile_ids','[]'::jsonb)) x; v_preview_fingerprint:=nullif(v_preview.result->>'scope_fingerprint','');
 if cardinality(v_preview_profiles)=0 or v_preview_fingerprint is null then raise exception 'preview token predates exact runnable-scope binding; preview again before dispatch' using errcode='22023'; end if;
 if coalesce((v_preview.result->>'executable')::boolean,false)=false then raise exception 'previewed scope has no executable Layer 2 work' using errcode='22023'; end if;
 v_live_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id); select coalesce(array_agg((x)::uuid order by (x)::uuid),'{}'::uuid[]) into v_live_profiles from jsonb_array_elements_text(coalesce(v_live_snapshot->'profile_ids','[]'::jsonb)) x; v_live_fingerprint:=v_live_snapshot->>'scope_fingerprint';
 if v_live_profiles<>v_preview_profiles or coalesce(v_live_fingerprint,'')<>v_preview_fingerprint then raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023'; end if;
 if coalesce((v_live_snapshot->>'queueable_count')::integer,0)+coalesce((v_live_snapshot->>'needs_discovery_count')::integer,0)<=0 then raise exception 'Layer 2 runnable scope changed after preview; preview again before dispatch' using errcode='22023'; end if;
 select count(distinct sc.profile_id)::integer into v_invalid_profiles from public.layer2_scope_courses(upper(p_country_code),v_scope,p_scope_id) sc join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id where lp.current_version_id is null or pv.id is null or pv.validation_status<>'valid'; if v_invalid_profiles>0 then raise exception 'Layer 2 profile qualification changed after preview; preview again after requalification' using errcode='22023'; end if;
 v_policy_gaps:=security.scheduler_workflow_execution_policy_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_policy_gaps>0 then raise exception 'Layer 2 execution policy qualification changed after preview; configure the execution policy and preview again' using errcode='22023'; end if;
 v_oversized_profiles:=security.scheduler_workflow_oversized_profile_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_oversized_profiles>0 then raise exception 'Layer 2 scope exceeds the current 1,000-course per-profile dispatch contract; narrow the target and preview again' using errcode='22023'; end if;
 v_route_gaps:=security.scheduler_workflow_route_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_route_gaps>0 then raise exception 'Layer 2 acquisition route qualification changed after preview; restore a runtime-usable governed route and preview again' using errcode='22023'; end if;
 v_discovery_config_gaps:=security.scheduler_workflow_discovery_config_gap_count_v1(upper(p_country_code),v_scope,p_scope_id); if v_discovery_config_gaps>0 then raise exception 'Layer 2 source/discovery URL qualification changed after preview; correct the worker-valid HTTPS target/allowlist and preview again' using errcode='22023'; end if;
 select greatest(10,coalesce(max(ep.stale_after_minutes),10))::integer into v_dedupe_minutes from pipeline.layer2_execution_policies ep where ep.profile_id=any(v_live_profiles) and ep.enabled;
 select * into v_prior from pipeline.jobs j where j.id<>p_preview_token and j.job_type='scheduler_workflow_preview' and nullif(j.payload->>'consumed_at','') is not null and (j.payload->>'consumed_at')::timestamptz>=now()-make_interval(mins=>v_dedupe_minutes) and coalesce(j.payload->>'workflow_key','')=v_workflow and coalesce(j.payload->>'country_code','')=upper(p_country_code) and coalesce(j.payload->>'scope_type','')=v_scope and coalesce(j.payload->>'scope_id','')=coalesce(p_scope_id::text,'') and coalesce(j.payload->>'processing_mode','')=v_mode and coalesce(j.result->>'scope_fingerprint','')=v_live_fingerprint and coalesce(j.result->'profile_ids','[]'::jsonb)=to_jsonb(v_live_profiles) and j.payload ? 'dispatch_result' order by (j.payload->>'consumed_at')::timestamptz desc limit 1;
 if found then update pipeline.jobs set payload=payload||jsonb_build_object('deduplicated_at',now(),'dispatch_result',v_prior.payload->'dispatch_result','deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'governance_reason',trim(p_reason)) where id=p_preview_token; return jsonb_build_object('ok',true,'preview_token',p_preview_token,'existing_recent_dispatch',true,'deduplicated_against_preview',v_prior.id,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_prior.payload->'dispatch_result'); end if;
 perform set_config('coursefinder.scheduler_preview_token',p_preview_token::text,true);
 v_result:=public.layer2_operator_scope_service(v_actor,'start',upper(p_country_code),v_scope,p_scope_id);
 select coalesce(array_agg(distinct (e->>'profile_id')::uuid order by (e->>'profile_id')::uuid),'{}'::uuid[]) into v_started_profiles from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e where nullif(e->>'profile_id','') is not null;
 if v_started_profiles<>v_live_profiles then raise exception 'Layer 2 runnable profile set changed during dispatch; transaction rolled back, preview again before dispatch' using errcode='22023'; end if;
 if exists(
   select 1
   from jsonb_array_elements(coalesce(v_result->'profiles','[]'::jsonb)) e
   where coalesce(e->>'status','') not in ('started','discovery_started')
      or (
        e->>'status'='started'
        and (
          nullif(e->>'batch_id','') is null
          or nullif(e->>'dispatch_request_id','') is null
          or coalesce((e->>'target_count')::integer,-1) + coalesce((e->>'fresh_terminal_negative_count')::integer,0) <> coalesce((e->>'requested_count')::integer,-2)
        )
      )
      or (e->>'status'='discovery_started' and nullif(e->>'request_id','') is null)
 ) then raise exception 'Layer 2 dispatch did not start the exact previewed work for every profile; transaction rolled back, resolve active/incompatible work and preview again' using errcode='22023'; end if;
 v_post_snapshot:=security.scheduler_workflow_scope_snapshot_v2(upper(p_country_code),v_scope,p_scope_id); if coalesce(v_post_snapshot->>'scope_fingerprint','')<>v_preview_fingerprint or coalesce(v_post_snapshot->'profile_ids','[]'::jsonb)<>to_jsonb(v_live_profiles) then raise exception 'Layer 2 runnable scope changed during dispatch; transaction rolled back, preview again' using errcode='40001'; end if;
 update pipeline.jobs set payload=payload||jsonb_build_object('consumed_at',now(),'dispatch_result',coalesce(v_result,'{}'::jsonb),'governance_reason',trim(p_reason),'dedupe_horizon_minutes',v_dedupe_minutes),result=result||jsonb_build_object('dispatch_result',coalesce(v_result,'{}'::jsonb)) where id=p_preview_token;
 return jsonb_build_object('ok',true,'preview_token',p_preview_token,'idempotent_replay',false,'dedupe_horizon_minutes',v_dedupe_minutes,'result',v_result);
end
$function$;

revoke all on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) to service_role;
