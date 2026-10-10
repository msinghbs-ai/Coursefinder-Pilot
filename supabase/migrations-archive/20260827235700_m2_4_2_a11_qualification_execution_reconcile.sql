-- M2.4.2 A11 — reconcile deployed qualification execution, strict pattern controls and cross-layer handoff.
-- Generated from live Pilot function definitions after deployed POC validation.

begin;

alter table pipeline.layer2_scale_qualification_items
  drop constraint if exists layer2_scale_qualification_items_status_check;
alter table pipeline.layer2_scale_qualification_items
  add constraint layer2_scale_qualification_items_status_check
  check (status in ('selected','qualifying','source_pattern_candidate','profile_qualified','qualified_l2','layer3_required','layer4_required','source_limited','blocked'));

CREATE OR REPLACE FUNCTION public.layer2_scale_cross_layer_handoff(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref'
AS $function$
declare
  v_l3 integer:=0;
  v_l4 integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if not exists(select 1 from pipeline.layer2_scale_qualification_runs where id=p_run_id) then
    raise exception 'qualification run not found' using errcode='22023';
  end if;

  with targets as (
    select distinct
      qi.provider_id,
      qi.evidence_id,
      s.id source_id,
      lp.id source_profile_id,
      co.iso_alpha2::text country_code
    from pipeline.layer2_scale_qualification_items qi
    join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
    join ref.countries co on co.id=qr.country_id
    left join pipeline.sources s on s.provider_id=qi.provider_id
      and coalesce((s.metadata->>'qualification_candidate')::boolean,false)
    left join pipeline.layer2_source_profiles lp on lp.source_id=s.id
      and lp.authority_class='qualification_candidate'
    where qi.run_id=p_run_id
      and qi.status='layer3_required'
      and qi.evidence_id is not null
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      evidence_id,layer3_profile_id,revalidation_ref,reason,trigger_type,status,
      requested_by,change_control_ref,schedule_error
    )
    select
      3,t.country_code,t.source_id,t.source_profile_id,'provider',t.provider_id,
      t.evidence_id,null,'A11-SOURCE-PATTERN:'||p_run_id::text,
      'Interpret first-party Course discovery/source pattern from governed Layer 2 Evidence; do not infer or change Layer 1 identity. Candidate pattern must return to Layer 2 strict control validation before profile promotion.',
      'manual_governed','blocked',null,'CF-CHG-20260827-044',
      'blocked_pending_dedicated_source_pattern_layer3_profile_benchmark'
    from targets t
    where not exists(
      select 1
      from pipeline.refresh_requests rr
      where rr.requested_layer=3
        and rr.entity_type='provider'
        and rr.entity_id=t.provider_id
        and rr.evidence_id=t.evidence_id
        and rr.revalidation_ref='A11-SOURCE-PATTERN:'||p_run_id::text
    )
    returning 1
  )
  select count(*) into v_l3 from ins;

  with targets as (
    select distinct
      qi.provider_id,
      co.iso_alpha2::text country_code,
      coalesce(qi.outcome->>'reason','missing_or_invalid_first_party_source_seed') reason
    from pipeline.layer2_scale_qualification_items qi
    join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
    join ref.countries co on co.id=qr.country_id
    where qi.run_id=p_run_id
      and qi.status='source_limited'
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,entity_type,entity_id,
      reason,trigger_type,status,requested_by,change_control_ref,schedule_error
    )
    select
      4,t.country_code,'provider',t.provider_id,
      'Resolve/verify missing or invalid first-party Provider Course source seed from Layer 1 before Layer 2 qualification. Reason: '||t.reason,
      'manual_governed','queued',null,'CF-CHG-20260827-044',
      'provider_source_resolution_required'
    from targets t
    where not exists(
      select 1
      from pipeline.refresh_requests rr
      where rr.requested_layer=4
        and rr.entity_type='provider'
        and rr.entity_id=t.provider_id
        and rr.change_control_ref='CF-CHG-20260827-044'
        and rr.status in ('queued','running','blocked')
    )
    returning 1
  )
  select count(*) into v_l4 from ins;

  update pipeline.layer2_scale_qualification_runs
  set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
    'cross_layer_handoff_at',now(),
    'layer3_source_pattern_requests_created',v_l3,
    'layer3_execution_state','blocked_pending_dedicated_profile_benchmark',
    'layer4_source_resolution_requests_created',v_l4,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  )
  where id=p_run_id;

  return jsonb_build_object(
    'ok',true,'run_id',p_run_id,
    'layer3_source_pattern_requests_created',v_l3,
    'layer3_execution_state','blocked_pending_dedicated_profile_benchmark',
    'layer4_source_resolution_requests_created',v_l4,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.layer2_scale_pattern_reconcile(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue'
AS $function$
declare
  r record;
  v_version uuid;
  v_ids uuid[];
  v_terminal integer;
  v_selected integer;
  v_profile uuid;
  v_provider_result jsonb;
  v_results jsonb:='[]'::jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  for r in
    select distinct qi.provider_id,
      nullif(qi.outcome->>'pattern_dispatch_version_id','')::uuid version_id
    from pipeline.layer2_scale_qualification_items qi
    where qi.run_id=p_run_id
      and qi.status='source_pattern_candidate'
      and nullif(qi.outcome->>'pattern_dispatch_version_id','') is not null
  loop
    v_version:=r.version_id;
    select array_agg((x)::uuid)
    into v_ids
    from jsonb_array_elements_text((
      select qi.outcome->'control_course_ids'
      from pipeline.layer2_scale_qualification_items qi
      where qi.run_id=p_run_id and qi.provider_id=r.provider_id
      limit 1
    )) x;

    select count(distinct dc.course_id),
           count(distinct dc.course_id) filter(where dc.selected=true)
    into v_terminal,v_selected
    from pipeline.layer2_course_discovery_candidates dc
    where dc.source_profile_version_id=v_version
      and dc.course_id=any(v_ids)
      and dc.status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found');

    if v_terminal<coalesce(array_length(v_ids,1),0) then
      continue;
    end if;

    select lp.id into v_profile
    from pipeline.layer2_source_profiles lp
    join pipeline.sources s on s.id=lp.source_id
    where s.provider_id=r.provider_id
      and lp.current_version_id=v_version
      and lp.authority_class='qualification_candidate'
    limit 1;

    if v_selected=coalesce(array_length(v_ids,1),0) and v_selected>=3 then
      update pipeline.layer2_source_profiles
      set authority_class='first_party_qualified',updated_at=now()
      where id=v_profile;

      update pipeline.sources
      set metadata=metadata||jsonb_build_object(
        'qualification_status','first_party_pattern_qualified',
        'qualification_run_id',p_run_id,
        'qualification_profile_version_id',v_version,
        'identity_controls_verified',v_selected,
        'qualified_at',now(),
        'canonical_mutation_authorised',false
      ),updated_at=now()
      where id=(select source_id from pipeline.layer2_source_profiles where id=v_profile);

      update pipeline.layer2_scale_qualification_items
      set status='profile_qualified',
          outcome=outcome||jsonb_build_object(
            'provider_pattern_qualified',true,
            'identity_controls_verified',v_selected,
            'identity_controls_required',array_length(v_ids,1),
            'qualified_profile_id',v_profile,
            'qualified_profile_version_id',v_version,
            'next_step','full_scope_discovery_wave',
            'canonical_mutation_authorised',false,
            'search_mutation_authorised',false,
            'publication_mutation_authorised',false
          )
      where run_id=p_run_id and provider_id=r.provider_id and status='source_pattern_candidate';
      v_provider_result:=jsonb_build_object('provider_id',r.provider_id,'status','profile_qualified','controls_verified',v_selected);
    else
      update pipeline.layer2_scale_qualification_items
      set status='layer3_required',
          outcome=outcome||jsonb_build_object(
            'provider_pattern_qualified',false,
            'identity_controls_verified',v_selected,
            'identity_controls_required',array_length(v_ids,1),
            'handoff','layer3_source_pattern_interpretation',
            'canonical_mutation_authorised',false,
            'search_mutation_authorised',false,
            'publication_mutation_authorised',false
          )
      where run_id=p_run_id and provider_id=r.provider_id and status='source_pattern_candidate';
      v_provider_result:=jsonb_build_object('provider_id',r.provider_id,'status','layer3_required','controls_verified',v_selected);
    end if;
    v_results:=v_results||jsonb_build_array(v_provider_result);
  end loop;

  update pipeline.layer2_scale_qualification_runs
  set result_summary=result_summary||jsonb_build_object(
    'pattern_control_reconciled_at',now(),
    'profile_qualified_providers',(
      select count(distinct provider_id) from pipeline.layer2_scale_qualification_items
      where run_id=p_run_id and status='profile_qualified'
    ),
    'layer3_required_providers',(
      select count(distinct provider_id) from pipeline.layer2_scale_qualification_items
      where run_id=p_run_id and status='layer3_required'
    ),
    'source_limited_providers',(
      select count(distinct provider_id) from pipeline.layer2_scale_qualification_items
      where run_id=p_run_id and status='source_limited'
    )
  )
  where id=p_run_id;

  return jsonb_build_object('ok',true,'run_id',p_run_id,'reconciled',v_results);
end $function$
;

CREATE OR REPLACE FUNCTION public.layer2_scale_qualification_context(p_run_id uuid, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref', 'public'
AS $function$
  select jsonb_build_object(
    'run_id',r.id,
    'country_code',co.iso_alpha2::text,
    'providers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'provider_id',x.provider_id,
        'provider_name',x.canonical_name,
        'website',x.website,
        'profile_id',x.profile_id,
        'items',x.items
      ) order by x.canonical_name)
      from (
        select p.id provider_id,p.canonical_name,p.website,lp.id profile_id,
          jsonb_agg(jsonb_build_object(
            'item_id',qi.id,'course_id',qi.course_id,'sample_rank',qi.sample_rank,
            'course_title',c.canonical_title,'course_code',c.course_code
          ) order by qi.sample_rank) items
        from pipeline.layer2_scale_qualification_items qi
        join catalogue.providers p on p.id=qi.provider_id
        join catalogue.courses c on c.id=qi.course_id
        join pipeline.sources s on s.provider_id=p.id
        join pipeline.layer2_source_profiles lp on lp.source_id=s.id
          and lp.authority_class='qualification_candidate'
          and lp.domain='course_facts'
          and lp.enabled and not lp.paused
        where qi.run_id=r.id and qi.status='qualifying'
        group by p.id,p.canonical_name,p.website,lp.id
        order by p.canonical_name
        limit least(greatest(coalesce(p_limit,5),1),10)
      ) x
    ),'[]'::jsonb)
  )
  from pipeline.layer2_scale_qualification_runs r
  join ref.countries co on co.id=r.country_id
  where r.id=p_run_id
$function$
;

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
          'change_control_ref','CF-CHG-20260827-044',
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
        'change_control_ref','CF-CHG-20260827-044'
      );
      v_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');
      v_validation:=security.layer2_validate_profile_config(v_cfg);

      insert into pipeline.layer2_source_profile_versions(
        profile_id,version_no,configuration,configuration_hash,
        validation_status,validation_result,change_control_ref,uat_ref
      ) values(
        v_profile,1,v_cfg,v_hash,
        case when (v_validation->>'valid')::boolean then 'valid' else 'invalid' end,
        v_validation,'CF-CHG-20260827-044','M2.4.2-A11-source-qualification'
      ) returning id into v_version;

      update pipeline.layer2_source_profiles set current_version_id=v_version where id=v_profile;

      insert into pipeline.layer2_profile_provider_routes(
        profile_id,acquisition_provider_id,priority,enabled,
        required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref
      )
      select
        v_profile,ap.id,
        case ap.provider_key
          when 'direct-http' then 10
          when 'firecrawl' then 20
          when 'scrape-do' then 30
          when 'scraperapi' then 40
          when 'zenrows' then 50
          else 100
        end,
        true,'{}'::jsonb,'{}'::jsonb,
        '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb,
        '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
        'CF-CHG-20260827-044'
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
;

CREATE OR REPLACE FUNCTION public.layer2_scale_qualification_provider_finish(p_run_id uuid, p_provider_id uuid, p_evidence_id uuid, p_status text, p_outcome jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare
  v_status text:=lower(coalesce(nullif(trim(p_status),''),'blocked'));
  v_remaining integer;
  v_summary jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if v_status not in ('source_pattern_candidate','source_limited','blocked','layer3_required','layer4_required') then
    raise exception 'invalid qualification provider status' using errcode='22023';
  end if;

  update pipeline.layer2_scale_qualification_items
  set status=v_status,
      evidence_id=coalesce(p_evidence_id,evidence_id),
      outcome=coalesce(outcome,'{}'::jsonb)||coalesce(p_outcome,'{}'::jsonb)||
        jsonb_build_object(
          'canonical_mutation_authorised',false,
          'search_mutation_authorised',false,
          'publication_mutation_authorised',false
        )
  where run_id=p_run_id and provider_id=p_provider_id and status='qualifying';

  select count(*) into v_remaining
  from pipeline.layer2_scale_qualification_items
  where run_id=p_run_id and status in ('selected','qualifying');

  if v_remaining=0 then
    select jsonb_build_object(
      'source_pattern_candidate',count(distinct provider_id) filter(where status='source_pattern_candidate'),
      'source_limited',count(distinct provider_id) filter(where status='source_limited'),
      'layer3_required',count(distinct provider_id) filter(where status='layer3_required'),
      'layer4_required',count(distinct provider_id) filter(where status='layer4_required'),
      'blocked',count(distinct provider_id) filter(where status='blocked'),
      'course_samples',count(*),
      'evidence_backed_samples',count(*) filter(where evidence_id is not null)
    ) into v_summary
    from pipeline.layer2_scale_qualification_items
    where run_id=p_run_id;

    update pipeline.layer2_scale_qualification_runs
    set status=case when coalesce((v_summary->>'blocked')::integer,0)>0 then 'partial' else 'completed' end,
        completed_at=now(),
        result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
          'source_seed_results',v_summary,
          'next_step','course_page_source_pattern_validation',
          'canonical_mutation_authorised',false,
          'search_mutation_authorised',false,
          'publication_mutation_authorised',false
        )
    where id=p_run_id;
  end if;

  return jsonb_build_object('ok',true,'run_id',p_run_id,'provider_id',p_provider_id,'status',v_status,'remaining',v_remaining);
end $function$
;

CREATE OR REPLACE FUNCTION security.layer2_scale_pattern_dispatch(p_run_id uuid, p_limit integer DEFAULT 2)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue', 'security'
AS $function$
declare
  r record;
  v_url text;
  v_cfg jsonb;
  v_hash text;
  v_validation jsonb;
  v_version uuid;
  v_version_no integer;
  v_ids uuid[];
  v_dispatch jsonb;
  v_results jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  for r in
    select distinct p.id provider_id,p.canonical_name,lp.id profile_id,lp.current_version_id
    from pipeline.layer2_scale_qualification_items qi
    join catalogue.providers p on p.id=qi.provider_id
    join pipeline.sources s on s.provider_id=p.id
    join pipeline.layer2_source_profiles lp on lp.source_id=s.id
      and lp.authority_class='qualification_candidate'
      and lp.domain='course_facts'
      and lp.enabled and not lp.paused
    where qi.run_id=p_run_id
      and qi.status='source_pattern_candidate'
      and coalesce(qi.outcome->>'pattern_dispatch_version_id','')=''
    order by p.canonical_name
    limit least(greatest(coalesce(p_limit,2),1),5)
  loop
    select e->>'url'
    into v_url
    from pipeline.layer2_scale_qualification_items qi
    cross join lateral jsonb_array_elements(coalesce(qi.outcome->'signal_examples','[]'::jsonb)) e
    where qi.run_id=p_run_id and qi.provider_id=r.provider_id
    order by (
      case when lower(coalesce(e->>'text','')||' '||coalesce(e->>'url','')) ~ '(find|explore).*(course|degree|qualification|program|programme)' then 100 else 0 end +
      case when lower(coalesce(e->>'url','')) ~ '/courses/?([?#].*)?$' then 90 else 0 end +
      case when lower(coalesce(e->>'url','')) ~ '/qualifications/?([?#].*)?$' then 80 else 0 end +
      case when lower(coalesce(e->>'text','')||' '||coalesce(e->>'url','')) ~ '(course|degree|qualification|program|programme)' then 50 else 0 end +
      case when lower(coalesce(e->>'url','')) ~ '/study/?([?#].*)?$' then 30 else 0 end -
      case when lower(coalesce(e->>'text','')||' '||coalesce(e->>'url','')) ~ '(scholarship|library|apply|support|cost|exam|graduation)' then 30 else 0 end
    ) desc, length(e->>'url'), e->>'url'
    limit 1;

    if v_url is null then
      update pipeline.layer2_scale_qualification_items
      set status='layer3_required',
          outcome=outcome||jsonb_build_object(
            'stage','course_page_source_pattern_validation',
            'reason','no_deterministic_catalogue_candidate',
            'handoff','layer3_source_pattern_interpretation'
          )
      where run_id=p_run_id and provider_id=r.provider_id and status='source_pattern_candidate';
      continue;
    end if;

    select configuration into v_cfg
    from pipeline.layer2_source_profile_versions where id=r.current_version_id;

    v_cfg:=jsonb_set(
      jsonb_set(
        v_cfg,
        '{discovery_strategy}',
        jsonb_build_object(
          'type','catalogue_link_scan',
          'catalogue_url',v_url,
          'course_acquisition_budget_ms',60000,
          'qualification_control_sample_size',3
        ),
        true
      ),
      '{url_patterns}',
      coalesce(v_cfg->'url_patterns','[]'::jsonb)||jsonb_build_array(v_url),
      true
    );
    v_cfg:=jsonb_set(v_cfg,'{source_authority}',to_jsonb('first_party_candidate_under_control_validation'::text),true);
    v_cfg:=jsonb_set(v_cfg,'{change_control_ref}',to_jsonb('CF-CHG-20260827-044'::text),true);
    v_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');
    v_validation:=security.layer2_validate_profile_config(v_cfg);
    if not coalesce((v_validation->>'valid')::boolean,false) then
      update pipeline.layer2_scale_qualification_items
      set status='blocked',
          outcome=outcome||jsonb_build_object(
            'stage','course_page_source_pattern_validation',
            'reason','generated_pattern_profile_invalid',
            'validation',v_validation
          )
      where run_id=p_run_id and provider_id=r.provider_id and status='source_pattern_candidate';
      continue;
    end if;

    select coalesce(max(version_no),0)+1 into v_version_no
    from pipeline.layer2_source_profile_versions where profile_id=r.profile_id;

    insert into pipeline.layer2_source_profile_versions(
      profile_id,version_no,configuration,configuration_hash,
      validation_status,validation_result,change_control_ref,uat_ref
    ) values(
      r.profile_id,v_version_no,v_cfg,v_hash,'valid',v_validation,
      'CF-CHG-20260827-044','M2.4.2-A11-pattern-control'
    ) returning id into v_version;

    update pipeline.layer2_source_profiles
    set current_version_id=v_version,updated_at=now()
    where id=r.profile_id;

    select array_agg(course_id order by sample_rank)
    into v_ids
    from (
      select course_id,sample_rank
      from pipeline.layer2_scale_qualification_items
      where run_id=p_run_id and provider_id=r.provider_id
      order by sample_rank
      limit 3
    ) x;

    update pipeline.layer2_scale_qualification_items
    set outcome=outcome||jsonb_build_object(
      'stage','course_page_source_pattern_validation',
      'catalogue_candidate_url',v_url,
      'pattern_dispatch_version_id',v_version,
      'control_course_ids',to_jsonb(v_ids),
      'identity_control_required','3_of_3',
      'canonical_mutation_authorised',false,
      'search_mutation_authorised',false,
      'publication_mutation_authorised',false
    )
    where run_id=p_run_id and provider_id=r.provider_id and status='source_pattern_candidate';

    v_dispatch:=security.layer2_discovery_scope_dispatch_v2(
      r.profile_id,v_ids,3,null,v_ids
    );

    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'provider_id',r.provider_id,
      'provider_name',r.canonical_name,
      'profile_id',r.profile_id,
      'profile_version_id',v_version,
      'catalogue_candidate_url',v_url,
      'control_course_ids',to_jsonb(v_ids),
      'request_id',v_dispatch->'request_id'
    ));
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'ok',true,'run_id',p_run_id,'dispatched',v_count,'providers',v_results,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end $function$
;

CREATE OR REPLACE FUNCTION security.layer2_scale_qualification_dispatch(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security'
AS $function$
declare v_prepared jsonb; v_req bigint;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  v_prepared:=public.layer2_scale_qualification_prepare(p_run_id);
  if coalesce((v_prepared->>'providers_ready_for_acquisition')::integer,0)=0 then
    return v_prepared||jsonb_build_object('dispatch_status','nothing_to_dispatch');
  end if;
  v_req:=pipeline.svc_pilot_submit_nonce(
    'layer2-scale-qualify-scheduled',
    jsonb_build_object('run_id',p_run_id,'limit',5)
  );
  return v_prepared||jsonb_build_object('dispatch_status','dispatched','request_id',v_req);
end $function$
;


-- Current deployed supporting definitions used by A11 execution.
CREATE OR REPLACE FUNCTION pipeline.svc_pilot_submit_nonce(p_function text, p_body jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pipeline', 'net', 'public', 'extensions'
AS $function$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
  if p_function not in (
    'layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness',
    'coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled',
    'layer2-scope-discover-scheduled','layer2-scale-qualify-scheduled'
  ) then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
    headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),
    body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000
  ) into v_id;
  return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.layer2_scale_scope_service(p_actor uuid, p_action text, p_country_code text, p_scope_type text DEFAULT 'country'::text, p_scope_id uuid DEFAULT NULL::uuid, p_wave_size integer DEFAULT 5, p_sample_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare
  v_rank integer:=0;
  v_country_id uuid;
  v_scope text:=lower(coalesce(nullif(trim(p_scope_type),''),'country'));
  v_wave integer:=least(greatest(coalesce(p_wave_size,5),1),10);
  v_sample integer:=least(greatest(coalesce(p_sample_size,10),1),20);
  v_run uuid;
  v_provider_count integer:=0;
  v_course_count integer:=0;
  v_payload jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
 select coalesce(max(role.rank),0) into v_rank
 from security.user_roles ur join security.roles role on role.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if v_scope not in ('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
 if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;

 select id into v_country_id from ref.countries where upper(iso_alpha2::text)=upper(trim(p_country_code)) limit 1;
 if v_country_id is null then raise exception 'country not found' using errcode='22023'; end if;

 if p_action='preview' then
   with providers as (
     select p.id
     from catalogue.providers p
     where p.country_id=v_country_id
       and exists(select 1 from catalogue.courses c where c.provider_id=p.id)
       and (
         v_scope='country'
         or (v_scope='university' and p.id=p_scope_id)
         or (v_scope='state' and (
           p.subdivision_id=p_scope_id
           or exists(
             select 1 from catalogue.courses c
             join catalogue.course_campuses cc on cc.course_id=c.id
             join catalogue.campuses cam on cam.id=cc.campus_id
             where c.provider_id=p.id and cam.subdivision_id=p_scope_id
           )
         ))
       )
   ), status as (
     select p.id,
       exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=p.id and lp.domain='course_facts'
           and lp.authority_class<>'qualification_candidate'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       ) qualified,
       (select count(*) from catalogue.courses c where c.provider_id=p.id)::integer courses
     from providers p
   )
   select jsonb_build_object(
     'ok',true,'scope_source','layer1_catalogue','country_code',upper(trim(p_country_code)),
     'scope_type',v_scope,'scope_id',p_scope_id,
     'university_count',count(*)::integer,
     'catalogue_count',coalesce(sum(courses),0)::integer,
     'qualified_provider_count',count(*) filter(where qualified)::integer,
     'qualification_required_count',count(*) filter(where not qualified)::integer,
     'executable_course_count',coalesce(sum(courses) filter(where qualified),0)::integer,
     'qualification_course_count',coalesce(sum(courses) filter(where not qualified),0)::integer,
     'queueable_count',(
       select count(distinct c.id)::integer
       from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and (
         nullif(c.course_url,'') is not null
         or exists(
           select 1 from pipeline.layer2_course_discovery_candidates dc
           join pipeline.layer2_source_profiles lp2 on lp2.current_version_id=dc.source_profile_version_id
           join pipeline.sources s2 on s2.id=lp2.source_id
           where dc.course_id=c.id and dc.selected and nullif(dc.discovered_url,'') is not null and s2.provider_id=pp.id
         )
       )
     ),
     'needs_discovery_count',(
       select count(distinct c.id)::integer
       from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and nullif(c.course_url,'') is null
       and not exists(
         select 1 from pipeline.layer2_course_discovery_candidates dc
         join pipeline.layer2_source_profiles lp2 on lp2.current_version_id=dc.source_profile_version_id
         join pipeline.sources s2 on s2.id=lp2.source_id
         where dc.course_id=c.id and dc.selected and nullif(dc.discovered_url,'') is not null and s2.provider_id=pp.id
       )
     ),
     'active_run_count',(
       select count(*)::integer from pipeline.layer2_run_batches b
       join pipeline.layer2_source_profiles lp on lp.id=b.profile_id
       join pipeline.sources s on s.id=lp.source_id
       where b.status in ('queued','running')
         and s.provider_id in (select id from providers)
     ),
     'recommended_action',case when count(*) filter(where not qualified)>0 then 'qualify_wave' else 'sync' end,
     'wave_size',v_wave,'sample_size',v_sample
   ) into v_payload
   from status;
   return v_payload;
 end if;

 if p_action='qualify_wave' then
   insert into pipeline.layer2_scale_qualification_runs(
     country_id,scope_type,scope_id,requested_by,wave_size,sample_size,status,change_control_ref
   ) values(v_country_id,v_scope,p_scope_id,p_actor,v_wave,v_sample,'planned','CF-CHG-20260827-044')
   returning id into v_run;

   with eligible as (
     select p.id,p.canonical_name,(select count(*) from catalogue.courses c where c.provider_id=p.id) course_count
     from catalogue.providers p
     where p.country_id=v_country_id
       and exists(select 1 from catalogue.courses c where c.provider_id=p.id)
       and (
         v_scope='country'
         or (v_scope='university' and p.id=p_scope_id)
         or (v_scope='state' and (
           p.subdivision_id=p_scope_id
           or exists(
             select 1 from catalogue.courses c
             join catalogue.course_campuses cc on cc.course_id=c.id
             join catalogue.campuses cam on cam.id=cc.campus_id
             where c.provider_id=p.id and cam.subdivision_id=p_scope_id
           )
         ))
       )
       and not exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=p.id and lp.domain='course_facts'
           and lp.authority_class<>'qualification_candidate'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and not exists(
         select 1
         from pipeline.layer2_scale_qualification_items qi
         join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
         where qi.provider_id=p.id
           and qr.status in ('planned','running')
       )
     order by course_count desc,p.canonical_name,p.id
     limit v_wave
   ), samples as (
     select e.id provider_id,c.id course_id,
            row_number() over(partition by e.id order by
              case when nullif(c.course_url,'') is null then 0 else 1 end,
              c.stable_key,c.id
            )::integer sample_rank
     from eligible e
     join catalogue.courses c on c.provider_id=e.id
   )
   insert into pipeline.layer2_scale_qualification_items(run_id,provider_id,course_id,sample_rank,selection_reason)
   select v_run,provider_id,course_id,sample_rank,
          case when sample_rank<=greatest(1,least(2,v_sample)) then 'gap_first_control_mix' else 'layer1_gap_sample' end
   from samples where sample_rank<=v_sample
   order by provider_id,sample_rank;

   select count(distinct provider_id),count(*) into v_provider_count,v_course_count
   from pipeline.layer2_scale_qualification_items where run_id=v_run;

   if v_provider_count=0 then
     update pipeline.layer2_scale_qualification_runs
     set status='completed',completed_at=now(),result_summary=jsonb_build_object('outcome','nothing_to_qualify')
     where id=v_run;
   else
     update pipeline.layer2_scale_qualification_runs
     set provider_count=v_provider_count,course_sample_count=v_course_count,
         result_summary=jsonb_build_object(
           'outcome','sample_selected',
           'next_step','deterministic_source_qualification',
           'identity_safety_required',true,
           'canonical_mutation_authorised',false,
           'search_mutation_authorised',false,
           'publication_mutation_authorised',false
         )
     where id=v_run;
   end if;

   return jsonb_build_object(
     'ok',true,'status',case when v_provider_count=0 then 'nothing_to_qualify' else 'qualification_wave_planned' end,
     'qualification_run_id',v_run,'provider_count',v_provider_count,'course_sample_count',v_course_count,
     'wave_size',v_wave,'sample_size',v_sample,
     'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
   );
 end if;

 raise exception 'unsupported action' using errcode='22023';
end $function$
;

CREATE OR REPLACE FUNCTION public.layer2_scope_courses(p_country_code text, p_scope_type text, p_scope_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(profile_id uuid, profile_key text, provider_id uuid, provider_name text, course_id uuid, source_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref'
AS $function$
  select lp.id,lp.profile_key,cp.id,cp.canonical_name,c.id,
         coalesce(nullif(dc.discovered_url,''),nullif(c.course_url,'')) as source_url
  from pipeline.layer2_source_profiles lp
  join pipeline.sources s on s.id=lp.source_id
  join ref.countries country on country.id=s.country_id
  join catalogue.providers cp on cp.id=s.provider_id
  join catalogue.courses c on c.provider_id=cp.id
  left join lateral (
    select d.discovered_url
    from pipeline.layer2_course_discovery_candidates d
    where d.course_id=c.id
      and d.source_profile_version_id=lp.current_version_id
      and d.selected=true
      and nullif(d.discovered_url,'') is not null
    order by d.created_at desc
    limit 1
  ) dc on true
  where lp.domain='course_facts'
    and lp.enabled and not lp.paused
    and upper(country.iso_alpha2::text)=upper(p_country_code)
    and (
      lower(p_scope_type)='country'
      or (lower(p_scope_type)='university' and cp.id=p_scope_id)
      or (lower(p_scope_type)='state' and exists(
        select 1
        from catalogue.course_campuses ccx
        join catalogue.campuses cam on cam.id=ccx.campus_id
        where ccx.course_id=c.id and cam.subdivision_id=p_scope_id
      ))
    )
$function$
;

-- Qualification-candidate profiles are internal evidence/profiling candidates only.
-- They must not enter routine Layer 2 scope until strict controls promote them.
do $$
declare v_oid oid; v_def text; v_old text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='layer2_scope_courses' limit 1;
  if v_oid is null then raise exception 'layer2_scope_courses not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  v_old:='    and lp.enabled
    and not lp.paused';
  if position('authority_class<>''qualification_candidate''' in v_def)=0 then
    v_def:=replace(v_def,v_old,v_old||'
    and lp.authority_class<>''qualification_candidate''');
    execute v_def;
  end if;
end $$;

-- Preserve 401 as a governed acquisition fallback for qualification-only routes.
update pipeline.layer2_profile_provider_routes r
set fallback_on=case when fallback_on ? '401' then fallback_on else fallback_on||'["401"]'::jsonb end,
    updated_at=now()
from pipeline.layer2_source_profiles lp
where r.profile_id=lp.id and lp.authority_class='qualification_candidate';

revoke all on function public.layer2_scale_qualification_prepare(uuid) from public,anon,authenticated;
revoke all on function public.layer2_scale_qualification_context(uuid,integer) from public,anon,authenticated;
revoke all on function public.layer2_scale_qualification_provider_finish(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function security.layer2_scale_qualification_dispatch(uuid) from public,anon,authenticated;
revoke all on function security.layer2_scale_pattern_dispatch(uuid,integer) from public,anon,authenticated;
revoke all on function public.layer2_scale_pattern_reconcile(uuid) from public,anon,authenticated;
revoke all on function public.layer2_scale_cross_layer_handoff(uuid) from public,anon,authenticated;

grant execute on function public.layer2_scale_qualification_prepare(uuid) to service_role;
grant execute on function public.layer2_scale_qualification_context(uuid,integer) to service_role;
grant execute on function public.layer2_scale_qualification_provider_finish(uuid,uuid,uuid,text,jsonb) to service_role;
grant execute on function security.layer2_scale_qualification_dispatch(uuid) to service_role;
grant execute on function security.layer2_scale_pattern_dispatch(uuid,integer) to service_role;
grant execute on function public.layer2_scale_pattern_reconcile(uuid) to service_role;
grant execute on function public.layer2_scale_cross_layer_handoff(uuid) to service_role;

commit;
