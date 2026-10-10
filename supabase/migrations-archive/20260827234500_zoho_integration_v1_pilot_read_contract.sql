
create or replace function api.zoho_provider_search_v1(
  p_query text default null,
  p_country_code text default null,
  p_changed_since timestamptz default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb
language sql
security definer
set search_path = pg_catalog, catalogue, ref, api
as $$
  with base as (
    select
      p.id,
      p.stable_key,
      p.canonical_name,
      p.display_name,
      c.iso_alpha2::text as country_code,
      p.website,
      p.lifecycle_status,
      p.publication_status,
      p.last_verified_at,
      p.updated_at
    from catalogue.providers p
    join ref.countries c on c.id = p.country_id
    where (p_query is null or btrim(p_query) = '' or
           p.canonical_name ilike '%' || btrim(p_query) || '%' or
           p.display_name ilike '%' || btrim(p_query) || '%' or
           p.stable_key ilike '%' || btrim(p_query) || '%')
      and (p_country_code is null or c.iso_alpha2 = upper(p_country_code))
      and (p_changed_since is null or p.updated_at > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(canonical_name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','providers',
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'provider_id', stable_key,
      'name', canonical_name,
      'display_name', display_name,
      'country_code', country_code,
      'website', website,
      'lifecycle_status', lifecycle_status,
      'publication_status', publication_status,
      'freshness', jsonb_build_object(
        'last_verified_at', last_verified_at,
        'updated_at', updated_at
      )
    ) order by lower(canonical_name), stable_key), '[]'::jsonb),
    'page', jsonb_build_object(
      'limit', greatest(1, least(coalesce(p_limit,20),50)),
      'offset', greatest(coalesce(p_offset,0),0),
      'total', (select count(*) from base)
    ),
    'generated_at', now()
  ) from page;
$$;

create or replace function api.zoho_provider_lookup_v1(p_identifier text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalogue, ref, api
as $$
  with x as (
    select
      p.id, p.stable_key, p.canonical_name, p.display_name, p.short_name,
      c.iso_alpha2::text country_code, p.website, p.description,
      p.primary_city, p.lifecycle_status, p.publication_status,
      p.last_verified_at, p.updated_at
    from catalogue.providers p
    join ref.countries c on c.id=p.country_id
    where lower(p.stable_key)=lower(btrim(p_identifier))
       or exists (
         select 1 from catalogue.provider_identifiers i
         where i.provider_id=p.id and lower(i.identifier)=lower(btrim(p_identifier))
       )
    order by case when lower(p.stable_key)=lower(btrim(p_identifier)) then 0 else 1 end
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','provider',
    'item',(select jsonb_build_object(
      'provider_id',stable_key,'name',canonical_name,'display_name',display_name,
      'short_name',short_name,'country_code',country_code,'website',website,
      'description',description,'primary_city',primary_city,
      'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('last_verified_at',last_verified_at,'updated_at',updated_at)
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','provider','error',
    jsonb_build_object('code','NOT_FOUND','message','Provider identifier not found')
  ) end;
$$;

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
    where (p_query is null or btrim(p_query)='' or d.search_tsv @@ websearch_to_tsquery('simple', btrim(p_query))
           or d.course_code = btrim(p_query) or lower(d.course_stable_key)=lower(btrim(p_query)))
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

create or replace function api.zoho_course_lookup_v1(p_identifier text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, search, api
as $$
  with x as (
    select * from search.course_documents
    where lower(course_stable_key)=lower(btrim(p_identifier))
       or lower(course_code)=lower(btrim(p_identifier))
    order by case when lower(course_stable_key)=lower(btrim(p_identifier)) then 0 else 1 end,
             course_stable_key
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','course',
    'item',(select jsonb_build_object(
      'course_id',course_stable_key,'course_code',course_code,'title',course_title,
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
        'annual_currency',provider_annual_tuition_currency,'options',coalesce(provider_tuition_options,'[]'::jsonb)
      ),
      'official_course_url',official_course_url,
      'intakes',coalesce(intake_options,'[]'::jsonb),
      'english_requirements',coalesce(english_requirement_options,'[]'::jsonb),
      'scholarships',coalesce(scholarship_options,'[]'::jsonb),
      'publication_status',publication_status,
      'context',jsonb_build_object(
        'qilt',jsonb_build_object('state','not_admitted','grain','provider_or_study_area','message','QILT remains contextual and is not yet admitted in this v1 Pilot read function'),
        'prisms',jsonb_build_object('state','not_admitted','grain','provider_state_or_sector','message','PRISMS remains contextual and is not yet admitted in this v1 Pilot read function')
      ),
      'freshness',jsonb_build_object(
        'source_updated_at',source_updated_at,'projection_updated_at',updated_at,'generated_at',generated_at
      )
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','course','error',
    jsonb_build_object('code','NOT_FOUND','message','Course identifier not found')
  ) end;
$$;

create or replace function api.zoho_scholarship_search_v1(
  p_query text default null,
  p_provider_ids text[] default null,
  p_changed_since timestamptz default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb
language sql
security definer
set search_path = pg_catalog, scholarship, catalogue, api
as $$
  with base as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where (p_query is null or btrim(p_query)='' or s.name ilike '%'||btrim(p_query)||'%' or s.stable_key ilike '%'||btrim(p_query)||'%')
      and (p_provider_ids is null or p.stable_key = any(p_provider_ids))
      and (p_changed_since is null or s.updated_at > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarships',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'audience',audience,'award_value_text',award_value_text,
      'application_required',application_required,'application_open_date',application_open_date,
      'application_close_date',application_close_date,'academic_year',academic_year,
      'source_url',source_url,'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) order by lower(name), stable_key),'[]'::jsonb),
    'page',jsonb_build_object(
      'limit',greatest(1, least(coalesce(p_limit,20),50)),
      'offset',greatest(coalesce(p_offset,0),0),
      'total',(select count(*) from base)
    ),
    'ordering','name_asc,scholarship_id_asc',
    'generated_at',now()
  ) from page;
$$;

create or replace function api.zoho_scholarship_lookup_v1(p_identifier text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, scholarship, catalogue, api
as $$
  with x as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where lower(s.stable_key)=lower(btrim(p_identifier))
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarship',
    'item',(select jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'description',description,'audience',audience,
      'award_value_text',award_value_text,'application_required',application_required,
      'application_open_date',application_open_date,'application_close_date',application_close_date,
      'academic_year',academic_year,'source_url',source_url,
      'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','scholarship','error',
    jsonb_build_object('code','NOT_FOUND','message','Scholarship identifier not found')
  ) end;
$$;

create or replace function api.zoho_sync_manifest_v1(p_changed_since timestamptz default null)
returns jsonb
language sql
security definer
set search_path = pg_catalog, catalogue, scholarship, search, api
as $$
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'boundary','server-side-pilot-only',
    'changed_since',p_changed_since,
    'providers',jsonb_build_object(
      'count',(select count(*) from catalogue.providers where p_changed_since is null or updated_at > p_changed_since),
      'max_updated_at',(select max(updated_at) from catalogue.providers)
    ),
    'courses',jsonb_build_object(
      'count',(select count(*) from search.course_documents where p_changed_since is null or greatest(updated_at,source_updated_at,generated_at) > p_changed_since),
      'max_updated_at',(select max(greatest(updated_at,source_updated_at,generated_at)) from search.course_documents)
    ),
    'scholarships',jsonb_build_object(
      'count',(select count(*) from scholarship.scholarships where p_changed_since is null or updated_at > p_changed_since),
      'max_updated_at',(select max(updated_at) from scholarship.scholarships)
    ),
    'ordering',jsonb_build_object(
      'providers','name_asc,provider_id_asc',
      'courses','title_asc,course_id_asc',
      'scholarships','name_asc,scholarship_id_asc'
    ),
    'generated_at',now()
  );
$$;

revoke all on function api.zoho_provider_search_v1(text,text,timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function api.zoho_provider_lookup_v1(text) from public, anon, authenticated;
revoke all on function api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function api.zoho_course_lookup_v1(text) from public, anon, authenticated;
revoke all on function api.zoho_scholarship_search_v1(text,text[],timestamptz,integer,integer) from public, anon, authenticated;
revoke all on function api.zoho_scholarship_lookup_v1(text) from public, anon, authenticated;
revoke all on function api.zoho_sync_manifest_v1(timestamptz) from public, anon, authenticated;

grant execute on function api.zoho_provider_search_v1(text,text,timestamptz,integer,integer) to service_role;
grant execute on function api.zoho_provider_lookup_v1(text) to service_role;
grant execute on function api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamptz,integer,integer) to service_role;
grant execute on function api.zoho_course_lookup_v1(text) to service_role;
grant execute on function api.zoho_scholarship_search_v1(text,text[],timestamptz,integer,integer) to service_role;
grant execute on function api.zoho_scholarship_lookup_v1(text) to service_role;
grant execute on function api.zoho_sync_manifest_v1(timestamptz) to service_role;
