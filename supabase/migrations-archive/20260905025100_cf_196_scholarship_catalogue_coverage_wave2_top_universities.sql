-- CF-196 — Scholarship catalogue coverage wave 2: UNSW, UQ and UWA.
-- First-party, international-only catalogue registration. Evidence-first; no canonical publication.
do $$
declare
  r record; v_country uuid; v_source uuid; v_profile uuid; v_version uuid; v_cfg jsonb; v_base text; ap record;
begin
  select id into v_country from ref.countries where iso_alpha2::text='AU' limit 1;
  for r in select * from (values
    ('22657140-1cb0-4fa7-91df-90518ea8b35b'::uuid,'UNSW Sydney','https://www.unsw.edu.au/study/your-future/international-scholarships','International scholarships'),
    ('e55396d2-869a-46ef-9d17-841c7eab1313'::uuid,'The University of Queensland','https://scholarships.uq.edu.au/scholarships?type%5B160%5D=160','International scholarships'),
    ('9109fe0c-9f44-4e2d-a136-eb00dec24701'::uuid,'The University of Western Australia','https://www.uwa.edu.au/study/scholarships-and-fees/scholarships/international-scholarships','International scholarships')
  ) x(provider_id,provider_name,url,label)
  loop
    select id into v_source from pipeline.sources where provider_id=r.provider_id and source_type='scholarship_catalogue' and rtrim(lower(url),'/')=rtrim(lower(r.url),'/') order by created_at desc limit 1;
    if v_source is null then
      insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
      values('scholarship_catalogue',r.provider_id,v_country,r.url,r.label,100,'active',jsonb_build_object('authority','first_party','audience','international','qualified_at',now(),'change_control_ref','CF-196','qualification_basis','official first-party international scholarship catalogue verified 2026-09-05')) returning id into v_source;
    else
      update pipeline.sources set status='active',trust_rank=100,metadata=metadata||jsonb_build_object('authority','first_party','audience','international','qualified_at',now(),'change_control_ref','CF-196') where id=v_source;
    end if;
    select id,current_version_id into v_profile,v_version from pipeline.layer2_source_profiles where source_id=v_source and domain='scholarship' and acquisition_method='scholarship_catalogue' order by created_at desc limit 1;
    if v_profile is null then
      insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
      values(v_source,'au-scholarship-entry-'||replace(r.provider_id::text,'-','')||'-'||substr(md5(r.url),1,8),'scholarship','scholarship_catalogue','scholarship','first_party',true,false,'CourseFinder PIM',168,'weekly; international catalogue; hash-gated detail fanout') returning id,current_version_id into v_profile,v_version;
    else
      update pipeline.layer2_source_profiles set enabled=true,paused=false,freshness_sla_hours=168,schedule_text='weekly; international catalogue; hash-gated detail fanout',updated_at=now() where id=v_profile;
    end if;
    if v_version is null then
      v_base:=regexp_replace(r.url,'^(https?://[^/]+).*','\1');
      v_cfg:=jsonb_build_object('retry',jsonb_build_object('backoff','exponential','max_attempts',2),'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship catalogue acquisition'),'schedule','weekly; international catalogue; hash-gated detail fanout','base_domain',v_base,'concurrency',1,'url_patterns',jsonb_build_array(r.url),'discovery_url',r.url,'robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),'max_payload_mb',20,'timeout_seconds',60,'evidence_required',true,'acquisition_method','scholarship_catalogue','allowed_mime_types',jsonb_build_array('text/html','application/json'),'change_control_ref','CF-196','international_only',true,'reuse_shared_fetch',true,'target_entity_type','scholarship','freshness_sla_hours',168,'content_change_policy','hash before enumeration; no direct canonical mutation','rate_limit_per_minute',20,'shared_fetch_ttl_hours',24);
      insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
      values(v_profile,1,v_cfg,encode(extensions.digest(v_cfg::text,'sha256'),'hex'),'valid',jsonb_build_object('first_party_verified',true,'international_only',true,'provider_name',r.provider_name),'CF-196') returning id into v_version;
      update pipeline.layer2_source_profiles set current_version_id=v_version,updated_at=now() where id=v_profile;
    end if;
    for ap in select id,provider_key from pipeline.layer2_acquisition_providers where enabled and provider_key in('direct-http','parsebot','firecrawl','zenrows') loop
      if not exists(select 1 from pipeline.layer2_profile_provider_routes pr where pr.profile_id=v_profile and pr.acquisition_provider_id=ap.id) then
        insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
        values(v_profile,ap.id,case ap.provider_key when 'direct-http' then 10 when 'parsebot' then 20 when 'firecrawl' then 40 else 50 end,true,'{}'::jsonb,'{}'::jsonb,jsonb_build_object('capture_raw',true,'capture_html',true,'capture_screenshot_on_failure',ap.provider_key='firecrawl','capture_screenshot_on_extraction_failure',ap.provider_key='firecrawl'),'["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,'CF-196');
      end if;
    end loop;
  end loop;
end $$;
comment on function public.scholarship_scope_acquisition_service(uuid,text,text,text,uuid) is 'Governed Scholarship acquisition service. CF-196 expands qualified AU international catalogue coverage to UNSW, UQ and UWA; acquisition remains Evidence-first and publication is never automatic.';
