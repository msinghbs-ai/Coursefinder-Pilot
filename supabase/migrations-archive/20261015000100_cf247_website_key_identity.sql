-- CF-247 (Platform Admin, 15 Oct 2026 07:43: "I need to send api to developers and need to do clean-up and make it streamline"). Decision
-- (multiple choice): "New developer key": a separate Pilot key for the website developers, with its own identity and rate limit; the
-- existing Wix key is unchanged. Keys are stored only as SHA-256 in private.website_integration_credentials (rows are added there directly,
-- never in this repository).
--   website_edge_identity_v1 returns the credential name for a key that is enabled (null otherwise). wix-course-api uses it as the
--   rate-limit identity; the original Wix key keeps its rate-limit name and both contracts; any other key may use website-search-v2 only.
--   website_edge_auth_v1 is unchanged. Nothing dropped or deleted.

CREATE OR REPLACE FUNCTION api.website_integration_identity_v1(p_token_sha256 text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$
  select c.credential_name from private.website_integration_credentials c
   where c.enabled and c.token_sha256 = lower(coalesce(p_token_sha256, '')) order by c.created_at limit 1
$function$;
revoke all on function api.website_integration_identity_v1(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.website_edge_identity_v1(p_token_sha256 text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'api'
AS $function$ select api.website_integration_identity_v1(p_token_sha256); $function$;
revoke all on function public.website_edge_identity_v1(text) from public, anon, authenticated;
grant execute on function public.website_edge_identity_v1(text) to service_role;
