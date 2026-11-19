create table if not exists pipeline.ca_course_scope_keys (
  source_id uuid not null references pipeline.sources(id) on delete cascade,
  scope_tag text not null,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  course_scheme text not null,
  identifier text not null,
  study_level_code text null,
  metadata jsonb not null default '{}'::jsonb,
  verified_at timestamptz not null default now(),
  primary key (source_id, scope_tag, provider_id, course_scheme, identifier)
);
revoke all on pipeline.ca_course_scope_keys from public, anon, authenticated;
grant select,insert,update,delete on pipeline.ca_course_scope_keys to service_role;

create or replace function public.svc_layer1_stage_course_scope_keys(
  p_source_id uuid,
  p_scope_tag text,
  p_course_scheme text,
  p_rows jsonb
) returns jsonb
language plpgsql security definer
set search_path='public','catalogue','pipeline','ref'
as $$
declare r jsonb; v_provider uuid; v_dli text; v_id text; v_level text; v_n int:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if nullif(trim(p_scope_tag),'') is null or nullif(trim(p_course_scheme),'') is null then raise exception 'scope tag and scheme required'; end if;
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    v_dli:=upper(nullif(trim(r->>'provider_code'),'')); v_id:=nullif(trim(r->>'local_program_id'),''); v_level:=nullif(trim(r->>'study_level_code'),'');
    if v_dli is null or v_id is null then raise exception 'scope row missing provider_code/local_program_id'; end if;
    select pi.provider_id into v_provider from catalogue.provider_identifiers pi join ref.countries c on c.id=pi.country_id where upper(c.iso_alpha2::text)='CA' and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)=v_dli order by pi.is_primary desc,pi.verified_at desc nulls last limit 1;
    if v_provider is null then raise exception 'scope Provider DLI not resolved: %',v_dli; end if;
    insert into pipeline.ca_course_scope_keys(source_id,scope_tag,provider_id,course_scheme,identifier,study_level_code,metadata,verified_at)
    values(p_source_id,trim(p_scope_tag),v_provider,lower(trim(p_course_scheme)),v_id,v_level,coalesce(r->'metadata','{}'::jsonb),now())
    on conflict (source_id,scope_tag,provider_id,course_scheme,identifier) do update set study_level_code=excluded.study_level_code,metadata=excluded.metadata,verified_at=excluded.verified_at;
    v_n:=v_n+1;
  end loop;
  return jsonb_build_object('staged',v_n,'scope_tag',p_scope_tag);
end $$;
revoke all on function public.svc_layer1_stage_course_scope_keys(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_layer1_stage_course_scope_keys(uuid,text,text,jsonb) to service_role;

create or replace function public.svc_layer1_apply_course_scope(
  p_source_id uuid,
  p_scope_tag text,
  p_course_scheme text
) returns jsonb
language plpgsql security definer
set search_path='public','catalogue','pipeline','ref'
as $$
declare v_in_scope int:=0; v_retired int:=0; v_levelled int:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  update catalogue.courses c
     set lifecycle_status='inactive',publication_status='unpublished',updated_at=now()
   where c.canonical_source_id=p_source_id
     and exists (select 1 from catalogue.course_identifiers ci where ci.course_id=c.id and ci.source_id=p_source_id and lower(ci.scheme)=lower(p_course_scheme))
     and not exists (
       select 1 from catalogue.course_identifiers ci
       join pipeline.ca_course_scope_keys sk on sk.source_id=p_source_id and sk.scope_tag=p_scope_tag and sk.provider_id=ci.provider_id and lower(sk.course_scheme)=lower(ci.scheme) and sk.identifier=ci.identifier
       where ci.course_id=c.id and ci.source_id=p_source_id and lower(ci.scheme)=lower(p_course_scheme)
     );
  get diagnostics v_retired=row_count;

  update catalogue.courses c
     set lifecycle_status='active',publication_status='unpublished',
         study_level_id=sl.id,updated_at=now()
    from catalogue.course_identifiers ci
    join pipeline.ca_course_scope_keys sk on sk.source_id=p_source_id and sk.scope_tag=p_scope_tag and lower(sk.course_scheme)=lower(ci.scheme) and sk.provider_id=ci.provider_id and sk.identifier=ci.identifier
    left join ref.study_levels sl on sl.code=sk.study_level_code
   where ci.course_id=c.id and ci.source_id=p_source_id and lower(ci.scheme)=lower(p_course_scheme);
  get diagnostics v_in_scope=row_count;
  select count(*) into v_levelled from catalogue.courses c join catalogue.course_identifiers ci on ci.course_id=c.id join pipeline.ca_course_scope_keys sk on sk.source_id=p_source_id and sk.scope_tag=p_scope_tag and sk.provider_id=ci.provider_id and lower(sk.course_scheme)=lower(ci.scheme) and sk.identifier=ci.identifier where ci.source_id=p_source_id and lower(ci.scheme)=lower(p_course_scheme) and c.study_level_id is not null;
  return jsonb_build_object('scope_tag',p_scope_tag,'in_scope',v_in_scope,'retired',v_retired,'levelled',v_levelled);
end $$;
revoke all on function public.svc_layer1_apply_course_scope(uuid,text,text) from public,anon,authenticated;
grant execute on function public.svc_layer1_apply_course_scope(uuid,text,text) to service_role;
