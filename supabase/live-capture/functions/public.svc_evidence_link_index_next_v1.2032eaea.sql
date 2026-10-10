CREATE OR REPLACE FUNCTION public.svc_evidence_link_index_next_v1(p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'path',x.storage_path,'mime',x.mime_type,'url',x.source_url,'type',x.evidence_type)),'[]'::jsonb)
  from (select e.id, e.storage_path, e.mime_type, e.source_url, e.evidence_type
        from pipeline.evidence_artifacts e
        left join pipeline.evidence_link_index_state st on st.evidence_id=e.id
        join pipeline.sources s on s.id=e.source_id
        join pipeline.layer2_onboarding_snapshot o on o.provider_id=s.provider_id
        where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
          and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
          and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
          and (st.evidence_id is null or (st.status='error' and st.indexed_at < now()-interval '6 hours'))
        order by o.rank_no, e.captured_at desc nulls last
        limit greatest(1,least(coalesce(p_limit,60),200))) x
$function$
