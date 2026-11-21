-- CF-247 S1-RM-Design s951 (P0, Platform Admin 21 Nov 2026 20:12 AEDT, from the website developer's report: "HTTP 503, SERVICE_UNAVAILABLE" on
-- website-api-v3 search and destination, request ids 2cd7d848-f518-4276-90f3-8cdfdf6b7e2e and abe9f30c-afd7-4ad8-be33-984ca86c162f).
-- Found (read live, 21 Nov 2026 20:15 AEDT): since s935 (#1458, deployed about 18:11 AEDT) website-api-v3 and zoho-api-v3 call pipeline.api_key_auth_v1 and
--   pipeline.api_request_log_v1 through the API gateway with svc.schema("pipeline"). The gateway only serves the exposed schemas (public), so every call
--   returns HTTP 406 (edge logs: POST /rest/v1/rpc/api_key_auth_v1 406, 07:11 to 09:11 UTC) and the function answers 503 before any key is checked.
--   Every v3 call has failed since then, whatever the key (the v2 bridge key and the newly rotated website_developer_v3 alike). v2 and v1 are not affected.
-- What changes (live on deploy):
--   public.api_key_auth_v1 and public.api_request_log_v1: thin service-role-only entry points in the exposed schema that call the pipeline functions unchanged.
--   website-api-v3 and zoho-api-v3 call them with svc.rpc(...) (no schema switch), in the same PR.
-- Not changed: the sign-in and log rules (pipeline.api_key_auth_v1 and pipeline.api_request_log_v1 are untouched), the keys, the frozen consumer API (G3: 75
--   functions and 48 relations, checked before and after; the two new public functions are not in the consumer surface), the manual locks, the jobs.
--   No AI, no Firecrawl. Nothing dropped or deleted.
-- Parity: live head 20261122010000 (2,252 versions) read 21 Nov 2026 20:16 AEDT; no open Pilot PR; this file is numbered strictly above it.
-- Replaces: v3's calls into the unexposed pipeline schema (svc.schema("pipeline").rpc) with calls to the public entry points.
-- Retires: nothing.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if to_regprocedure('pipeline.api_key_auth_v1(text,text,text)') is null or to_regprocedure('pipeline.api_request_log_v1(text,text,text,text,integer,integer,integer,bigint,text,text)') is null then
    raise exception 'pre-check: the s935 sign-in and log functions are missing';
  end if;
end $g$;

create or replace function public.api_key_auth_v1(p_platform text, p_version text, p_token_sha256 text) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
begin
  if coalesce(auth.role(), '') <> 'service_role' and session_user <> 'postgres' then raise exception 'service_role required'; end if;
  return pipeline.api_key_auth_v1(p_platform, p_version, p_token_sha256);
end $f$;
revoke all on function public.api_key_auth_v1(text, text, text) from public, anon, authenticated;
grant execute on function public.api_key_auth_v1(text, text, text) to service_role;
comment on function public.api_key_auth_v1(text, text, text) is 'CF-247 s951: the exposed entry point for pipeline.api_key_auth_v1 (sign-in by consumer and API version), so website-api-v3 and zoho-api-v3 can reach it through the API gateway. Service role only.';

create or replace function public.api_request_log_v1(p_platform text, p_version text, p_key_name text, p_action text, p_status int, p_elapsed_ms int,
                                                     p_items int, p_bytes bigint, p_error_code text, p_request_id text) returns void
language plpgsql security definer set search_path to '' as $f$
begin
  if coalesce(auth.role(), '') <> 'service_role' and session_user <> 'postgres' then raise exception 'service_role required'; end if;
  perform pipeline.api_request_log_v1(p_platform, p_version, p_key_name, p_action, p_status, p_elapsed_ms, p_items, p_bytes, p_error_code, p_request_id);
end $f$;
revoke all on function public.api_request_log_v1(text, text, text, text, int, int, int, bigint, text, text) from public, anon, authenticated;
grant execute on function public.api_request_log_v1(text, text, text, text, int, int, int, bigint, text, text) to service_role;
comment on function public.api_request_log_v1(text, text, text, text, int, int, int, bigint, text, text) is 'CF-247 s951: the exposed entry point for pipeline.api_request_log_v1 (one consumer API call logged with its own version and key), so website-api-v3 and zoho-api-v3 can reach it through the API gateway. Service role only.';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'public.api_key_auth_v1', 'Service', 'Search and API', 'Exposed entry point for pipeline.api_key_auth_v1 (v3 sign-in through the API gateway)', 'active', '{}', '20261122020000'),
  ('function', 'public.api_request_log_v1', 'Service', 'Search and API', 'Exposed entry point for pipeline.api_request_log_v1 (v3 request log through the API gateway)', 'active', '{}', '20261122020000')
on conflict do nothing;

do $p$
declare v jsonb := security.consumer_api_check_v1(); w jsonb; z jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  -- the entry points answer as the pipeline functions do: the v2 website key still signs in on v3 during its bridge, a Zoho v2 key does not
  w := public.api_key_auth_v1('website', 'v3', (select token_sha256 from private.api_keys where key_name = 'website_developer_v2'));
  z := public.api_key_auth_v1('zoho', 'v3', (select token_sha256 from private.api_keys where key_name = 'zoho_creator_v2'));
  if w is distinct from pipeline.api_key_auth_v1('website', 'v3', (select token_sha256 from private.api_keys where key_name = 'website_developer_v2')) then
    raise exception 'post-check: public.api_key_auth_v1 differs from pipeline.api_key_auth_v1';
  end if;
  if z is not null then raise exception 'post-check: a Zoho v2 key signs in on Zoho v3'; end if;
  if has_function_privilege('anon', 'public.api_key_auth_v1(text,text,text)', 'execute') or has_function_privilege('authenticated', 'public.api_key_auth_v1(text,text,text)', 'execute') then
    raise exception 'post-check: the sign-in entry point is open to anon or authenticated';
  end if;
  raise notice 's951: website v3 with the v2 key -> %', coalesce(w->>'key_name', 'not accepted (bridge ended or v3 key issued)');
end $p$;
