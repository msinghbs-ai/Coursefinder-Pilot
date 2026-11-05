CREATE OR REPLACE FUNCTION security.website_terms_status_v1(p_kind text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s
                              where s.toolset_key = 'pipeline' and s.key = 'website.' || p_kind || '_display_approved'), false)
              then 'approved' else 'management_decision_pending' end
$function$
