-- A15: keep probe history but surface only meaningful post-discovery change signals.

update pipeline.provider_contact_watch_events e
set acknowledged=true,
    metadata=e.metadata||jsonb_build_object('a15_quality_probe',true,'a15_auto_acknowledged_at',now())
where (
    e.metadata->>'reason' in ('a15_initial_probe_noise','a15_structured_table_fallback')
    or exists (
      select 1
      from pipeline.provider_contact_observations o
      where o.id=e.observation_id
        and o.verification_state='rejected'
        and o.metadata ? 'a15_quality_disposition'
    )
  )
  and e.acknowledged=false;

create or replace function security.admin_provider_contacts(p_provider_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','ref','public','auth'
as $$
declare
  v_rank integer:=0;
  v_profile jsonb;
  v_items jsonb;
  v_events jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  select jsonb_build_object(
    'profile_id',p.id,
    'enabled',p.enabled,
    'paused',p.paused,
    'base_url',p.base_url,
    'domain',p.domain,
    'last_run_at',p.last_run_at,
    'last_success_at',p.last_success_at,
    'last_error',p.last_error
  )
  into v_profile
  from pipeline.provider_contact_profiles p
  where p.provider_id=p_provider_id;

  select coalesce(
    jsonb_agg(row_json order by source_priority, lower(coalesce(row_json->>'territory_text','')), lower(coalesce(row_json->>'job_title','')), lower(coalesce(row_json->>'full_name',''))),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      case o.source_class when 'first_party' then 1 when 'manual' then 2 else 3 end source_priority,
      jsonb_build_object(
        'id',o.id,
        'source_class',o.source_class,
        'source_provider',o.source_provider,
        'full_name',o.full_name,
        'job_title',o.job_title,
        'team_name',o.team_name,
        'territory_text',o.territory_text,
        'territory_codes',o.territory_codes,
        'work_email',o.work_email,
        'work_phone',o.work_phone,
        'professional_profile_url',o.professional_profile_url,
        'source_url',o.source_url,
        'evidence_id',o.evidence_id,
        'verification_state',o.verification_state,
        'confidence',o.confidence,
        'observed_at',o.observed_at,
        'last_verified_at',o.last_verified_at,
        'source_priority',case o.source_class when 'first_party' then 'preferred' when 'manual' then 'governed_manual' else 'secondary_enrichment' end
      ) row_json
    from pipeline.provider_contact_observations o
    where o.provider_id=p_provider_id
      and o.is_current=true
      and o.verification_state <> 'rejected'
    order by 1, o.last_verified_at desc
    limit 50
  ) q;

  select coalesce(
    jsonb_agg(jsonb_build_object(
      'id',e.id,
      'event_type',e.event_type,
      'source_class',e.source_class,
      'before_state',e.before_state,
      'after_state',e.after_state,
      'detected_at',e.detected_at,
      'acknowledged',e.acknowledged
    ) order by e.detected_at desc),
    '[]'::jsonb
  )
  into v_events
  from (
    select *
    from pipeline.provider_contact_watch_events
    where provider_id=p_provider_id
      and event_type <> 'new_contact'
      and coalesce(metadata->>'a15_quality_probe','false') <> 'true'
    order by detected_at desc
    limit 20
  ) e;

  return jsonb_build_object(
    'profile',coalesce(v_profile,'{}'::jsonb),
    'items',coalesce(v_items,'[]'::jsonb),
    'events',coalesce(v_events,'[]'::jsonb),
    'summary',jsonb_build_object(
      'current_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and verification_state<>'rejected'),
      'first_party_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='first_party' and verification_state<>'rejected'),
      'enriched_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='licensed_enrichment' and verification_state<>'rejected'),
      'unacknowledged_changes',(
        select count(*)
        from pipeline.provider_contact_watch_events e
        where e.provider_id=p_provider_id
          and e.acknowledged=false
          and e.event_type <> 'new_contact'
          and coalesce(e.metadata->>'a15_quality_probe','false') <> 'true'
      )
    )
  );
end $$;

revoke all on function security.admin_provider_contacts(uuid) from public,anon,authenticated;
