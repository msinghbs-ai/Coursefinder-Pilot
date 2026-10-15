CREATE OR REPLACE FUNCTION public.website_edge_identity_v1(p_token_sha256 text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'api'
AS $function$ select api.website_integration_identity_v1(p_token_sha256); $function$
