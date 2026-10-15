CREATE OR REPLACE FUNCTION api.zoho_integration_auth_v1(p_token_sha256 text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$
  select exists(
    select 1
    from private.zoho_integration_credentials c
    where c.credential_name = 'coursefinder_zoho_pilot_v1'
      and c.enabled
      and c.token_sha256 = lower(coalesce(p_token_sha256,''))
  );
$function$
