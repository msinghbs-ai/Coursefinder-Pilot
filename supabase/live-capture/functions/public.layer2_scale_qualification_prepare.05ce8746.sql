CREATE OR REPLACE FUNCTION public.layer2_scale_qualification_prepare(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare
  v_run pipeline.layer2_scale_qualification_runs%rowtype;
  r record;
  v_source uuid;
  v_profile uuid;
  v_version uuid;
  v_cfg jsonb;
  v_hash text;
  v_validation jsonb;
  v_country text;
  v_profiles jsonb:='[]'::jsonb;
  v_ready integer:=0;
  v_limited integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_run from pipeline.layer2_scale_qualification_runs where id=p_run_id for update;
  if not found then raise exception 'qualification run not found' using errcode='22023'; end if;
  if v_run.status in ('completed','cancelled') then
    return jsonb_build_object('ok',true,'status',v_run.status,'run_id',p_run_id);
  end if;

  select iso_alpha2::text into v_country from ref.countries where id=v_run.country_id;

  for r in
    select distinct qi.provider_id,p.canonical_name,p.website,p.country_id
    from pipeline.layer2_scale_qualification_items qi
    join catalogue.providers p on p.id=qi.provider_id
    where qi.run_id=p_run_id
      and qi.status in ('selected','qualifying')
    order by p.canonical_name
  loop
    if r.website is null
       or btrim(r.website)=''
       or r.website !~* '^https?://[^[:space:]]+$'
       or lower(r.website) like 'https://https://%'
       or lower(r.website) like 'http://http://%'
    then
      update pipeline.layer2_scale_qualification_items
      set status='source_limited',
          outcome=coalesce(outcome,'{}'::jsonb)||jsonb_build_object(
            'stage','source_seed_qualification',
            'outcome','source_limited',
            'reason','missing_or_invalid_layer1_provider_website',
            'layer1_provider_website',r.website,
            'handoff','layer4_source_resolution',
            'canonical_mutation_authorised',false,
            'search_mutation_authorised',false,
            'publication_mutation_authorised',false
          )
      where run_id=p_run_id and provider_id=r.provider_id;
      v_limited:=v_limited+1;
      continue;
    end if;

    select lp.id,s.id into v_profile,v_source
    from pipeline.layer2_source_profiles lp
    join pipeline.sources s on s.id=lp.source_id
    where s.provider_id=r.provider_id
      and lp.authority_class='qualification_candidate'
      and lp.domain='course_facts'
    order by lp.created_at desc
    limit 1;

    if v_profile is null then
      insert into pipeline.sources(
        source_type,provider_id,country_id,url,label,trust_rank,status,metadata
      ) values(
        'web_catalogue',r.provider_id,r.country_id,btrim(r.website),
        'A11 qualification — '||r.canonical_name,60,'active',
        jsonb_build_object(
          'layer',2,
          'qualification_candidate',true,
          'qualification_run_id',p_run_id,
          'change_control_ref','CF-CHG-20260830-048',
          'canonical_mutation_authorised',false
        )
      ) returning id into v_source;

      insert into pipeline.layer2_source_profiles(
        source_id,profile_key,domain,acquisition_method,target_entity_type,
        authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text
      ) values(
        v_source,
        'qualification-'||lower(v_country)||'-'||left(replace(r.provider_id::text,'-',''),16),
        'course_facts','website','course_fact','qualification_candidate',
        true,false,'PIM/Data Operations',168,'qualification_only'
      ) returning id into v_profile;

      v_cfg:=jsonb_build_object(
        'acquisition_method','website',
        'base_domain',btrim(r.website),
        'discovery_url',btrim(r.website),
        'url_patterns',jsonb_build_array(btrim(r.website)),
        'inclusion_rules',jsonb_build_array(),
        'exclusion_rules',jsonb_build_array(),
        'headers',jsonb_build_object('user_agent','CourseFinder Layer2 Qualification/1.0'),
        'authentication',jsonb_build_object('mechanism','none'),
        'rate_limit_per_minute',30,
        'concurrency',1,
        'timeout_seconds',30,
        'retry',jsonb_build_object('max_attempts',2,'backoff','exponential'),
        'robots_policy','respect',
        'allowed_mime_types',jsonb_build_array('text/html','application/json'),
        'max_payload_mb',10,
        'parser_profile','generic-first-party-source-qualification-v1',
        'target_entity_type','course_fact',
        'mapping_strategy','qualification_only_no_canonical_mutation',
        'stable_identifier_strategy','layer1_provider_id_plus_first_party_host',
        'regulatory_code_extraction',jsonb_build_object('cricos',null,'nzqa',null),
        'evidence_required',true,
        'freshness_sla_hours',168,
        'schedule','qualification_only',
        'content_change_policy','evidence_only_never_direct_canonical_mutation',
        'source_authority','first_party_candidate_unqualified',
        'operational_owner','PIM/Data Operations',
        'change_control_ref','CF-CHG-20260830-048'
      );
      v_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');
      v_validation:=security.layer2_validate_profile_config(v_cfg);

      insert into pipeline.layer2_source_profile_versions(
        profile_id,version_no,configuration,configuration_hash,
        validation_status,validation_result,change_control_ref,uat_ref
      ) values(
        v_profile,1,v_cfg,v_hash,
        case when (v_validation->>'valid')::boolean then 'valid' else 'invalid' end,
        v_validation,'CF-CHG-20260830-048','M2.4.2-A11-source-qualification'
      ) returning id into v_version;

      update pipeline.layer2_source_profiles set current_version_id=v_version where id=v_profile;

      insert into pipeline.layer2_profile_provider_routes(
        profile_id,acquisition_provider_id,priority,enabled,
        required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref
      )
      select
        v_profile,ap.id,
        case ap.provider_key
          when 'firecrawl' then 5
          when 'direct-http' then 20
          when 'scrape-do' then 80
          when 'scraperapi' then 90
          when 'zenrows' then 100
          else 120
        end,
        case when ap.provider_key in ('firecrawl','direct-http') then true else false end,'{}'::jsonb,'{}'::jsonb,
        '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb,
        '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
        'CF-CHG-20260830-048'
      from pipeline.layer2_acquisition_providers ap
      where ap.enabled
      on conflict do nothing;
    end if;

    update pipeline.layer2_scale_qualification_items
    set status='qualifying',
        outcome=coalesce(outcome,'{}'::jsonb)||jsonb_build_object(
          'stage','source_seed_qualification',
          'qualification_profile_id',v_profile,
          'qualification_source_id',v_source,
          'layer1_provider_website',r.website,
          'canonical_mutation_authorised',false,
          'search_mutation_authorised',false,
          'publication_mutation_authorised',false
        )
    where run_id=p_run_id and provider_id=r.provider_id and status in ('selected','qualifying');

    v_profiles:=v_profiles||jsonb_build_array(jsonb_build_object(
      'provider_id',r.provider_id,'provider_name',r.canonical_name,
      'website',r.website,'profile_id',v_profile,'source_id',v_source
    ));
    v_ready:=v_ready+1;
  end loop;

  update pipeline.layer2_scale_qualification_runs
  set status=case when v_ready>0 then 'running' else 'completed' end,
      result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
        'stage','source_seed_qualification',
        'providers_ready_for_acquisition',v_ready,
        'providers_source_limited',v_limited,
        'identity_safety_required',true,
        'canonical_mutation_authorised',false,
        'search_mutation_authorised',false,
        'publication_mutation_authorised',false
      ),
      completed_at=case when v_ready=0 then now() else null end
  where id=p_run_id;

  return jsonb_build_object(
    'ok',true,'run_id',p_run_id,
    'providers_ready_for_acquisition',v_ready,
    'providers_source_limited',v_limited,
    'profiles',v_profiles,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end $function$
