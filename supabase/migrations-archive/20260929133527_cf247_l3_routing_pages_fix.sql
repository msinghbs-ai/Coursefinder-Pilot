-- CF-CHG-20260915-247 Layer 3 model routing: fix to layer3_routing_pages_service (read-only gold-reading helper) -
-- catalogue.courses has display_title/canonical_title, not title. Guarded by the checksum of the definition applied in
-- 20260929230000.
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid='public.layer3_routing_pages_service(uuid[])'::regprocedure)<>'7f4ee1534b7a3468b25f0b667d79f076' then
    raise exception 'layer3_routing_pages_service changed since review; not replaced';
  end if;
end $g$;

create or replace function public.layer3_routing_pages_service(p_course_ids uuid[])
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','security' as $f$
begin
  perform public.layer3_routing_service_guard();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'course_id',p.course_id,'provider_id',p.provider_id,'provider',coalesce(pv.display_name,pv.canonical_name),'course',coalesce(co.display_title,co.canonical_title),'course_code',co.course_code,
      'url',p.url,'evidence_id',p.evidence_id,'storage_path',e.storage_path,'candidates',p.candidates,
      'tuition_target',security.coverage_tuition_target_v1(p.candidates->'fee'),
      'work_item_id',w.id,'work_status',w.status,'work_candidate_context',w.candidate_context,
      'text_evidence_id',te.id,'text_storage_path',te.storage_path,'text_mime',te.mime_type,'text_source_url',te.source_url))
    from pipeline.coverage_course_pages p
    join pipeline.evidence_artifacts e on e.id=p.evidence_id
    join catalogue.courses co on co.id=p.course_id
    join catalogue.providers pv on pv.id=p.provider_id
    left join pipeline.layer3_work_items w on w.id=p.l3_work_item_id
    left join pipeline.evidence_artifacts te on te.id=w.evidence_id
   where p.course_id=any(p_course_ids)),'[]'::jsonb);
end $f$;
