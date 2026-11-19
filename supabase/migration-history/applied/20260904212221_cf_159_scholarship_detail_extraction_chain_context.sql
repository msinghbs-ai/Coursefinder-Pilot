create or replace function public.scholarship_detail_extraction_context(p_job_id uuid,p_evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $function$
declare
  v_job record;
  v_e record;
  v_candidate uuid;
  v_classification text;
  v_url text;
  v_eligible boolean:=false;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_job from pipeline.jobs
  where id=p_job_id and domain='scholarship' and job_type='scholarship_scope_acquisition';
  if not found then return null; end if;

  select id,evidence_type,source_url,metadata into v_e
  from pipeline.evidence_artifacts where id=p_evidence_id;
  if not found then return null; end if;

  begin v_candidate:=nullif(v_job.payload->>'candidate_id','')::uuid; exception when others then v_candidate:=null; end;
  if v_candidate is not null then
    select classification,coalesce(nullif(detail_target_url,''),nullif(scholarship_url,''))
      into v_classification,v_url
    from pipeline.layer2_scholarship_discovery_candidates where id=v_candidate;
  end if;

  v_eligible:=coalesce(v_classification,'')='detail_ready'
    and coalesce(v_url,v_e.source_url,'') !~* '/search\?'
    and coalesce(v_url,v_e.source_url,'') !~* '[?&](query|collection|form|num_ranks|f\.)=';

  return jsonb_build_object(
    'job_id',v_job.id,
    'candidate_id',v_candidate,
    'classification',v_classification,
    'eligible',v_eligible,
    'evidence_id',v_e.id,
    'evidence_type',v_e.evidence_type,
    'source_url',v_e.source_url,
    'attempt_id',v_e.metadata->>'attempt_id',
    'reason',case when v_eligible then 'detail_ready' else 'candidate_not_current_detail_ready_or_filter_page' end
  );
end
$function$;
revoke all on function public.scholarship_detail_extraction_context(uuid,uuid) from public,anon,authenticated;
grant execute on function public.scholarship_detail_extraction_context(uuid,uuid) to service_role;

-- Include existing result in execution context so extraction-only backfill jobs can reuse captured Evidence.
create or replace function public.scholarship_scope_job_execution_context(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue'
as $function$
declare
  v_job record;
  v_profile record;
  v_requested_profile uuid;
  v_requested_url text;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into v_job from pipeline.jobs where id=p_job_id and job_type='scholarship_scope_acquisition' and domain='scholarship';
  if not found then return null; end if;
  begin v_requested_profile:=nullif(v_job.payload->>'profile_id','')::uuid; exception when others then v_requested_profile:=null; end;
  v_requested_url:=nullif(v_job.payload->>'target_url','');
  if v_requested_profile is not null then
    select sp.id profile_id,sp.current_version_id,sp.profile_key,sp.source_id,coalesce(v_requested_url,s.url) target_url,s.trust_rank into v_profile
    from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
    where sp.id=v_requested_profile and s.provider_id=v_job.provider_id and s.status='active' and sp.domain='scholarship' and sp.enabled and not sp.paused and sp.current_version_id is not null limit 1;
  else
    select sp.id profile_id,sp.current_version_id,sp.profile_key,sp.source_id,s.url target_url,s.trust_rank into v_profile
    from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
    where s.provider_id=v_job.provider_id and s.status='active' and sp.domain='scholarship' and sp.acquisition_method='scholarship_catalogue' and sp.enabled and not sp.paused and sp.current_version_id is not null
    order by case when sp.profile_key like 'au-scholarship-entry-%' then 0 else 1 end,s.trust_rank desc nulls last,sp.updated_at desc limit 1;
  end if;
  return jsonb_build_object('job_id',v_job.id,'provider_id',v_job.provider_id,'status',v_job.status,'payload',coalesce(v_job.payload,'{}'::jsonb),'result',coalesce(v_job.result,'{}'::jsonb),'profile_id',v_profile.profile_id,'profile_version_id',v_profile.current_version_id,'profile_key',v_profile.profile_key,'source_id',v_profile.source_id,'target_url',v_profile.target_url);
end
$function$;
revoke all on function public.scholarship_scope_job_execution_context(uuid) from public,anon,authenticated;
grant execute on function public.scholarship_scope_job_execution_context(uuid) to service_role;

-- Backfill child jobs reusing existing raw Evidence; no re-scrape required.
insert into pipeline.jobs(job_type,domain,provider_id,status,requested_by,payload,result)
select 'scholarship_scope_acquisition','scholarship',j.provider_id,'queued',j.requested_by,
       jsonb_build_object(
         'profile_id',j.payload->>'profile_id','target_url',j.payload->>'target_url','candidate_id',j.payload->>'candidate_id',
         'acquisition_stage','first_party_detail_extraction','international_only',true,'extract_only',true,
         'source_job_id',j.id,'source_evidence_id',j.result->>'evidence_id','publication_authorised',false,'change_control_ref','CF-159'
       ),
       jsonb_build_object('source_evidence_id',j.result->>'evidence_id','source_job_id',j.id)
from pipeline.jobs j
where j.domain='scholarship' and j.job_type='scholarship_scope_acquisition'
  and j.payload->>'change_control_ref'='CF-157' and j.status='succeeded'
  and nullif(j.result->>'evidence_id','') is not null
  and not exists(select 1 from pipeline.jobs x where x.payload->>'source_job_id'=j.id::text and x.payload->>'change_control_ref'='CF-159');
