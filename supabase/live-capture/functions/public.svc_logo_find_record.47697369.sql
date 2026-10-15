CREATE OR REPLACE FUNCTION public.svc_logo_find_record(p_provider_id uuid, p_status text, p_reason text, p_method text, p_storage_path text, p_mime_type text, p_content_hash text, p_width integer, p_height integer, p_source_url text, p_page_url text, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_asset uuid; v_status text := p_status;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_status not in ('found', 'not_found', 'failed') then raise exception 'unknown status %', p_status; end if;
  if p_status = 'found' then
    if p_storage_path is null or p_content_hash is null or p_mime_type not in ('image/svg+xml', 'image/png', 'image/jpeg', 'image/webp') then raise exception 'stored logo required'; end if;
    if exists (select 1 from catalogue.provider_assets a where a.provider_id = p_provider_id and a.is_primary and a.status = 'approved' and a.asset_type in ('logo', 'logo_dark', 'logo_light')) then
      v_status := 'skipped_has_logo';  -- a person added one meanwhile: theirs stays
    else
      insert into catalogue.provider_assets(provider_id, asset_type, source_url, storage_path, mime_type, width, height, content_hash, is_primary, status, observed_at, verified_at, metadata)
      values (p_provider_id, 'logo', p_source_url, p_storage_path, p_mime_type, p_width, p_height, p_content_hash, true, 'approved', now(), now(),
              jsonb_build_object('source_class', 'website_logo_finder', 'method', p_method, 'page_url', p_page_url, 'managed_storage', true, 'change_control_ref', 'CF-CHG-20260915-247') || coalesce(p_evidence, '{}'::jsonb))
      on conflict (provider_id, asset_type, coalesce(content_hash, ''), source_url) do update
        set storage_path = excluded.storage_path, is_primary = true, status = 'approved', verified_at = now(), metadata = catalogue.provider_assets.metadata || excluded.metadata
      returning id into v_asset;
      update pipeline.enrichment_flags set cleared_at = now() where entity = 'provider' and entity_key = p_provider_id::text and field = 'logo' and cleared_at is null;
    end if;
  else
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    values ('provider', p_provider_id::text, p_provider_id, 'logo', 'logo_not_found', coalesce(p_reason, 'no logo on the home page'), 'logo-find')
    on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
  end if;
  update pipeline.provider_logo_finds set status = v_status, reason = p_reason, method = p_method, source_url = p_source_url, page_url = p_page_url,
         provider_asset_id = coalesce(v_asset, provider_asset_id), updated_at = now()
   where provider_id = p_provider_id;
  return jsonb_build_object('provider_id', p_provider_id, 'status', v_status, 'provider_asset_id', v_asset);
end $function$
