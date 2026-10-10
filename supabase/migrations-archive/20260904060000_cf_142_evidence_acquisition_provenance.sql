-- CF-142 — Evidence acquisition provenance.
-- Distinguish live acquisition from artifacts derived from retained private Evidence without widening browser grants.

create or replace function security.admin_evidence_acquisition_provenance(p_evidence_id uuid)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
  with artifact as (
    select e.id,e.storage_path,e.metadata,e.job_id,
           case when coalesce(e.metadata->>'source_evidence_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                then (e.metadata->>'source_evidence_id')::uuid end as source_evidence_id
    from pipeline.evidence_artifacts e where e.id=p_evidence_id
  ), origin as (
    select a.*,coalesce(src.id,a.id) origin_evidence_id,
           coalesce(src.storage_path,a.storage_path) origin_storage_path,
           coalesce(src.metadata,a.metadata) origin_metadata
    from artifact a left join pipeline.evidence_artifacts src on src.id=a.source_evidence_id
  ), sf as (
    select o.*,f.id shared_fetch_id,f.reuse_count,f.last_reused_at,f.reusable_until,
           ap.provider_key,ap.display_name,ap.adapter_type
    from origin o
    left join pipeline.layer2_shared_fetches f on f.evidence_id=o.origin_evidence_id
    left join pipeline.layer2_acquisition_providers ap on ap.id=coalesce(
      f.acquisition_provider_id,
      case when coalesce(o.origin_metadata->>'provider_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           then (o.origin_metadata->>'provider_id')::uuid end
    )
  )
  select jsonb_strip_nulls(jsonb_build_object(
    'mode',case when source_evidence_id is not null then 'stored_evidence_derived' when coalesce(reuse_count,0)>0 then 'live_capture_with_storage_reuse' else 'live_acquisition' end,
    'mode_label',case when source_evidence_id is not null then 'Derived from stored Evidence' when coalesce(reuse_count,0)>0 then 'Live capture · reused from shared Evidence storage' else 'Live acquisition' end,
    'provider_key',coalesce(provider_key,origin_metadata->>'provider_key'),
    'provider_name',coalesce(display_name,origin_metadata->>'provider_key'),
    'adapter_type',adapter_type,'origin_evidence_id',origin_evidence_id,'source_evidence_id',source_evidence_id,
    'origin_storage_path',origin_storage_path,'shared_fetch_id',shared_fetch_id,'reuse_count',coalesce(reuse_count,0),
    'last_reused_at',last_reused_at,'reusable_until',reusable_until,'storage_reused',coalesce(reuse_count,0)>0,
    'runtime_version',origin_metadata->>'runtime_version','response_adapter',origin_metadata->>'response_adapter'
  )) from sf;
$$;
revoke all on function security.admin_evidence_acquisition_provenance(uuid) from public,anon,authenticated;
grant execute on function security.admin_evidence_acquisition_provenance(uuid) to service_role;
