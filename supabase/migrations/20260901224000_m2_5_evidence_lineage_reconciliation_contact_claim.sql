-- CF-CHG-20260901-059
-- Evidence-lineage reconciliation + Provider-contact scheduler claim hardening.
-- No historical Storage object or Evidence row is deleted or rewritten.

begin;

create table if not exists pipeline.evidence_lineage_reconciliations(
  id uuid primary key default extensions.gen_random_uuid(),
  target_kind text not null check(target_kind in('storage_object','evidence_artifact')),
  storage_path text,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
  reconciliation_class text not null check(reconciliation_class in('historical_orphan_explained','legacy_virtual_reference')),
  reason_code text not null,
  job_id uuid references pipeline.jobs(id) on delete set null,
  provider_id uuid references catalogue.providers(id) on delete set null,
  course_id uuid references catalogue.courses(id) on delete set null,
  supporting_evidence jsonb not null default '{}'::jsonb,
  change_control_ref text not null,
  created_at timestamptz not null default now(),
  constraint evidence_lineage_reconciliation_target_ck check(
    (target_kind='storage_object' and nullif(btrim(storage_path),'') is not null and evidence_id is null)
    or
    (target_kind='evidence_artifact' and evidence_id is not null and storage_path is null)
  )
);

create unique index if not exists evidence_lineage_reconciliations_storage_uq
  on pipeline.evidence_lineage_reconciliations(storage_path)
  where target_kind='storage_object';

create unique index if not exists evidence_lineage_reconciliations_evidence_uq
  on pipeline.evidence_lineage_reconciliations(evidence_id)
  where target_kind='evidence_artifact';

alter table pipeline.evidence_lineage_reconciliations enable row level security;
revoke all on pipeline.evidence_lineage_reconciliations from public,anon,authenticated;
grant select on pipeline.evidence_lineage_reconciliations to service_role;

insert into pipeline.evidence_lineage_reconciliations(
  target_kind,storage_path,reconciliation_class,reason_code,job_id,provider_id,course_id,supporting_evidence,change_control_ref
) values
(
  'storage_object',
  'layer2/v2/discovery/726918ee-10e9-41e3-9a2a-5dace20af754/e7b0e849-d07e-4ea4-a1ec-62dad6ce55e3/09431698-3cfd-4c2b-8669-e924bc65c329/extraction-input.json',
  'historical_orphan_explained',
  'recovered_dispatch_timeout_upload_before_registration',
  'e7b0e849-d07e-4ea4-a1ec-62dad6ce55e3',
  '8e1adb6c-e069-43db-9584-bd054255e702',
  '09431698-3cfd-4c2b-8669-e924bc65c329',
  jsonb_build_object(
    'worker_version','layer2-scope-discover-scheduled-v1.2.4',
    'job_result',jsonb_build_object('recovered',true,'selected_before_timeout',10,'evaluated_before_timeout',16),
    'recovery_error','outer dispatch timeout recovered; resume remaining scope under v1.2.5',
    'registered_source_evidence_id','aafd56e3-3f89-43d0-acb8-7a8fa423561c',
    'later_registered_extraction_evidence_ids',jsonb_build_array(
      'd60d5424-a323-4bae-838c-097448fb2135',
      'a3c5059a-7c9f-4b94-bf2a-548b175f4333'
    )
  ),
  'CF-CHG-20260901-059'
),
(
  'storage_object',
  'layer2/v2/provider-contacts/e47a940d-186f-4a17-bb22-2b794b73248c/1787961417749-2ea05b0cef63.html',
  'historical_orphan_explained',
  'concurrent_scheduler_upload_before_registration',
  null,
  'e47a940d-186f-4a17-bb22-2b794b73248c',
  null,
  jsonb_build_object(
    'provider_name','Australian National University',
    'worker_version','provider-contact-discover-scheduled-v1.1.2',
    'worker_commit','4f2b36ba2b3c26549f519322513ca7d37348723b',
    'created_at','2026-08-28T23:56:57.892035Z',
    'sha256_prefix','2ea05b0cef63',
    'overlapping_nonce_window','2026-08-28T23:56:02Z/2026-08-28T23:57:35Z'
  ),
  'CF-CHG-20260901-059'
),
(
  'storage_object',
  'layer2/v2/provider-contacts/11e427cd-da7a-4f6f-b18a-99426b4d3b25/1787961433006-727538956bab.html',
  'historical_orphan_explained',
  'concurrent_scheduler_upload_before_registration',
  null,
  '11e427cd-da7a-4f6f-b18a-99426b4d3b25',
  null,
  jsonb_build_object(
    'provider_name','Australian University College of Divinity',
    'worker_version','provider-contact-discover-scheduled-v1.1.2',
    'worker_commit','4f2b36ba2b3c26549f519322513ca7d37348723b',
    'created_at','2026-08-28T23:57:13.066170Z',
    'sha256_prefix','727538956bab',
    'overlapping_nonce_window','2026-08-28T23:56:02Z/2026-08-28T23:57:35Z'
  ),
  'CF-CHG-20260901-059'
),
(
  'storage_object',
  'layer2/v2/provider-contacts/fd815678-46ec-49f1-bcc4-ac9b5880d76c/1787961483811-85ba4c1c12e1.html',
  'historical_orphan_explained',
  'concurrent_scheduler_upload_before_registration',
  null,
  'fd815678-46ec-49f1-bcc4-ac9b5880d76c',
  null,
  jsonb_build_object(
    'provider_name','Avondale University',
    'worker_version','provider-contact-discover-scheduled-v1.1.2',
    'worker_commit','4f2b36ba2b3c26549f519322513ca7d37348723b',
    'created_at','2026-08-28T23:58:03.863116Z',
    'sha256_prefix','85ba4c1c12e1',
    'overlapping_nonce_window','2026-08-28T23:56:26Z/2026-08-28T23:57:35Z'
  ),
  'CF-CHG-20260901-059'
),
(
  'storage_object',
  'layer2/v2/provider-contacts/739948f6-6338-4ee9-8d0c-a8c8e953c29d/1787961520922-4cfa1ed91b78.html',
  'historical_orphan_explained',
  'concurrent_scheduler_upload_before_registration',
  null,
  '739948f6-6338-4ee9-8d0c-a8c8e953c29d',
  null,
  jsonb_build_object(
    'provider_name','Bond University Limited',
    'worker_version','provider-contact-discover-scheduled-v1.1.2',
    'worker_commit','4f2b36ba2b3c26549f519322513ca7d37348723b',
    'created_at','2026-08-28T23:58:40.985966Z',
    'sha256_prefix','4cfa1ed91b78',
    'overlapping_nonce_window','2026-08-28T23:56:26Z/2026-08-28T23:57:35Z'
  ),
  'CF-CHG-20260901-059'
)
on conflict do nothing;

insert into pipeline.evidence_lineage_reconciliations(
  target_kind,evidence_id,reconciliation_class,reason_code,job_id,supporting_evidence,change_control_ref
) values
(
  'evidence_artifact',
  '97370ab7-d949-4e54-8785-9ee176703fb3',
  'legacy_virtual_reference',
  'legacy_management_plane_reference',
  'cd2e171d-f5e1-4c9b-91ab-46b002191e20',
  jsonb_build_object(
    'source_id','b012b41d-3be2-4024-9fae-06bbac040551',
    'legacy_path','management-plane/CA/ON/boreal/2026-08-14.html',
    'metadata_management_plane',true,
    'later_storage_backed_evidence_id','502c4148-4143-4235-9528-c4fcbba6c8d0',
    'later_storage_path','regulatory/CA/ON/boreal/2026-08-14T02-36-39-254Z.html',
    'byte_equivalent_claimed',false
  ),
  'CF-CHG-20260901-059'
),
(
  'evidence_artifact',
  'de6710b1-de72-43e6-a96b-4f9ecac07d51',
  'legacy_virtual_reference',
  'legacy_management_plane_reference',
  'e1be867e-b087-4e20-87e7-8517d3582741',
  jsonb_build_object(
    'source_id','50754d20-18dc-40d7-888b-e57267bf127d',
    'legacy_path','management-plane/CA/ON/sault/2026-08-14.html',
    'metadata_management_plane',true,
    'later_storage_backed_evidence_id','e0fb2acd-209d-413a-badb-08057de37a65',
    'later_storage_path','regulatory/CA/ON/sault/2026-08-14T02-43-32-758Z.json',
    'byte_equivalent_claimed',false
  ),
  'CF-CHG-20260901-059'
)
on conflict do nothing;

alter table pipeline.provider_contact_profiles
  add column if not exists claim_token uuid,
  add column if not exists claimed_at timestamptz,
  add column if not exists claim_until timestamptz;

create index if not exists provider_contact_profiles_claim_until_idx
  on pipeline.provider_contact_profiles(claim_until)
  where enabled=true and paused=false;

create or replace function public.provider_contact_profiles_claim_service(
  p_provider_id uuid default null,
  p_limit integer default 2,
  p_lease_seconds integer default 1800
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref','extensions'
as $$
declare
  v jsonb;
  v_limit integer:=greatest(1,least(coalesce(p_limit,2),5));
  v_lease integer:=greatest(60,least(coalesce(p_lease_seconds,1800),3600));
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  with candidate_ids as (
    select pcp.id
    from pipeline.provider_contact_profiles pcp
    join catalogue.providers p on p.id=pcp.provider_id
    where pcp.enabled=true
      and pcp.paused=false
      and (p_provider_id is null or pcp.provider_id=p_provider_id)
      and (pcp.claim_until is null or pcp.claim_until<=now())
    order by pcp.last_run_at nulls first,lower(p.canonical_name),pcp.id
    for update of pcp skip locked
    limit v_limit
  ), claimed as (
    update pipeline.provider_contact_profiles pcp
    set claim_token=extensions.gen_random_uuid(),
        claimed_at=now(),
        claim_until=now()+make_interval(secs=>v_lease),
        last_run_at=now(),
        updated_at=now()
    from candidate_ids c
    where pcp.id=c.id
    returning pcp.*
  ), base as (
    select
      pcp.*,
      p.canonical_name provider_name,
      (
        select coalesce(jsonb_agg(x.origin order by x.origin),'[]'::jsonb)
        from (
          select distinct
            case
              when s.url ~* '^https?://'
              then regexp_replace(s.url,'^(https?://[^/]+).*$','\1','i')
              else null
            end origin
          from pipeline.sources s
          where s.provider_id=pcp.provider_id
            and s.url is not null
            and s.status='active'
        ) x
        where x.origin is not null
      ) governed_origins
    from claimed pcp
    join catalogue.providers p on p.id=pcp.provider_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,
    'provider_id',provider_id,
    'country_id',country_id,
    'base_url',base_url,
    'domain',domain,
    'enabled',enabled,
    'paused',paused,
    'title_terms',title_terms,
    'last_run_at',last_run_at,
    'last_success_at',last_success_at,
    'provider_name',provider_name,
    'claim_token',claim_token,
    'claim_until',claim_until,
    'governed_origins',
      case
        when governed_origins @> jsonb_build_array(regexp_replace(base_url,'^(https?://[^/]+).*$','\1','i'))
        then governed_origins
        else governed_origins || jsonb_build_array(regexp_replace(base_url,'^(https?://[^/]+).*$','\1','i'))
      end
  ) order by last_run_at,id),'[]'::jsonb)
  into v
  from base;

  return v;
end
$$;

revoke all on function public.provider_contact_profiles_claim_service(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.provider_contact_profiles_claim_service(uuid,integer,integer) to service_role;

create or replace function public.provider_contact_profile_finish_claim_service(
  p_profile_id uuid,
  p_claim_token uuid,
  p_status text,
  p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_status not in ('succeeded','failed') then
    raise exception 'invalid Provider-contact finish status' using errcode='22023';
  end if;

  update pipeline.provider_contact_profiles
  set last_run_at=now(),
      last_success_at=case when p_status='succeeded' then now() else last_success_at end,
      last_error=case when p_status='succeeded' then null else left(p_error,1000) end,
      claim_token=null,
      claimed_at=null,
      claim_until=null,
      updated_at=now()
  where id=p_profile_id
    and claim_token=p_claim_token;

  if not found then
    raise exception 'stale or invalid Provider-contact claim token' using errcode='40001';
  end if;

  return true;
end
$$;

revoke all on function public.provider_contact_profile_finish_claim_service(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.provider_contact_profile_finish_claim_service(uuid,uuid,text,text) to service_role;

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
  v_reconciled_orphans bigint;
  v_orphans bigint;
  v_direct_virtual_refs bigint;
  v_reconciled_legacy_refs bigint;
  v_virtual_refs bigint;
  v_failed_raw bigint;
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

  select count(*) into v_unlinked_raw
  from storage.objects o
  where o.bucket_id='evidence'
    and not o.is_delete_marker
    and not exists (
      select 1 from pipeline.evidence_artifacts e
      where e.storage_path=o.name or e.storage_path=('evidence/'||o.name)
    );

  select count(*) into v_duplicate_unlinked
  from storage.objects o
  where o.bucket_id='evidence'
    and not o.is_delete_marker
    and not exists (
      select 1 from pipeline.evidence_artifacts e
      where e.storage_path=o.name or e.storage_path=('evidence/'||o.name)
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
          select 1 from pipeline.evidence_artifacts e
          where e.storage_path=retained.name or e.storage_path=('evidence/'||retained.name)
        )
    );

  select count(*) into v_reconciled_orphans
  from storage.objects o
  join pipeline.evidence_lineage_reconciliations r
    on r.target_kind='storage_object'
   and r.reconciliation_class='historical_orphan_explained'
   and r.storage_path=o.name
  where o.bucket_id='evidence'
    and not o.is_delete_marker
    and not exists (
      select 1 from pipeline.evidence_artifacts e
      where e.storage_path=o.name or e.storage_path=('evidence/'||o.name)
    )
    and not (
      coalesce(o.metadata->>'eTag','')<>''
      and coalesce(o.metadata->>'size','') ~ '^[0-9]+$'
      and exists (
        select 1 from storage.objects retained
        where retained.bucket_id='evidence'
          and not retained.is_delete_marker
          and retained.id<>o.id
          and retained.metadata->>'eTag'=o.metadata->>'eTag'
          and retained.metadata->>'size'=o.metadata->>'size'
          and exists (
            select 1 from pipeline.evidence_artifacts e
            where e.storage_path=retained.name or e.storage_path=('evidence/'||retained.name)
          )
      )
    );

  v_orphans:=greatest(v_unlinked_raw-v_duplicate_unlinked-v_reconciled_orphans,0);

  select count(*) into v_direct_virtual_refs
  from pipeline.evidence_artifacts e
  where nullif(btrim(e.storage_path),'') is not null
    and e.storage_path ~ '^[A-Za-z][A-Za-z0-9+.-]*://';

  select count(*) into v_reconciled_legacy_refs
  from pipeline.evidence_artifacts e
  join pipeline.evidence_lineage_reconciliations r
    on r.target_kind='evidence_artifact'
   and r.reconciliation_class='legacy_virtual_reference'
   and r.evidence_id=e.id
  where nullif(btrim(e.storage_path),'') is not null
    and e.storage_path !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
    and not exists (
      select 1 from storage.objects o
      where o.bucket_id='evidence'
        and not o.is_delete_marker
        and (o.name=e.storage_path or ('evidence/'||o.name)=e.storage_path)
    );

  v_virtual_refs:=v_direct_virtual_refs+v_reconciled_legacy_refs;

  select count(*) into v_failed_raw
  from pipeline.evidence_artifacts e
  where nullif(btrim(e.storage_path),'') is not null
    and e.storage_path !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
    and not exists (
      select 1 from storage.objects o
      where o.bucket_id='evidence'
        and not o.is_delete_marker
        and (o.name=e.storage_path or ('evidence/'||o.name)=e.storage_path)
    );

  select count(*) into v_failed
  from pipeline.evidence_artifacts e
  where nullif(btrim(e.storage_path),'') is not null
    and e.storage_path !~ '^[A-Za-z][A-Za-z0-9+.-]*://'
    and not exists (
      select 1 from storage.objects o
      where o.bucket_id='evidence'
        and not o.is_delete_marker
        and (o.name=e.storage_path or ('evidence/'||o.name)=e.storage_path)
    )
    and not exists (
      select 1 from pipeline.evidence_lineage_reconciliations r
      where r.target_kind='evidence_artifact'
        and r.reconciliation_class='legacy_virtual_reference'
        and r.evidence_id=e.id
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
    'reconciled_historical_orphan_count',v_reconciled_orphans,
    'orphan_object_count',v_orphans,
    'direct_virtual_evidence_reference_count',v_direct_virtual_refs,
    'reconciled_legacy_reference_count',v_reconciled_legacy_refs,
    'virtual_evidence_reference_count',v_virtual_refs,
    'missing_storage_object_count_raw',v_failed_raw,
    'missing_storage_object_count',v_failed,
    'failed_upload_count',v_failed,
    'integrity_count_for_severity',v_integrity_count,
    'integrity_classification',jsonb_build_object(
      'raw_unlinked_storage_objects',v_unlinked_raw,
      'proven_duplicate_unlinked_objects',v_duplicate_unlinked,
      'reconciled_historical_orphans',v_reconciled_orphans,
      'unresolved_orphan_objects',v_orphans,
      'direct_virtual_or_external_evidence_references',v_direct_virtual_refs,
      'reconciled_legacy_references',v_reconciled_legacy_refs,
      'virtual_or_external_evidence_references',v_virtual_refs,
      'raw_missing_bucket_objects',v_failed_raw,
      'missing_bucket_objects',v_failed,
      'duplicate_rule','same ETag + size as an Evidence-linked object',
      'reconciliation_rule','explicit private CF-governed provenance ledger'
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

select public.svc_record_platform_capacity_observation('pilot');

commit;
