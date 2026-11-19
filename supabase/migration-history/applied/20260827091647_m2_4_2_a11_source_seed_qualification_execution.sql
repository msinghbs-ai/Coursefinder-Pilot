
begin;

alter table pipeline.layer2_scale_qualification_items
  drop constraint if exists layer2_scale_qualification_items_status_check;
alter table pipeline.layer2_scale_qualification_items
  add constraint layer2_scale_qualification_items_status_check
  check (status in (
    'selected','qualifying','source_pattern_candidate','qualified_l2',
    'layer3_required','layer4_required','source_limited','blocked'
  ));

create or replace function public.layer2_scale_qualification_prepare(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref','security'
as $$
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
end $$;

create or replace function public.layer2_scale_qualification_context(p_run_id uuid,p_limit integer default 5)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','pipeline','catalogue','ref','public'
as $$
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
$$;

create or replace function public.layer2_scale_qualification_provider_finish(
  p_run_id uuid,
  p_provider_id uuid,
  p_evidence_id uuid,
  p_status text,
  p_outcome jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $$
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
end $$;

-- Prevent qualification-only profiles from entering routine sync scope.
do $$
declare v_oid oid; v_def text; v_old text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='layer2_scope_courses'
  limit 1;
  if v_oid is null then raise exception 'layer2_scope_courses not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  v_old:='    and lp.enabled
    and not lp.paused';
  if position('authority_class' in v_def)=0 then
    v_def:=replace(v_def,v_old,v_old||'
    and lp.authority_class<>''qualification_candidate''');
    execute v_def;
  end if;
end $$;

-- Qualification-candidate profiles must not count as fully qualified in the A11 preview.
do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='layer2_scale_scope_service'
    and pg_get_function_identity_arguments(p.oid)='p_actor uuid, p_action text, p_country_code text, p_scope_type text, p_scope_id uuid, p_wave_size integer, p_sample_size integer'
  limit 1;
  if v_oid is null then raise exception 'layer2_scale_scope_service not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('qualification_candidate' in v_def)=0 then
    v_def:=replace(v_def,
      'where s.provider_id=p.id and lp.domain=''course_facts''
           and lp.enabled and not lp.paused and pv.validation_status=''valid''',
      'where s.provider_id=p.id and lp.domain=''course_facts''
           and lp.authority_class<>''qualification_candidate''
           and lp.enabled and not lp.paused and pv.validation_status=''valid'''
    );
    v_def:=replace(v_def,
      'where s.provider_id=pp.id and lp.domain=''course_facts'' and lp.enabled and not lp.paused and pv.validation_status=''valid''',
      'where s.provider_id=pp.id and lp.domain=''course_facts'' and lp.authority_class<>''qualification_candidate'' and lp.enabled and not lp.paused and pv.validation_status=''valid'''
    );
    execute v_def;
  end if;
end $$;

-- Allow internal scheduled qualification worker through the existing one-time nonce bridge.
do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='pipeline' and p.proname='svc_pilot_submit_nonce'
  limit 1;
  if v_oid is null then raise exception 'svc_pilot_submit_nonce not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('layer2-scale-qualify-scheduled' in v_def)=0 then
    v_def:=replace(v_def,
      '''layer2-scope-discover-scheduled''',
      '''layer2-scope-discover-scheduled'',''layer2-scale-qualify-scheduled'''
    );
    execute v_def;
  end if;
end $$;

create or replace function security.layer2_scale_qualification_dispatch(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','security'
as $$
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
end $$;

revoke all on function public.layer2_scale_qualification_prepare(uuid) from public,anon,authenticated;
revoke all on function public.layer2_scale_qualification_context(uuid,integer) from public,anon,authenticated;
revoke all on function public.layer2_scale_qualification_provider_finish(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function security.layer2_scale_qualification_dispatch(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scale_qualification_prepare(uuid) to service_role;
grant execute on function public.layer2_scale_qualification_context(uuid,integer) to service_role;
grant execute on function public.layer2_scale_qualification_provider_finish(uuid,uuid,uuid,text,jsonb) to service_role;
grant execute on function security.layer2_scale_qualification_dispatch(uuid) to service_role;

commit;
