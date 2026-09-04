-- CF-142 — Evidence acquisition provenance.
-- Evidence detail must distinguish live scraper/direct acquisition from artifacts derived from retained private Evidence.

create or replace function security.admin_evidence_acquisition_provenance(p_evidence_id uuid)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
  with artifact as (
    select e.id,e.storage_path,e.metadata,e.job_id,
           nullif(e.metadata->>'source_evidence_id','')::uuid as source_evidence_id
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
    left join pipeline.layer2_acquisition_providers ap on ap.id=coalesce(f.acquisition_provider_id,nullif(o.origin_metadata->>'provider_id','')::uuid)
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

-- `security.admin_evidence_detail(uuid)` is replaced in the Pilot runtime so its existing JSON contract now includes:
--   acquisition_provenance := security.admin_evidence_acquisition_provenance(e.id)
-- alongside artifact/source/job/storage/supersession/claim/review lineage.
-- The browser continues to access this through the existing guarded `public.admin_read('evidence_detail', ...)` path;
-- no raw Evidence/shared-fetch/provider table grant is introduced.
