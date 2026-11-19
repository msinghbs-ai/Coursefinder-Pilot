-- CF-CHG-20260901-055
-- M2.5 Evidence lineage classification.
-- Reclassifies integrity telemetry only. No Evidence row or Storage object is deleted or rewritten.

begin;

create or replace function security.platform_capacity_snapshot_internal(p_environment text default 'pilot')
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','storage','public'
as $$
declare
  v_db bigint;
  v_temp_bytes bigint;
  v_temp_files bigint;
  v_obj_count bigint;
  v_obj_bytes bigint;
  v_evidence_count bigint;
  v_unlinked_raw bigint;
  v_duplicate_unlinked bigint;
  v_orphans bigint;
  v_virtual_refs bigint;
  v_failed bigint;
  v_largest jsonb;
  v_evidence_policy jsonb;
  v_policy jsonb;
  v_severity text := 'ok';
  v_integrity_count bigint;
  v_evidence_pct numeric;
  v_prev_temp_bytes bigint;
  v_prev_observed_at timestamptz;
  v_temp_delta bigint;
begin
  if p_environment not in ('pilot','production') then
    raise exception 'invalid environment';
  end if;

  select pg_database_size(current_database()) into v_db;
  select coalesce(temp_bytes,0),coalesce(temp_files,0)
    into v_temp_bytes,v_temp_files
  from pg_stat_database where datname=current_database();

  select count(*),
         coalesce(sum(case when coalesce(metadata->>'size','') ~ '^[0-9]+$'
                           then (metadata->>'size')::bigint else 0 end),0)
    into v_obj_count,v_obj_bytes
  from storage.objects
  where bucket_id='evidence' and not is_delete_marker;

  select count(*) into v_evidence_count
  from pipeline.evidence_artifacts;

  -- Raw Storage objects without a retained Evidence path. Keep this visible for audit.
  select count(*) into v_unlinked_raw
  from storage.objects o
  where o.bucket_id='evidence'
    and not o.is_delete_marker
    and not exists (
      select 1
      from pipeline.evidence_artifacts e
      where e.storage_path=o.name
         or e.storage_path=('evidence/'||o.name)
    );

  -- Classify only strong duplicate fingerprints:
  -- identical ETag + byte size to another object which is itself referenced by Evidence.
  select count(*) into v_duplicate_unlinked
  from storage.objects o
  where o.bucket_id='evidence'
    and not o.is_delete_marker
    and not exists (
      select 1
      from pipeline.evidence_artifacts e
      where e.storage_path=o.name
         or e.storage_path=('evidence/'||o.name)
    )
    and coalesce(o.metadata->>'eTag','')<>''
    and coalesce(o.metadata->>'size','') ~ '^[0-9]+$'
    and exists (
      select 1
      from storage.objects retained
      where retained.bucket_id='evidence'
        and not retained.is_delete_marker
        and retained.id<>o.id
        and retained.metadata->>'eTag'=o.metadata->>'eTag'
        and retained.metadata->>'size'=o.metadata->>'size'
        and exists (
          select 1
          from pipeline.evidence_artifacts e
          where e.storage_path=retained.name
             or e.storage_path=('evidence/'||retained.name)
        )
    );

  v_orphans:=greatest(v_unlinked_raw-v_duplicate_unlinked,0);

  -- Legacy DB / management-plane references are not Supabase Storage keys.
  select count(*) into v_virtual_refs
  from pipeline.evidence_artifacts e
  where nullif(btrim(e.storage_path),'') is not null
    and e.storage_path ~ '^[A-Za-z][A-Za-z0-9+.-]*://';

  -- Only bucket-like paths can represent missing Supabase Storage objects.
  select count(*) into v_failed
  from pipeline.evidence_artifacts e
  where nullif(btrim(e.storage_path),'') is not null
    and e.storage_path !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
    and not exists (
      select 1
      from storage.objects o
      where o.bucket_id='evidence'
        and not o.is_delete_marker
        and (o.name=e.storage_path or ('evidence/'||o.name)=e.storage_path)
    );

  v_integrity_count:=greatest(v_orphans,v_failed);

  select coalesce(jsonb_agg(jsonb_build_object(
           'schema',schema_name,'relation',relation_name,'bytes',total_bytes
         ) order by total_bytes desc),'[]'::jsonb)
  into v_largest
  from (
    select n.nspname schema_name,c.relname relation_name,pg_total_relation_size(c.oid) total_bytes
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind in ('r','m')
      and n.nspname not in ('pg_catalog','information_schema')
    order by total_bytes desc
    limit 10
  ) x;

  select coalesce(to_jsonb(p),'{}'::jsonb) into v_evidence_policy
  from pipeline.evidence_capacity_policy p where id=true;

  if coalesce((v_evidence_policy->>'planning_capacity_bytes')::bigint,0)>0 then
    v_evidence_pct:=round((v_obj_bytes::numeric/(v_evidence_policy->>'planning_capacity_bytes')::numeric)*100,2);
  end if;

  select coalesce(to_jsonb(p),'{}'::jsonb) into v_policy
  from pipeline.platform_capacity_policy p where environment=p_environment;

  select cumulative_temp_bytes,observed_at
    into v_prev_temp_bytes,v_prev_observed_at
  from pipeline.platform_capacity_observations
  where environment=p_environment
  order by observed_at desc limit 1;

  if v_prev_temp_bytes is not null then
    v_temp_delta:=greatest(v_temp_bytes-v_prev_temp_bytes,0);
  end if;

  if coalesce((v_policy->>'database_critical_bytes')::bigint,9223372036854775807) <= v_db
     or coalesce((v_policy->>'integrity_critical_count')::integer,2147483647) <= v_integrity_count
     or coalesce((v_evidence_policy->>'critical_pct')::numeric,101) <= coalesce(v_evidence_pct,0)
  then v_severity:='critical';
  elsif coalesce((v_policy->>'database_high_bytes')::bigint,9223372036854775807) <= v_db
     or coalesce((v_policy->>'integrity_high_count')::integer,2147483647) <= v_integrity_count
     or coalesce((v_evidence_policy->>'high_pct')::numeric,101) <= coalesce(v_evidence_pct,0)
  then v_severity:='high';
  elsif coalesce((v_policy->>'database_warn_bytes')::bigint,9223372036854775807) <= v_db
     or coalesce((v_policy->>'integrity_warn_count')::integer,2147483647) <= v_integrity_count
     or coalesce((v_evidence_policy->>'warn_pct')::numeric,101) <= coalesce(v_evidence_pct,0)
  then v_severity:='warning';
  end if;

  return jsonb_build_object(
    'environment',p_environment,
    'observed_at',now(),
    'severity',v_severity,
    'database_bytes',v_db,
    'cumulative_temp_bytes',v_temp_bytes,
    'cumulative_temp_files',v_temp_files,
    'temp_bytes_since_previous_observation',v_temp_delta,
    'previous_observation_at',v_prev_observed_at,
    'evidence_object_count',v_obj_count,
    'evidence_object_bytes',v_obj_bytes,
    'evidence_planning_capacity_pct',v_evidence_pct,
    'evidence_artifact_count',v_evidence_count,
    'unlinked_storage_object_count_raw',v_unlinked_raw,
    'duplicate_unlinked_storage_object_count',v_duplicate_unlinked,
    'orphan_object_count',v_orphans,
    'virtual_evidence_reference_count',v_virtual_refs,
    'missing_storage_object_count',v_failed,
    'failed_upload_count',v_failed,
    'integrity_count_for_severity',v_integrity_count,
    'integrity_classification',jsonb_build_object(
      'raw_unlinked_storage_objects',v_unlinked_raw,
      'proven_duplicate_unlinked_objects',v_duplicate_unlinked,
      'unresolved_orphan_objects',v_orphans,
      'virtual_or_external_evidence_references',v_virtual_refs,
      'missing_bucket_objects',v_failed,
      'duplicate_rule','same ETag + size as an Evidence-linked object'
    ),
    'largest_relations',v_largest,
    'evidence_capacity_policy',v_evidence_policy,
    'platform_capacity_policy',v_policy,
    'backup_status','platform_api_required',
    'pitr_status','platform_api_required'
  );
end $$;

revoke all on function security.platform_capacity_snapshot_internal(text) from public,anon,authenticated;
grant execute on function security.platform_capacity_snapshot_internal(text) to service_role;

-- Record one corrected-semantics Pilot observation. This is telemetry only.
select public.svc_record_platform_capacity_observation('pilot');

commit;
