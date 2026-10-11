CREATE OR REPLACE FUNCTION public.admin_scholarship_publishing(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
AS $function$ select security.admin_scholarship_publishing_v1(p_action,coalesce(p_args,'{}'::jsonb)) $function$
