-- CourseFinder Zoho Pilot: public service-role-only Edge wrappers + one-call reference bundle.
-- Runtime-aligned corrective mirror, 31 Aug 2026.
-- No canonical writes. No anon/authenticated execute grants.

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

create or replace function public.zoho_edge_reference_bundle_v1()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, catalogue, ref, search
as $$
with countries as (
  select jsonb_agg(
    jsonb_build_object(
      'code', c.iso_alpha2,
      'name', c.name,
      'coverage_state', case
        when c.iso_alpha2 in ('AU','NZ') then 'live_regulatory'
        when c.iso_alpha2 = 'CA' then 'beta_limited'
        else 'not_admitted'
      end
    )
    order by case c.iso_alpha2 when 'AU' then 1 when 'NZ' then 2 when 'CA' then 3 else 99 end
  ) as items
  from ref.countries c
  where c.iso_alpha2 in ('AU','NZ','CA')
),
subdivisions as (
  select jsonb_agg(
    jsonb_build_object(
      'code', s.code,
      'name', s.name,
      'country_code', c.iso_alpha2
    )
    order by c.iso_alpha2, s.name
  ) as items
  from ref.subdivisions s
  join ref.countries c on c.id=s.country_id
  where c.iso_alpha2 in ('AU','NZ','CA')
    and coalesce(s.status,'active') = 'active'
),
providers as (
  select jsonb_agg(
    jsonb_build_object(
      'provider_id', p.stable_key,
      'name', p.canonical_name,
      'display_name', p.display_name,
      'country_code', c.iso_alpha2,
      'website', p.website,
      'lifecycle_status', p.lifecycle_status,
      'publication_status', p.publication_status,
      'freshness', jsonb_build_object(
        'last_verified_at', p.last_verified_at,
        'updated_at', p.updated_at
      )
    )
    order by c.iso_alpha2, lower(p.canonical_name), p.stable_key
  ) as items
  from catalogue.providers p
  join ref.countries c on c.id=p.country_id
  where c.iso_alpha2 in ('AU','NZ','CA')
),
provider_counts as (
  select jsonb_object_agg(country_code, provider_count) as counts
  from (
    select c.iso_alpha2 as country_code, count(*)::int as provider_count
    from catalogue.providers p
    join ref.countries c on c.id=p.country_id
    where c.iso_alpha2 in ('AU','NZ','CA')
    group by c.iso_alpha2
  ) x
),
course_counts as (
  select jsonb_object_agg(country_code, course_count) as counts
  from (
    select d.country_code, count(*)::int as course_count
    from search.course_documents d
    where d.country_code in ('AU','NZ','CA')
    group by d.country_code
  ) x
),
top_fields as (
  select jsonb_agg(
    jsonb_build_object(
      'code', primary_field_code,
      'name', primary_field_name,
      'courses', course_count
    )
    order by course_count desc, primary_field_name
  ) as items
  from (
    select primary_field_code, primary_field_name, count(*)::int as course_count
    from search.course_documents
    where country_code in ('AU','NZ')
      and primary_field_name is not null
    group by primary_field_code, primary_field_name
    order by count(*) desc, primary_field_name
    limit 8
  ) x
)
select jsonb_build_object(
  'contract_version','zoho-integration-v1',
  'resource','reference_bundle',
  'generated_at',now(),
  'countries',coalesce((select items from countries),'[]'::jsonb),
  'subdivisions',coalesce((select items from subdivisions),'[]'::jsonb),
  'providers',coalesce((select items from providers),'[]'::jsonb),
  'platform_stats',jsonb_build_object(
    'provider_counts',coalesce((select counts from provider_counts),'{}'::jsonb),
    'course_counts',coalesce((select counts from course_counts),'{}'::jsonb),
    'top_study_areas',coalesce((select items from top_fields),'[]'::jsonb)
  )
);
$$;

revoke all on function public.zoho_edge_auth_v1(text) from public, anon, authenticated;
revoke all on function public.zoho_edge_rate_check_v1(text,text,integer,integer) from public, anon, authenticated;
revoke all on function public.zoho_edge_course_lookup_v1(text) from public, anon, authenticated;
revoke all on function public.zoho_edge_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function public.zoho_edge_provider_search_v1(text,text,timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function public.zoho_edge_filter_options_v1(text,text,text,integer,integer) from public, anon, authenticated;
revoke all on function public.zoho_edge_reference_bundle_v1() from public, anon, authenticated;

grant execute on function public.zoho_edge_auth_v1(text) to service_role;
grant execute on function public.zoho_edge_rate_check_v1(text,text,integer,integer) to service_role;
grant execute on function public.zoho_edge_course_lookup_v1(text) to service_role;
grant execute on function public.zoho_edge_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) to service_role;
grant execute on function public.zoho_edge_provider_search_v1(text,text,timestamptz,integer,integer) to service_role;
grant execute on function public.zoho_edge_filter_options_v1(text,text,text,integer,integer) to service_role;
grant execute on function public.zoho_edge_reference_bundle_v1() to service_role;
