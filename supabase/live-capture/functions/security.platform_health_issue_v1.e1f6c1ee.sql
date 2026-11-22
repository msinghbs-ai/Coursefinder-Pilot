CREATE OR REPLACE FUNCTION security.platform_health_issue_v1(p_key text, p_severity text, p_area text, p_title text, p_detail jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$ select jsonb_build_object('check_key',p_key,'severity',p_severity,'area',p_area,'title',p_title,'detail',coalesce(p_detail,'{}'::jsonb)) $function$
