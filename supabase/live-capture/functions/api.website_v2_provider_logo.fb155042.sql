CREATE OR REPLACE FUNCTION api.website_v2_provider_logo(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'catalogue'
AS $function$
  select jsonb_build_object('storage_path', a.storage_path, 'mime_type', a.mime_type, 'content_hash', a.content_hash,
           'updated_at', coalesce(a.verified_at, a.observed_at), 'source_url', a.source_url,
           'attribution', 'Logo of the provider, from the provider''s own website', 'terms_status', 'management_decision_pending')
  from catalogue.provider_assets a
  where a.provider_id = p_provider_id and a.asset_type = 'logo' and a.status = 'approved' and a.is_primary and a.storage_path is not null
  order by coalesce(a.verified_at, a.observed_at) desc nulls last limit 1
$function$
