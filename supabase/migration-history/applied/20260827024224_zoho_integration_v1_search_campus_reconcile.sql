
create or replace function api.zoho_course_search_v1(
  p_query text default null,
  p_country_codes text[] default null,
  p_provider_ids text[] default null,
  p_subdivision_codes text[] default null,
  p_has_scholarship boolean default null,
  p_changed_since timestamptz default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb
language sql
security definer
set search_path = pg_catalog, search, api
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
      and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
      and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(course_title), course_stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
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

create or replace function api.zoho_campus_search_v1(
  p_query text default null,
  p_country_code text default null,
  p_provider_ids text[] default null,
  p_subdivision_codes text[] default null,
  p_changed_since timestamptz default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb
language sql
security definer
set search_path = pg_catalog, catalogue, ref, api
as $$
  with base as (
    select ca.*, p.stable_key provider_stable_key, p.canonical_name provider_name,
           co.iso_alpha2::text country_code, s.code subdivision_code, s.name subdivision_name
    from catalogue.campuses ca
    join catalogue.providers p on p.id=ca.provider_id
    join ref.countries co on co.id=ca.country_id
    left join ref.subdivisions s on s.id=ca.subdivision_id
    where (p_query is null or btrim(p_query)='' or ca.name ilike '%'||btrim(p_query)||'%' or
           ca.stable_key ilike '%'||btrim(p_query)||'%' or ca.city ilike '%'||btrim(p_query)||'%')
      and (p_country_code is null or co.iso_alpha2=upper(p_country_code))
      and (p_provider_ids is null or p.stable_key=any(p_provider_ids))
      and (p_subdivision_codes is null or s.code=any(p_subdivision_codes))
      and (p_changed_since is null or ca.updated_at > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','campuses',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'campus_id',stable_key,'name',name,'campus_code',campus_code,
      'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
      'country_code',country_code,
      'subdivision',case when subdivision_code is null then null else jsonb_build_object('code',subdivision_code,'name',subdivision_name) end,
      'city',city,'postcode',postcode,'website',website,
      'lifecycle_status',status,'publication_status',publication_status,
      'freshness',jsonb_build_object('last_verified_at',last_verified_at,'updated_at',updated_at)
    ) order by lower(name),stable_key),'[]'::jsonb),
    'page',jsonb_build_object(
      'limit',greatest(1,least(coalesce(p_limit,20),50)),
      'offset',greatest(coalesce(p_offset,0),0),
      'total',(select count(*) from base)
    ),
    'ordering','name_asc,campus_id_asc','generated_at',now()
  ) from page;
$$;

create or replace function api.zoho_campus_lookup_v1(p_identifier text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalogue, ref, api
as $$
  with x as (
    select ca.*, p.stable_key provider_stable_key, p.canonical_name provider_name,
           co.iso_alpha2::text country_code, s.code subdivision_code, s.name subdivision_name
    from catalogue.campuses ca
    join catalogue.providers p on p.id=ca.provider_id
    join ref.countries co on co.id=ca.country_id
    left join ref.subdivisions s on s.id=ca.subdivision_id
    where lower(ca.stable_key)=lower(btrim(p_identifier))
       or lower(coalesce(ca.campus_code,''))=lower(btrim(p_identifier))
    order by case when lower(ca.stable_key)=lower(btrim(p_identifier)) then 0 else 1 end, ca.stable_key
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','campus',
    'item',(select jsonb_build_object(
      'campus_id',stable_key,'name',name,'campus_code',campus_code,
      'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
      'country_code',country_code,
      'subdivision',case when subdivision_code is null then null else jsonb_build_object('code',subdivision_code,'name',subdivision_name) end,
      'city',city,'address',jsonb_build_object('line1',address_line1,'line2',address_line2,'postcode',postcode),
      'website',website,'lifecycle_status',status,'publication_status',publication_status,
      'freshness',jsonb_build_object('last_verified_at',last_verified_at,'updated_at',updated_at)
    ) from x),'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','campus',
    'error',jsonb_build_object('code','NOT_FOUND','message','Campus identifier not found')
  ) end;
$$;

revoke all on function api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function api.zoho_campus_search_v1(text,text,text[],text[],timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function api.zoho_campus_lookup_v1(text) from public, anon, authenticated;
grant execute on function api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) to service_role;
grant execute on function api.zoho_campus_search_v1(text,text,text[],text[],timestamptz,integer,integer) to service_role;
grant execute on function api.zoho_campus_lookup_v1(text) to service_role;
