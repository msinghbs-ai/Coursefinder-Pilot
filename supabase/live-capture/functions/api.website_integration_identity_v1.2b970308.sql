CREATE OR REPLACE FUNCTION api.website_integration_identity_v1(p_token_sha256 text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$
  select c.credential_name from private.website_integration_credentials c
   where c.enabled and c.token_sha256 = lower(coalesce(p_token_sha256, '')) order by c.created_at limit 1
$function$
