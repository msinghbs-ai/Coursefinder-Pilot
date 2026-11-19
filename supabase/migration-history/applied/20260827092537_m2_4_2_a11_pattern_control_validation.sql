
begin;

alter table pipeline.layer2_scale_qualification_items
  drop constraint if exists layer2_scale_qualification_items_status_check;
alter table pipeline.layer2_scale_qualification_items
  add constraint layer2_scale_qualification_items_status_check
  check (status in (
    'selected','qualifying','source_pattern_candidate','profile_qualified','qualified_l2',
    'layer3_required','layer4_required','source_limited','blocked'
  ));

create or replace function security.layer2_scale_pattern_dispatch(
  p_run_id uuid,
  p_limit integer default 2
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','security'
as $$
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
end $$;

create or replace function public.layer2_scale_pattern_reconcile(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue'
as $$
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
end $$;

revoke all on function security.layer2_scale_pattern_dispatch(uuid,integer) from public,anon,authenticated;
revoke all on function public.layer2_scale_pattern_reconcile(uuid) from public,anon,authenticated;
grant execute on function security.layer2_scale_pattern_dispatch(uuid,integer) to service_role;
grant execute on function public.layer2_scale_pattern_reconcile(uuid) to service_role;

commit;
