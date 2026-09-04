-- CF-157 — International Scholarship detail batch dispatch
-- Extends Scholarship scope execution so jobs may carry an explicit governed detail profile + URL.
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
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_job
  from pipeline.jobs
  where id=p_job_id and job_type='scholarship_scope_acquisition' and domain='scholarship';
  if not found then return null; end if;

  begin
    v_requested_profile:=nullif(v_job.payload->>'profile_id','')::uuid;
  exception when others then
    v_requested_profile:=null;
  end;
  v_requested_url:=nullif(v_job.payload->>'target_url','');

  if v_requested_profile is not null then
    select sp.id profile_id,sp.current_version_id,sp.profile_key,sp.source_id,
           coalesce(v_requested_url,s.url) target_url,s.trust_rank
      into v_profile
    from pipeline.layer2_source_profiles sp
    join pipeline.sources s on s.id=sp.source_id
    where sp.id=v_requested_profile
      and s.provider_id=v_job.provider_id
      and s.status='active'
      and sp.domain='scholarship'
      and sp.enabled and not sp.paused
      and sp.current_version_id is not null
    limit 1;
  else
    select sp.id profile_id,sp.current_version_id,sp.profile_key,sp.source_id,s.url target_url,s.trust_rank
      into v_profile
    from pipeline.layer2_source_profiles sp
    join pipeline.sources s on s.id=sp.source_id
    where s.provider_id=v_job.provider_id
      and s.status='active'
      and sp.domain='scholarship'
      and sp.acquisition_method='scholarship_catalogue'
      and sp.enabled and not sp.paused
      and sp.current_version_id is not null
    order by case when sp.profile_key like 'au-scholarship-entry-%' then 0 else 1 end,
             s.trust_rank desc nulls last,sp.updated_at desc
    limit 1;
  end if;

  return jsonb_build_object(
    'job_id',v_job.id,'provider_id',v_job.provider_id,'status',v_job.status,
    'payload',coalesce(v_job.payload,'{}'::jsonb),
    'profile_id',v_profile.profile_id,'profile_version_id',v_profile.current_version_id,
    'profile_key',v_profile.profile_key,'source_id',v_profile.source_id,'target_url',v_profile.target_url
  );
end
$function$;

revoke all on function public.scholarship_scope_job_execution_context(uuid) from public,anon,authenticated;
grant execute on function public.scholarship_scope_job_execution_context(uuid) to service_role;

-- Runtime population of detail sources/profiles/jobs is intentionally idempotent by provider+URL and candidate/job checks.
do $block$
declare
  r record;
  v_source uuid;
  v_profile uuid;
  v_version uuid;
  v_key text;
  v_cfg jsonb;
  v_actor uuid:='63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid;
  route_rec record;
begin
  for r in
    select c.id candidate_id,s.provider_id,p.country_id,
           coalesce(nullif(c.detail_target_url,''),nullif(c.scholarship_url,'')) target_url,
           coalesce(nullif(c.observed_title,''),'International scholarship detail') observed_title
    from pipeline.layer2_scholarship_discovery_candidates c
    join pipeline.sources s on s.id=c.source_id
    join catalogue.providers p on p.id=s.provider_id
    where c.classification='detail_ready'
      and s.provider_id in (
        '982fb12f-41ed-4358-9d1b-d7422b3089dd'::uuid,
        'f34fae5e-b5b9-4c82-a6ca-44bf0803020e'::uuid,
        'fac03540-a412-4c76-a5ab-cd338d7760db'::uuid,
        '6f5cb7f7-7c70-4c06-970f-f368c3a786e2'::uuid,
        'c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid
      )
      and coalesce(nullif(c.detail_target_url,''),nullif(c.scholarship_url,'')) is not null
      and not exists (
        select 1 from pipeline.scholarship_source_records sr
        where sr.source_record_url=coalesce(nullif(c.detail_target_url,''),nullif(c.scholarship_url,''))
          and sr.status in ('captured','applied')
      )
      and not exists (
        select 1 from pipeline.jobs j
        where j.domain='scholarship'
          and j.payload->>'candidate_id'=c.id::text
          and j.status in ('queued','running','succeeded')
      )
    order by s.provider_id,c.created_at,c.id
    limit 40
  loop
    select id into v_source
    from pipeline.sources
    where provider_id=r.provider_id and source_type='scholarship_detail' and url=r.target_url
    order by created_at desc limit 1;

    if v_source is null then
      insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
      values('scholarship_detail',r.provider_id,r.country_id,r.target_url,left(r.observed_title,180),100,'active',
             jsonb_build_object('authority','first_party','change_control_ref','CF-157','candidate_id',r.candidate_id))
      returning id into v_source;
    end if;

    select id,current_version_id into v_profile,v_version
    from pipeline.layer2_source_profiles
    where source_id=v_source and domain='scholarship' and acquisition_method='website'
    order by created_at desc limit 1;

    if v_profile is null then
      v_key:='au-scholarship-detail-'||replace(r.provider_id::text,'-','')||'-'||substr(md5(r.target_url),1,10);
      insert into pipeline.layer2_source_profiles(
        source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,
        enabled,paused,operational_owner,freshness_sla_hours,schedule_text
      ) values(
        v_source,v_key,'scholarship','website','scholarship','first_party',true,false,
        'CourseFinder PIM',168,'weekly; international-only governed detail acquisition'
      ) returning id into v_profile;
    end if;

    select current_version_id into v_version from pipeline.layer2_source_profiles where id=v_profile;
    if v_version is null then
      v_cfg:=jsonb_build_object(
        'retry',jsonb_build_object('backoff','exponential','max_attempts',2),
        'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),
        'schedule','weekly; international-only governed detail acquisition',
        'base_domain',regexp_replace(r.target_url,'^(https?://[^/]+).*','\\1'),
        'concurrency',1,'url_patterns',jsonb_build_array(r.target_url),'discovery_url',r.target_url,
        'robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),
        'max_payload_mb',20,'timeout_seconds',60,'evidence_required',true,
        'acquisition_method','website','allowed_mime_types',jsonb_build_array('text/html','application/json'),
        'change_control_ref','CF-157','reuse_shared_fetch',true,'target_entity_type','scholarship',
        'freshness_sla_hours',168,'content_change_policy','hash before extraction; no direct publication',
        'rate_limit_per_minute',20,'shared_fetch_ttl_hours',24
      );
      insert into pipeline.layer2_source_profile_versions(
        profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref,created_by
      ) values(
        v_profile,1,v_cfg,encode(extensions.digest(v_cfg::text,'sha256'),'hex'),'valid',
        jsonb_build_object('international_only',true,'candidate_id',r.candidate_id),'CF-157',v_actor
      ) returning id into v_version;
      update pipeline.layer2_source_profiles set current_version_id=v_version,updated_at=now() where id=v_profile;
    end if;

    for route_rec in
      select * from (values
        ('126845fa-0a16-4151-a3e9-1d3864374c1b'::uuid,10,false),
        ('1f5b36f5-4e8b-4f30-a0c2-0769b4ce8266'::uuid,20,false),
        ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88'::uuid,40,true),
        ('53c4b0b2-23da-40f9-a41f-e8d4f543b3f7'::uuid,50,false)
      ) x(acq_id,priority,screenshot)
    loop
      if not exists(select 1 from pipeline.layer2_profile_provider_routes where profile_id=v_profile and acquisition_provider_id=route_rec.acq_id) then
        insert into pipeline.layer2_profile_provider_routes(
          profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,
          evidence_policy,fallback_on,change_control_ref
        ) values(
          v_profile,route_rec.acq_id,route_rec.priority,true,'{}'::jsonb,'{}'::jsonb,
          jsonb_build_object('capture_raw',true,'capture_html',true,
            'capture_screenshot_on_failure',route_rec.screenshot,
            'capture_screenshot_on_extraction_failure',route_rec.screenshot),
          '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,'CF-157'
        );
      end if;
    end loop;

    insert into pipeline.jobs(job_type,domain,provider_id,status,requested_by,payload)
    values(
      'scholarship_scope_acquisition','scholarship',r.provider_id,'queued',v_actor,
      jsonb_build_object(
        'profile_id',v_profile,'target_url',r.target_url,'candidate_id',r.candidate_id,
        'acquisition_stage','first_party_detail','international_only',true,
        'publication_authorised',false,'change_control_ref','CF-157'
      )
    );
  end loop;
end
$block$;
