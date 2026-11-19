
begin;

create or replace function public.layer2_scale_cross_layer_handoff(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','ref'
as $$
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
end $$;

revoke all on function public.layer2_scale_cross_layer_handoff(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scale_cross_layer_handoff(uuid) to service_role;

commit;
