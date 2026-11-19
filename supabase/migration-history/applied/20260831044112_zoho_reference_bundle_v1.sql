
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

revoke all on function public.zoho_edge_reference_bundle_v1() from public, anon, authenticated;
grant execute on function public.zoho_edge_reference_bundle_v1() to service_role;
