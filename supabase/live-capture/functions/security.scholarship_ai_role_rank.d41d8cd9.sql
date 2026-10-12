CREATE OR REPLACE FUNCTION security.scholarship_ai_role_rank()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security'
AS $function$
 select coalesce(max(r.rank),0)::int from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=auth.uid() and r.status='active' and (ur.expires_at is null or ur.expires_at>now())
$function$
