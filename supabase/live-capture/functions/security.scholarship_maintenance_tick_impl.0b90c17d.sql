CREATE OR REPLACE FUNCTION security.scholarship_maintenance_tick_impl(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'scholarship', 'catalogue'
AS $function$
declare
  v_run uuid;
  v_mappings integer:=0;
  v_candidates integer:=0;
  v_source_records integer:=0;
  v_unapplied integer:=0;
  v_discovery integer:=0;
  v_stale integer:=0;
begin
  if current_user not in('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  insert into pipeline.scholarship_maintenance_runs(status) values('running') returning id into v_run;

  with deterministic as(
    select distinct s.id scholarship_id,c.id course_id,sc.id scope_id,coalesce(sc.evidence_id,s.evidence_id) evidence_id,
      case when sc.scope_type='course' then 'explicit_course_scope' else 'explicit_provider_scope' end basis
    from scholarship.scholarships s
    join scholarship.scopes sc on sc.scholarship_id=s.id and sc.include_exclude='include'
    join catalogue.courses c
      on (sc.scope_type='course' and sc.course_id=c.id)
      or (sc.scope_type='provider' and sc.provider_id=c.provider_id)
    where sc.scope_type in('course','provider')
      and not exists(
        select 1 from scholarship.scopes ex
        where ex.scholarship_id=s.id and ex.include_exclude='exclude'
          and ((ex.scope_type='course' and ex.course_id=c.id)
            or (ex.scope_type='provider' and ex.provider_id=c.provider_id))
      )
  ), upserted as(
    insert into scholarship.course_mappings(
      scholarship_id,course_id,mapping_state,mapping_basis,source_scope_id,evidence_id,mapped_by,updated_at
    )
    select scholarship_id,course_id,'mapped',basis,scope_id,evidence_id,null,p_now
    from deterministic
    on conflict(scholarship_id,course_id) do update set
      mapping_state='mapped',
      mapping_basis=excluded.mapping_basis,
      source_scope_id=excluded.source_scope_id,
      evidence_id=excluded.evidence_id,
      updated_at=p_now
    returning 1
  )
  select count(*) into v_mappings from upserted;

  select count(*) into v_candidates
  from scholarship.course_mapping_candidates where status='needs_review';

  select count(*) into v_source_records from pipeline.scholarship_source_records;
  select count(*) into v_unapplied
  from pipeline.scholarship_source_records where status<>'applied' or applied_at is null;
  select count(*) into v_discovery
  from pipeline.layer2_scholarship_discovery_candidates where status='discovered';
  select count(*) into v_stale
  from pipeline.scholarship_source_records
  where observed_at<p_now-interval '45 days';

  update pipeline.scholarship_maintenance_runs
  set completed_at=p_now,status='completed',
      deterministic_mappings=v_mappings,
      mapping_candidates=v_candidates,
      source_records=v_source_records,
      unapplied_source_records=v_unapplied,
      discovery_candidates=v_discovery,
      stale_source_records=v_stale,
      evidence_deleted=0,
      source_records_deleted=0,
      notes=jsonb_build_object(
        'mapping_rule','explicit course/provider include scopes only',
        'evidence_retained',true,
        'source_history_retained',true
      )
  where id=v_run;

  return jsonb_build_object(
    'ok',true,'run_id',v_run,'deterministic_mappings',v_mappings,
    'mapping_candidates',v_candidates,'source_records',v_source_records,
    'unapplied_source_records',v_unapplied,'discovery_candidates',v_discovery,
    'stale_source_records',v_stale,'evidence_deleted',0,'source_records_deleted',0
  );
exception when others then
  if v_run is not null then
    update pipeline.scholarship_maintenance_runs
    set completed_at=now(),status='failed',notes=jsonb_build_object('error',sqlerrm)
    where id=v_run;
  end if;
  raise;
end $function$
