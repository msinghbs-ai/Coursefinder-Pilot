CREATE OR REPLACE FUNCTION public.website_edge_auth_v1(p_token_sha256 text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'api'
AS $function$ select api.website_integration_auth_v1(p_token_sha256); $function$
