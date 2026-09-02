begin;

create table if not exists pipeline.scholarship_catalogue_runs(
  id uuid primary key default extensions.gen_random_uuid(),
  source_id uuid not null references pipeline.sources(id) on delete cascade,
  evidence_id uuid not null references pipeline.evidence_artifacts(id) on delete restrict,
  source_profile_version_id uuid references pipeline.layer2_source_profile_versions(id) on delete set null,
  provider_id uuid references catalogue.providers(id) on delete cascade,
  content_hash text,
  discovered_count integer not null default 0 check(discovered_count>=0),
  unique_candidate_count integer not null default 0 check(unique_candidate_count>=0),
  duplicate_count integer not null default 0 check(duplicate_count>=0),
  status text not null default 'captured' check(status in('captured','complete','partial','needs_review','failed')),
  observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(source_id,evidence_id)
);
create index if not exists scholarship_catalogue_runs_provider_idx on pipeline.scholarship_catalogue_runs(provider_id,observed_at desc);
create index if not exists scholarship_catalogue_runs_source_idx on pipeline.scholarship_catalogue_runs(source_id,observed_at desc);

alter table pipeline.scholarship_catalogue_runs enable row level security;
revoke all on pipeline.scholarship_catalogue_runs from public,anon,authenticated;

create or replace function public.layer2_scholarship_extraction_context(p_evidence_id uuid)
returns jsonb language sql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
 select jsonb_build_object(
   'id',e.id,
   'source_id',e.source_id,
   'job_id',e.job_id,
   'evidence_type',e.evidence_type,
   'source_url',e.source_url,
   'storage_path',e.storage_path,
   'content_hash',e.content_hash,
   'mime_type',e.mime_type,
   'source_profile_version_id',e.source_profile_version_id,
   'metadata',e.metadata,
   'provider_id',s.provider_id,
   'provider_name',p.canonical_name,
   'source_type',s.source_type,
   'source_label',s.label,
   'source_metadata',s.metadata
 )
 from pipeline.evidence_artifacts e
 join pipeline.sources s on s.id=e.source_id
 left join catalogue.providers p on p.id=s.provider_id
 where e.id=p_evidence_id
$$;
revoke all on function public.layer2_scholarship_extraction_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scholarship_extraction_context(uuid) to service_role;

create or replace function public.layer2_scholarship_catalogue_apply(
  p_evidence_id uuid,
  p_links jsonb default '[]'::jsonb,
  p_status text default 'captured',
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
declare
  v_ctx jsonb;
  v_link jsonb;
  v_inserted integer:=0;
  v_total integer:=0;
  v_duplicates integer:=0;
  v_parent_candidate uuid;
  v_run uuid;
begin
  v_ctx:=public.layer2_scholarship_extraction_context(p_evidence_id);
  if v_ctx is null or v_ctx='null'::jsonb then raise exception 'evidence_not_found' using errcode='P0002'; end if;
  if v_ctx->>'evidence_type'<>'layer2_extraction_input' then raise exception 'layer2_extraction_input_required' using errcode='23514'; end if;
  if p_status not in('captured','complete','partial','needs_review','failed') then raise exception 'invalid_catalogue_status' using errcode='23514'; end if;

  for v_link in select value from jsonb_array_elements(coalesce(p_links,'[]'::jsonb))
  loop
    v_total:=v_total+1;
    insert into pipeline.layer2_scholarship_discovery_candidates(
      source_id,evidence_id,source_profile_version_id,scholarship_url,observed_title,status
    ) values(
      (v_ctx->>'source_id')::uuid,
      p_evidence_id,
      nullif(v_ctx->>'source_profile_version_id','')::uuid,
      v_link->>'url',
      nullif(v_link->>'title',''),
      'discovered'
    )
    on conflict(evidence_id,scholarship_url) do nothing;
    if found then v_inserted:=v_inserted+1; else v_duplicates:=v_duplicates+1; end if;
  end loop;

  insert into pipeline.scholarship_catalogue_runs(
    source_id,evidence_id,source_profile_version_id,provider_id,content_hash,
    discovered_count,unique_candidate_count,duplicate_count,status,metadata
  ) values(
    (v_ctx->>'source_id')::uuid,
    p_evidence_id,
    nullif(v_ctx->>'source_profile_version_id','')::uuid,
    nullif(v_ctx->>'provider_id','')::uuid,
    v_ctx->>'content_hash',
    v_total,v_inserted,v_duplicates,p_status,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'source_url',v_ctx->>'source_url',
      'source_label',v_ctx->>'source_label',
      'change_control_ref','CF-CHG-20260903-083'
    )
  )
  on conflict(source_id,evidence_id) do update set
    discovered_count=excluded.discovered_count,
    unique_candidate_count=excluded.unique_candidate_count,
    duplicate_count=excluded.duplicate_count,
    status=excluded.status,
    metadata=excluded.metadata,
    observed_at=now()
  returning id into v_run;

  begin
    v_parent_candidate:=nullif(v_ctx->'source_metadata'->>'candidate_id','')::uuid;
  exception when others then v_parent_candidate:=null; end;

  if v_parent_candidate is not null then
    update pipeline.layer2_scholarship_discovery_candidates
    set status='acquired'
    where id=v_parent_candidate and status='discovered';
  end if;

  return jsonb_build_object(
    'run_id',v_run,
    'provider_id',v_ctx->>'provider_id',
    'source_id',v_ctx->>'source_id',
    'discovered_count',v_total,
    'inserted_count',v_inserted,
    'duplicate_count',v_duplicates,
    'status',p_status
  );
end $$;
revoke all on function public.layer2_scholarship_catalogue_apply(uuid,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_scholarship_catalogue_apply(uuid,jsonb,text,jsonb) to service_role;

commit;