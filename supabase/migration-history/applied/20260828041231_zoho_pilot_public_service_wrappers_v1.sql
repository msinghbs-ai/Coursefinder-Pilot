
create or replace function public.zoho_edge_auth_v1(p_token_sha256 text)
returns boolean
language sql
security definer
set search_path = public, api
as $$
  select api.zoho_integration_auth_v1(p_token_sha256);
$$;

create or replace function public.zoho_edge_rate_check_v1(
  p_identity text,
  p_resource text,
  p_limit integer,
  p_window_seconds integer
)
returns jsonb
language sql
security definer
set search_path = public, api
as $$
  select api.zoho_integration_rate_check_v1(p_identity,p_resource,p_limit,p_window_seconds);
$$;

create or replace function public.zoho_edge_course_lookup_v1(p_identifier text)
returns jsonb
language sql
security definer
set search_path = public, api
as $$
  select api.zoho_course_lookup_v1(p_identifier);
$$;

create or replace function public.zoho_edge_course_search_v1(
  p_query text,
  p_country_codes text[],
  p_provider_ids text[],
  p_subdivision_codes text[],
  p_has_scholarship boolean,
  p_changed_since timestamptz,
  p_limit integer,
  p_offset integer
)
returns jsonb
language sql
security definer
set search_path = public, api
as $$
  select api.zoho_course_search_v1(
    p_query,p_country_codes,p_provider_ids,p_subdivision_codes,
    p_has_scholarship,p_changed_since,p_limit,p_offset
  );
$$;

create or replace function public.zoho_edge_provider_search_v1(
  p_query text,
  p_country_code text,
  p_changed_since timestamptz,
  p_limit integer,
  p_offset integer
)
returns jsonb
language sql
security definer
set search_path = public, api
as $$
  select api.zoho_provider_search_v1(
    p_query,p_country_code,p_changed_since,p_limit,p_offset
  );
$$;

create or replace function public.zoho_edge_filter_options_v1(
  p_kind text,
  p_country_code text,
  p_query text,
  p_limit integer,
  p_offset integer
)
returns jsonb
language sql
security definer
set search_path = public, api
as $$
  select api.zoho_filter_options_v1(
    p_kind,p_country_code,p_query,p_limit,p_offset
  );
$$;

revoke all on function public.zoho_edge_auth_v1(text) from public, anon, authenticated;
revoke all on function public.zoho_edge_rate_check_v1(text,text,integer,integer) from public, anon, authenticated;
revoke all on function public.zoho_edge_course_lookup_v1(text) from public, anon, authenticated;
revoke all on function public.zoho_edge_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function public.zoho_edge_provider_search_v1(text,text,timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function public.zoho_edge_filter_options_v1(text,text,text,integer,integer) from public, anon, authenticated;

grant execute on function public.zoho_edge_auth_v1(text) to service_role;
grant execute on function public.zoho_edge_rate_check_v1(text,text,integer,integer) to service_role;
grant execute on function public.zoho_edge_course_lookup_v1(text) to service_role;
grant execute on function public.zoho_edge_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) to service_role;
grant execute on function public.zoho_edge_provider_search_v1(text,text,timestamptz,integer,integer) to service_role;
grant execute on function public.zoho_edge_filter_options_v1(text,text,text,integer,integer) to service_role;
