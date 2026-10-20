CREATE OR REPLACE FUNCTION security.enrich_focus_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- page search runs for every provider when the setting is 0, for providers outside Australia, and for the Australian focus providers
  -- CF-247 19 Oct 2026: and for a provider in a re-find wave (Layer 2 > Build adapter, wave named "refind-...")
  -- CF-247 20 Oct 2026: never for a provider held because its course pages could not be found (until a person releases it)
  select not security.flag_provider_held_v1(p_provider_id, array['course_pages_not_found'])
     and (security.pipeline_num_v1('enrich.focus_top_n', 50) = 0
      or coalesce(security.coverage_country(p_provider_id), '') <> 'AU'
      or exists (select 1 from pipeline.enrich_focus_providers f where f.provider_id = p_provider_id and f.in_focus)
      or exists (select 1 from pipeline.adapter_builds b where b.provider_id = p_provider_id and b.wave like 'refind-%'))
$function$
