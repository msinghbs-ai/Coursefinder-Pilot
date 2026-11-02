CREATE OR REPLACE FUNCTION security.provider_description_stored_v1(p_provider uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select a.id
    from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id = s.id
   where s.provider_id = p_provider and a.storage_path is not null and a.source_url ~* '^https?://'
     and coalesce(a.mime_type, 'text/html') ~* 'html|markdown|text'
     and coalesce(a.captured_at, a.created_at) > now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int)
     -- pilot 2 Nov 2026 16:16: the page rule (a held news article was used because "about" was one of its path parts)
     and (security.provider_description_page_v1(p_provider, a.source_url)->>'ok')::boolean
   order by (security.provider_description_page_v1(p_provider, a.source_url)->>'main_host')::boolean desc, coalesce(a.captured_at, a.created_at) desc, a.id
   limit 1
$function$
