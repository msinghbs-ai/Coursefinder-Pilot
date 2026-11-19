do $$
declare
  r record;
  v_source uuid;
  v_profile uuid;
  v_version uuid;
  v_config jsonb;
  v_hash text;
  v_country uuid;
begin
  select id into v_country from ref.countries where upper(iso_alpha2::text)='AU' limit 1;
  for r in
    select distinct on (t.provider_id) t.provider_id,p.canonical_name,t.first_party_catalogue_url
    from pipeline.scholarship_acquisition_trace t
    join catalogue.providers p on p.id=t.provider_id
    where t.first_party_catalogue_url is not null
      and t.verification_status='verified_first_party'
    order by t.provider_id,t.updated_at desc
  loop
    select id into v_source from pipeline.sources
    where provider_id=r.provider_id and source_type='scholarship_catalogue' and url=r.first_party_catalogue_url
    order by trust_rank desc nulls last,created_at desc limit 1;
    if v_source is null then
      insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
      values('scholarship_catalogue',r.provider_id,v_country,r.first_party_catalogue_url,r.canonical_name||' Scholarships — official first-party catalogue',100,'active',jsonb_build_object('authority','first_party','discovery_role','authoritative_catalogue','change_control_ref','CF-CHG-20260904-120'))
      returning id into v_source;
    end if;

    select id into v_profile from pipeline.layer2_source_profiles
    where source_id=v_source and domain='scholarship' and acquisition_method='scholarship_catalogue'
    order by created_at limit 1;
    if v_profile is null then
      insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
      values(v_source,'au-scholarship-entry-'||replace(r.provider_id::text,'-','')||'-cf120','scholarship','scholarship_catalogue','scholarship','first_party',true,false,'PIM/Data Operations',168,'weekly; accelerate around application deadlines or changed hash')
      returning id into v_profile;
    else
      update pipeline.layer2_source_profiles set enabled=true,paused=false,authority_class='first_party',freshness_sla_hours=168,updated_at=now() where id=v_profile;
    end if;

    v_config:=jsonb_build_object(
      'retry',jsonb_build_object('backoff','exponential','max_attempts',2),
      'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 scholarship acquisition'),
      'schedule','weekly; accelerate around application deadlines or changed hash',
      'base_domain',regexp_replace(r.first_party_catalogue_url,'^(https?://[^/]+).*$','\\1'),
      'concurrency',1,
      'url_patterns',jsonb_build_array(r.first_party_catalogue_url),
      'discovery_url',r.first_party_catalogue_url,
      'robots_policy','respect',
      'fanout_domains',jsonb_build_array('scholarship','provider_asset'),
      'max_payload_mb',20,
      'timeout_seconds',60,
      'evidence_required',true,
      'acquisition_method','scholarship_catalogue',
      'allowed_mime_types',jsonb_build_array('text/html','application/json'),
      'change_control_ref','CF-CHG-20260904-120',
      'reuse_shared_fetch',true,
      'target_entity_type','scholarship',
      'freshness_sla_hours',168,
      'content_change_policy','hash before downstream extraction; no direct canonical mutation',
      'rate_limit_per_minute',20,
      'shared_fetch_ttl_hours',24
    );
    v_hash:=encode(extensions.digest(convert_to(v_config::text,'UTF8'),'sha256'),'hex');
    select id into v_version from pipeline.layer2_source_profile_versions where profile_id=v_profile and configuration_hash=v_hash limit 1;
    if v_version is null then
      insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
      values(v_profile,coalesce((select max(version_no)+1 from pipeline.layer2_source_profile_versions where profile_id=v_profile),1),v_config,v_hash,'valid',jsonb_build_object('valid',true,'errors',jsonb_build_array(),'validated_at',now()),'CF-CHG-20260904-120')
      returning id into v_version;
    end if;
    update pipeline.layer2_source_profiles set current_version_id=v_version,updated_at=now() where id=v_profile;
    v_source:=null;v_profile:=null;v_version:=null;
  end loop;
end $$;
