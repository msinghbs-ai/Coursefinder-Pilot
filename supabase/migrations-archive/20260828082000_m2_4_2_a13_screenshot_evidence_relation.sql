-- M2.4.2 A13 — relate retained screenshot Evidence to HTML/raw Evidence for private thumbnail display.
begin;

create or replace function security.admin_evidence_related_visual(p_evidence_id uuid)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','pipeline','storage'
as $$
  select case when se.id is null then null else jsonb_build_object(
    'id',se.id,
    'evidence_type',se.evidence_type,
    'mime_type',se.mime_type,
    'captured_at',se.captured_at,
    'content_hash',se.content_hash,
    'storage_available',so.id is not null,
    'preview_allowed',(so.id is not null and lower(coalesce(se.mime_type,'')) in ('image/png','image/jpeg','image/webp')),
    'source_url',se.source_url
  ) end
  from pipeline.layer2_provider_attempts pa
  join pipeline.evidence_artifacts se on se.id=pa.screenshot_evidence_id
  left join storage.objects so on so.bucket_id='evidence' and so.name=se.storage_path
  left join pipeline.evidence_artifacts cur on cur.id=p_evidence_id
  where pa.screenshot_evidence_id is not null
    and (
      pa.raw_evidence_id=p_evidence_id
      or pa.html_evidence_id=p_evidence_id
      or pa.screenshot_evidence_id=p_evidence_id
      or pa.id::text=coalesce(cur.metadata->>'attempt_id','')
      or coalesce(cur.metadata->>'source_evidence_id','') in (
        coalesce(pa.raw_evidence_id::text,''),
        coalesce(pa.html_evidence_id::text,''),
        coalesce(pa.screenshot_evidence_id::text,'')
      )
    )
  order by pa.completed_at desc nulls last
  limit 1
$$;

revoke all on function security.admin_evidence_related_visual(uuid) from public,anon,authenticated;

do $$
declare v_oid oid;v_def text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='security' and p.proname='admin_evidence_detail'
    and pg_get_function_identity_arguments(p.oid)='p_evidence_id uuid';
  if v_oid is null then raise exception 'admin_evidence_detail not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('related_visual' in v_def)=0 then
    v_def:=replace(
      v_def,
      '''source'',case when s.id is null',
      '''related_visual'',security.admin_evidence_related_visual(e.id),''source'',case when s.id is null'
    );
    execute v_def;
  end if;
end $$;

commit;
