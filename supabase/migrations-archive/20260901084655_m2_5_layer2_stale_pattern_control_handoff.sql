-- CF-CHG-20260901-053
-- Reconcile incomplete pattern-control sets after a bounded stale window.
-- A stale/incomplete control is routed to governed Layer 3 review; it is never auto-qualified.
-- No Layer 3 AI call, canonical mutation, Search admission or Publication mutation occurs here.

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
  v_required integer;
  v_dispatched_at timestamptz;
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

    v_required:=coalesce(array_length(v_ids,1),0);
    select created_at into v_dispatched_at
    from pipeline.layer2_source_profile_versions
    where id=v_version;

    select count(distinct dc.course_id),
           count(distinct dc.course_id) filter(where dc.selected=true)
    into v_terminal,v_selected
    from pipeline.layer2_course_discovery_candidates dc
    where dc.source_profile_version_id=v_version
      and dc.course_id=any(v_ids)
      and dc.status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found');

    if v_terminal<v_required then
      if v_dispatched_at is not null and v_dispatched_at<=now()-interval '30 minutes' then
        update pipeline.layer2_scale_qualification_items
        set status='layer3_required',
            outcome=outcome||jsonb_build_object(
              'provider_pattern_qualified',false,
              'pattern_control_status','incomplete_timeout',
              'pattern_control_dispatched_at',v_dispatched_at,
              'identity_controls_terminal',coalesce(v_terminal,0),
              'identity_controls_missing',greatest(v_required-coalesce(v_terminal,0),0),
              'identity_controls_required',v_required,
              'reason','pattern_control_incomplete_timeout',
              'handoff','layer3_source_pattern_interpretation',
              'canonical_mutation_authorised',false,
              'search_mutation_authorised',false,
              'publication_mutation_authorised',false
            )
        where run_id=p_run_id and provider_id=r.provider_id and status='source_pattern_candidate';
        v_provider_result:=jsonb_build_object(
          'provider_id',r.provider_id,
          'status','layer3_required',
          'reason','pattern_control_incomplete_timeout',
          'controls_terminal',coalesce(v_terminal,0),
          'controls_required',v_required
        );
        v_results:=v_results||jsonb_build_array(v_provider_result);
      end if;
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

revoke all on function public.layer2_scale_pattern_reconcile(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scale_pattern_reconcile(uuid) to service_role;
