CREATE OR REPLACE FUNCTION security.provider_description_stored_candidate_v1(p_provider uuid, p_patterns text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER COST 10
 SET search_path TO ''
AS $function$
  -- a necessary condition of security.provider_description_stored_v1, in one index probe: a stored, recent copy whose address looks like an About page. The page rule and host proof still run later, on the few providers that pass.
  select exists (select 1 from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id = s.id
                  where s.provider_id = p_provider and a.storage_path is not null and a.source_url ~* '^https?://'
                    and lower(a.source_url) like any (p_patterns)
                    and coalesce(a.captured_at, a.created_at) > now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int))
$function$
