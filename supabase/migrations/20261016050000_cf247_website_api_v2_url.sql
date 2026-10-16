-- CF-247 (16 Oct 2026): Website API v2 at its own URL (website-api-v2), in parallel with the current one. Platform Admin 16 Oct 2026 09:55:
-- "I want a separate URL for each API version going forward. Lets keep it simple not with contracts calling in the URL"; 11:43: "Can we
-- build the Website v2 URL as parallel without disturbing api v2 through v1 url with contract?"
-- The new URL serves the same nine actions from the same public.website_v2_* functions, so the answers are the same as
-- wix-course-api with "contract":"website-search-v2" (plus api_version). No contract field. Its own key (private.api_keys, platform
-- website), its own rate limit per key (setting website.rate_per_minute) and every call logged in pipeline.api_requests, shown on
-- Operations > API usage. wix-course-api (v1 and the contract path) is not changed; the website moves when its developer is ready.
-- Replaces: nothing (the contract path on wix-course-api stays until the website has moved; then it is retired by its own change)
-- Retires: nothing
-- No new tables or jobs. Nothing dropped or deleted.

-- 1 Setting
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'website.rate_per_minute', 'Website API v2 calls per minute, per key', 'Each key on the website-api-v2 URL may make this many calls a minute (all actions together); more are answered 429 with Retry-After. A key can have its own figure.', 'number', to_jsonb(300), 10, 2000, 'calls', 760, 'Platform Admin 16 Oct 2026: website v2 at its own URL (the contract path allows 60 a minute per action, nine actions)', 'Website API', 'website-api-v2')
on conflict (toolset_key, key) do nothing;

-- 2 Key: the website developer (only the SHA-256 is kept; the key was handed to the Platform Admin once)
insert into private.api_keys(key_name, platform, api_version, consumer, token_sha256, note) values
 ('website_developer_v2', 'website', 'v2', 'Website (Wix) developer', '4dc4acd40d412a0719636393540dedf42f14ad53b160ca0acc755956a091b736', 'Platform Admin 16 Oct 2026 11:43: website v2 URL in parallel')
on conflict (key_name) do nothing;

-- 3 Service functions for the edge function (service role only)
create or replace function public.website_api_v2_auth(p_token_sha256 text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare k private.api_keys%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into k from private.api_keys where platform = 'website' and api_version = 'v2' and enabled and token_sha256 = lower(coalesce(p_token_sha256, ''));
  if k.key_name is null then return null; end if;
  return jsonb_build_object('key_name', k.key_name, 'rate_per_minute', coalesce(k.rate_per_minute, security.pipeline_num_v1('website.rate_per_minute', 300)::int),
                            'logo_link_days', security.pipeline_num_v1('website.logo_link_days', 365));
end $function$;

create or replace function public.website_api_v2_rate(p_key_name text, p_limit integer)
returns jsonb language plpgsql security definer set search_path = '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return api.zoho_integration_rate_check_v1('website-v2:' || p_key_name, 'all', p_limit, 60);  -- fixed: the limit is per minute
end $function$;

create or replace function public.website_api_v2_log(p_key_name text, p_action text, p_status integer, p_elapsed_ms integer, p_items integer, p_bytes integer, p_error_code text, p_request_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.api_requests(platform, api_version, key_name, action, status, elapsed_ms, items, bytes, error_code, request_id)
  values ('website', 'v2', p_key_name, left(p_action, 40), p_status, p_elapsed_ms, p_items, p_bytes, left(p_error_code, 40), p_request_id);
end $function$;

revoke execute on function public.website_api_v2_auth(text), public.website_api_v2_rate(text, integer),
  public.website_api_v2_log(text, text, integer, integer, integer, integer, text, uuid) from public, anon, authenticated;

-- 4 Register
insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('edge_function', 'website-api-v2', 'Website API', 'Website API v2 at its own URL and key (same answers as the website-search-v2 contract path)', 'active', '20261016050000')
on conflict (kind, name) do nothing;
