
create or replace function api.zoho_course_search_v2(
  p_query text default null,
  p_country_codes text[] default null,
  p_provider_ids text[] default null,
  p_subdivision_codes text[] default null,
  p_study_level_codes text[] default null,
  p_primary_field_codes text[] default null,
  p_delivery_modes text[] default null,
  p_has_scholarship boolean default null,
  p_has_intake boolean default null,
  p_has_english boolean default null,
  p_has_provider_current_tuition boolean default null,
  p_has_regulatory_tuition boolean default null,
  p_has_link boolean default null,
  p_intake_years integer[] default null,
  p_intake_labels text[] default null,
  p_english_test_codes text[] default null,
  p_min_provider_annual_tuition numeric default null,
  p_max_provider_annual_tuition numeric default null,
  p_min_regulatory_total_tuition numeric default null,
  p_max_regulatory_total_tuition numeric default null,
  p_publication_statuses text[] default null,
  p_changed_since timestamptz default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb
language sql
security definer
set search_path = 'pg_catalog','search','api'
as $$
with base as (
  select d.*
  from search.course_documents d
  where (
      p_query is null or btrim(p_query)='' or
      d.search_tsv @@ websearch_to_tsquery('english', btrim(p_query)) or
      d.course_title ilike '%' || btrim(p_query) || '%' or
      d.provider_name ilike '%' || btrim(p_query) || '%' or
      lower(d.course_code)=lower(btrim(p_query)) or
      lower(d.course_stable_key)=lower(btrim(p_query))
    )
    and (p_country_codes is null or d.country_code = any(p_country_codes))
    and (p_provider_ids is null or d.provider_stable_key = any(p_provider_ids))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_study_level_codes is null or d.study_level_code = any(p_study_level_codes))
    and (p_primary_field_codes is null or d.primary_field_code = any(p_primary_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (p_has_intake is null or d.has_intake=p_has_intake)
    and (p_has_english is null or d.has_english=p_has_english)
    and (p_has_provider_current_tuition is null or d.has_provider_current_tuition=p_has_provider_current_tuition)
    and (p_has_regulatory_tuition is null or d.has_regulatory_tuition=p_has_regulatory_tuition)
    and (p_has_link is null or d.has_link=p_has_link)
    and (p_publication_statuses is null or d.publication_status = any(p_publication_statuses))
    and (
      p_intake_years is null or exists (
        select 1 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) x
        where (x->>'year') ~ '^[0-9]+$' and (x->>'year')::int = any(p_intake_years)
      )
    )
    and (
      p_intake_labels is null or exists (
        select 1 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) x
        where x->>'label' = any(p_intake_labels)
      )
    )
    and (
      p_english_test_codes is null or exists (
        select 1 from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) x
        where x->>'test_code' = any(p_english_test_codes)
      )
    )
    and (p_min_provider_annual_tuition is null or d.provider_annual_tuition_amount >= p_min_provider_annual_tuition)
    and (p_max_provider_annual_tuition is null or d.provider_annual_tuition_amount <= p_max_provider_annual_tuition)
    and (p_min_regulatory_total_tuition is null or d.regulatory_tuition_amount >= p_min_regulatory_total_tuition)
    and (p_max_regulatory_total_tuition is null or d.regulatory_tuition_amount <= p_max_regulatory_total_tuition)
    and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)
),
page as (
  select * from base
  order by lower(course_title), course_stable_key
  limit greatest(1, least(coalesce(p_limit,20),50))
  offset greatest(coalesce(p_offset,0),0)
)
select jsonb_build_object(
  'contract_version','zoho-integration-v2',
  'resource','courses',
  'items',coalesce(jsonb_agg(jsonb_build_object(
    'course_id',course_stable_key,
    'course_code',course_code,
    'title',course_title,
    'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
    'country_code',country_code,
    'study_level',jsonb_build_object('code',study_level_code),
    'field',jsonb_build_object('code',primary_field_code,'name',primary_field_name),
    'subdivision_codes',coalesce(to_jsonb(subdivision_codes),'[]'::jsonb),
    'delivery_modes',coalesce(to_jsonb(delivery_modes),'[]'::jsonb),
    'regulatory_tuition',jsonb_build_object(
      'state',regulatory_tuition_state,'amount',regulatory_tuition_amount,
      'currency',regulatory_tuition_currency,'basis',regulatory_tuition_basis
    ),
    'provider_current_tuition',jsonb_build_object(
      'has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,
      'annual_currency',provider_annual_tuition_currency
    ),
    'official_course_url',official_course_url,
    'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship,
    'earliest_intake_date',earliest_intake_date,
    'publication_status',publication_status,
    'freshness',jsonb_build_object(
      'source_updated_at',source_updated_at,'projection_updated_at',updated_at,'generated_at',generated_at
    )
  ) order by lower(course_title), course_stable_key),'[]'::jsonb),
  'page',jsonb_build_object(
    'limit',greatest(1, least(coalesce(p_limit,20),50)),
    'offset',greatest(coalesce(p_offset,0),0),
    'total',(select count(*) from base)
  ),
  'ordering','title_asc,course_id_asc',
  'generated_at',now()
) from page;
$$;

revoke all on function api.zoho_course_search_v2(
  text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,
  integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamptz,integer,integer
) from public, anon, authenticated;
grant execute on function api.zoho_course_search_v2(
  text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,
  integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamptz,integer,integer
) to service_role;

create or replace function public.zoho_edge_course_search_v2(
  p_query text default null,
  p_country_codes text[] default null,
  p_provider_ids text[] default null,
  p_subdivision_codes text[] default null,
  p_study_level_codes text[] default null,
  p_primary_field_codes text[] default null,
  p_delivery_modes text[] default null,
  p_has_scholarship boolean default null,
  p_has_intake boolean default null,
  p_has_english boolean default null,
  p_has_provider_current_tuition boolean default null,
  p_has_regulatory_tuition boolean default null,
  p_has_link boolean default null,
  p_intake_years integer[] default null,
  p_intake_labels text[] default null,
  p_english_test_codes text[] default null,
  p_min_provider_annual_tuition numeric default null,
  p_max_provider_annual_tuition numeric default null,
  p_min_regulatory_total_tuition numeric default null,
  p_max_regulatory_total_tuition numeric default null,
  p_publication_statuses text[] default null,
  p_changed_since timestamptz default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb
language sql
security definer
set search_path='public','api'
as $$
  select api.zoho_course_search_v2(
    p_query,p_country_codes,p_provider_ids,p_subdivision_codes,p_study_level_codes,p_primary_field_codes,
    p_delivery_modes,p_has_scholarship,p_has_intake,p_has_english,p_has_provider_current_tuition,
    p_has_regulatory_tuition,p_has_link,p_intake_years,p_intake_labels,p_english_test_codes,
    p_min_provider_annual_tuition,p_max_provider_annual_tuition,p_min_regulatory_total_tuition,
    p_max_regulatory_total_tuition,p_publication_statuses,p_changed_since,p_limit,p_offset
  );
$$;

revoke all on function public.zoho_edge_course_search_v2(
  text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,
  integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamptz,integer,integer
) from public, anon, authenticated;
grant execute on function public.zoho_edge_course_search_v2(
  text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,
  integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamptz,integer,integer
) to service_role;

create or replace function public.zoho_edge_reference_bundle_v1()
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, catalogue, ref, search
as $$
with provider_course_counts as (
  select provider_stable_key, count(*)::int as search_course_count
  from search.course_documents
  where country_code in ('AU','NZ','CA')
  group by provider_stable_key
),
countries as (
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
      'search_course_count',coalesce(pc.search_course_count,0),
      'freshness', jsonb_build_object(
        'last_verified_at', p.last_verified_at,
        'updated_at', p.updated_at
      )
    )
    order by c.iso_alpha2, lower(p.canonical_name), p.stable_key
  ) as items
  from catalogue.providers p
  join ref.countries c on c.id=p.country_id
  left join provider_course_counts pc on pc.provider_stable_key=p.stable_key
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
study_levels as (
  select jsonb_agg(jsonb_build_object(
    'code',study_level_code,'name',initcap(replace(study_level_code,'_',' ')),
    'courses',course_count,'country_counts',country_counts
  ) order by course_count desc, study_level_code) items
  from (
    select study_level_code, sum(country_count)::int course_count,
      jsonb_object_agg(country_code,country_count) country_counts
    from (
      select study_level_code,country_code,count(*)::int country_count
      from search.course_documents
      where country_code in ('AU','NZ') and study_level_code is not null
      group by study_level_code,country_code
    ) x
    group by study_level_code
  ) y
),
study_areas as (
  select jsonb_agg(jsonb_build_object(
    'code',primary_field_code,'name',primary_field_name,'courses',course_count,'country_counts',country_counts
  ) order by course_count desc, primary_field_name) items
  from (
    select primary_field_code,max(primary_field_name) primary_field_name,sum(country_count)::int course_count,
      jsonb_object_agg(country_code,country_count) country_counts
    from (
      select primary_field_code,primary_field_name,country_code,count(*)::int country_count
      from search.course_documents
      where country_code in ('AU','NZ') and primary_field_code is not null
      group by primary_field_code,primary_field_name,country_code
    ) x
    group by primary_field_code
  ) y
),
delivery_modes as (
  select jsonb_agg(jsonb_build_object('code',mode,'name',initcap(replace(mode,'_',' ')),'courses',course_count)
                   order by course_count desc,mode) items
  from (
    select mode,count(*)::int course_count
    from search.course_documents d cross join lateral unnest(coalesce(d.delivery_modes,array[]::text[])) mode
    where d.country_code in ('AU','NZ')
    group by mode
  ) x
),
intake_years as (
  select jsonb_agg(jsonb_build_object('year',intake_year,'courses',course_count) order by intake_year) items
  from (
    select (j->>'year')::int intake_year,count(distinct d.course_stable_key)::int course_count
    from search.course_documents d cross join lateral jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) j
    where d.country_code in ('AU','NZ') and (j->>'year') ~ '^[0-9]+$'
    group by (j->>'year')::int
  ) x
),
intake_labels as (
  select jsonb_agg(jsonb_build_object('label',intake_label,'courses',course_count) order by course_count desc,intake_label) items
  from (
    select j->>'label' intake_label,count(distinct d.course_stable_key)::int course_count
    from search.course_documents d cross join lateral jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) j
    where d.country_code in ('AU','NZ') and coalesce(j->>'label','')<>''
    group by j->>'label'
  ) x
),
english_tests as (
  select jsonb_agg(jsonb_build_object('code',test_code,'name',test_name,'courses',course_count)
                   order by course_count desc,test_name) items
  from (
    select j->>'test_code' test_code,max(j->>'test_name') test_name,count(distinct d.course_stable_key)::int course_count
    from search.course_documents d cross join lateral jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) j
    where d.country_code in ('AU','NZ') and coalesce(j->>'test_code','')<>''
    group by j->>'test_code'
  ) x
),
publication_states as (
  select jsonb_agg(jsonb_build_object('code',publication_status,'courses',course_count)
                   order by course_count desc,publication_status) items
  from (
    select publication_status,count(*)::int course_count
    from search.course_documents where country_code in ('AU','NZ')
    group by publication_status
  ) x
),
availability as (
  select jsonb_build_object(
    'total_courses',count(*)::int,
    'has_intake',count(*) filter (where has_intake)::int,
    'has_english',count(*) filter (where has_english)::int,
    'has_scholarship',count(*) filter (where has_scholarship)::int,
    'has_provider_current_tuition',count(*) filter (where has_provider_current_tuition)::int,
    'has_regulatory_tuition',count(*) filter (where has_regulatory_tuition)::int,
    'has_official_link',count(*) filter (where has_link)::int
  ) obj
  from search.course_documents where country_code in ('AU','NZ')
),
tuition_stats as (
  select jsonb_build_object(
    'provider_current_annual',jsonb_build_object(
      'min',min(provider_annual_tuition_amount) filter (where has_provider_current_tuition),
      'max',max(provider_annual_tuition_amount) filter (where has_provider_current_tuition),
      'courses',count(*) filter (where has_provider_current_tuition)
    ),
    'regulatory_total_course',jsonb_build_object(
      'min',min(regulatory_tuition_amount) filter (where has_regulatory_tuition),
      'max',max(regulatory_tuition_amount) filter (where has_regulatory_tuition),
      'courses',count(*) filter (where has_regulatory_tuition)
    )
  ) obj
  from search.course_documents where country_code in ('AU','NZ')
),
top_fields as (
  select jsonb_agg(
    jsonb_build_object('code', primary_field_code,'name', primary_field_name,'courses', course_count)
    order by course_count desc, primary_field_name
  ) as items
  from (
    select primary_field_code, primary_field_name, count(*)::int as course_count
    from search.course_documents
    where country_code in ('AU','NZ') and primary_field_name is not null
    group by primary_field_code, primary_field_name
    order by count(*) desc, primary_field_name
    limit 8
  ) x
)
select jsonb_build_object(
  'contract_version','zoho-integration-v2',
  'resource','reference_bundle',
  'generated_at',now(),
  'countries',coalesce((select items from countries),'[]'::jsonb),
  'subdivisions',coalesce((select items from subdivisions),'[]'::jsonb),
  'providers',coalesce((select items from providers),'[]'::jsonb),
  'course_filters',jsonb_build_object(
    'study_levels',coalesce((select items from study_levels),'[]'::jsonb),
    'study_areas',coalesce((select items from study_areas),'[]'::jsonb),
    'delivery_modes',coalesce((select items from delivery_modes),'[]'::jsonb),
    'intake_years',coalesce((select items from intake_years),'[]'::jsonb),
    'intake_labels',coalesce((select items from intake_labels),'[]'::jsonb),
    'english_tests',coalesce((select items from english_tests),'[]'::jsonb),
    'publication_states',coalesce((select items from publication_states),'[]'::jsonb),
    'availability',coalesce((select obj from availability),'{}'::jsonb),
    'tuition',coalesce((select obj from tuition_stats),'{}'::jsonb)
  ),
  'platform_stats',jsonb_build_object(
    'provider_counts',coalesce((select counts from provider_counts),'{}'::jsonb),
    'course_counts',coalesce((select counts from course_counts),'{}'::jsonb),
    'top_study_areas',coalesce((select items from top_fields),'[]'::jsonb)
  )
);
$$;

revoke all on function public.zoho_edge_reference_bundle_v1() from public, anon, authenticated;
grant execute on function public.zoho_edge_reference_bundle_v1() to service_role;
