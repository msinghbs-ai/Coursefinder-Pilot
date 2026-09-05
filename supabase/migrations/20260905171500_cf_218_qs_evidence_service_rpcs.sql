create or replace function public.svc_ranking_raw_evidence_register(
  p_system_code text,
  p_edition_year integer,
  p_source_url text,
  p_storage_path text,
  p_content_hash text,
  p_mime_type text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','ranking','pipeline'
as $$
declare
  v_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  if not exists (select 1 from ranking.systems where code=p_system_code and active) then
    raise exception 'unsupported ranking system' using errcode='22023';
  end if;
  if p_edition_year<2000 or p_edition_year>2100 then
    raise exception 'invalid edition year' using errcode='22023';
  end if;
  if coalesce(btrim(p_storage_path),'')='' or coalesce(btrim(p_content_hash),'')='' then
    raise exception 'storage path and content hash required' using errcode='22023';
  end if;

  select id into v_id from pipeline.evidence_artifacts where storage_path=p_storage_path limit 1;
  if v_id is not null then return v_id; end if;

  insert into pipeline.evidence_artifacts(
    evidence_type,source_url,storage_path,content_hash,mime_type,captured_at,metadata,
    retention_class,review_state,capture_version,evidence_group_key
  ) values (
    'ranking_publisher_raw',p_source_url,p_storage_path,p_content_hash,p_mime_type,now(),
    jsonb_strip_nulls(coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('ranking_system',p_system_code,'edition_year',p_edition_year)),
    'source_evidence','pending_review',1,
    'ranking:'||p_system_code||':'||p_edition_year::text||':raw:'||left(p_content_hash,16)
  ) returning id into v_id;
  return v_id;
end
$$;
revoke all on function public.svc_ranking_raw_evidence_register(text,integer,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_ranking_raw_evidence_register(text,integer,text,text,text,text,jsonb) to service_role;

create or replace function public.svc_ranking_manual_import_mark_applied(
  p_import_id uuid,
  p_validation_summary jsonb default '{}'::jsonb,
  p_parse_summary jsonb default '{}'::jsonb,
  p_supersede_inline boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','ranking'
as $$
declare
  v_system_id uuid;
  v_year integer;
  v_rejected integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  select system_id,edition_year into v_system_id,v_year from ranking.manual_imports where id=p_import_id;
  if v_system_id is null then raise exception 'ranking import not found' using errcode='P0002'; end if;

  update ranking.manual_imports
  set status='applied', validation_summary=coalesce(p_validation_summary,'{}'::jsonb), parse_summary=coalesce(p_parse_summary,'{}'::jsonb), updated_at=now()
  where id=p_import_id;

  if p_supersede_inline then
    update ranking.manual_imports
    set status='rejected', revision_note='Superseded by Storage-backed canonical reload import '||p_import_id::text, updated_at=now()
    where system_id=v_system_id and edition_year=v_year and id<>p_import_id and storage_path like 'inline://%';
    get diagnostics v_rejected=row_count;
  end if;

  return jsonb_build_object('ok',true,'import_id',p_import_id,'superseded_inline',v_rejected);
end
$$;
revoke all on function public.svc_ranking_manual_import_mark_applied(uuid,jsonb,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.svc_ranking_manual_import_mark_applied(uuid,jsonb,jsonb,boolean) to service_role;
