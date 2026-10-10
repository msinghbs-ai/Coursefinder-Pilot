-- CF-CHG-20260825-033
-- Bounded Friday showcase Search/read contract. This is server-side only and grants no Publication authority.

create or replace function api.website_course_search_preview_v1(
  p_query text default null,
  p_country_codes text[] default null,
  p_provider_keys text[] default null,
  p_provider_name text default null,
  p_subdivision_codes text[] default null,
  p_level_codes text[] default null,
  p_field_codes text[] default null,
  p_delivery_modes text[] default null,
  p_provider_annual_tuition_min numeric default null,
  p_provider_annual_tuition_max numeric default null,
  p_has_intake boolean default null,
  p_has_english boolean default null,
  p_has_scholarship boolean default null,
  p_sort text default 'relevance',
  p_limit integer default 20,
  p_offset integer default 0
) returns jsonb
language sql stable security definer
set search_path = 'api','search','pg_catalog'
as $function$
with params as (
  select greatest(1,least(coalesce(p_limit,20),50)) lim,
         greatest(coalesce(p_offset,0),0) off,
         trim(coalesce(p_query,'')) q,
         case when trim(coalesce(p_query,''))='' then null else websearch_to_tsquery('english',trim(p_query)) end tsq,
         case when p_sort in ('relevance','title','provider_annual_tuition_asc','provider_annual_tuition_desc','earliest_intake') then p_sort else 'relevance' end sort_code
), ranked as (
  select d.*,
         case
           when (select q from params)='' then 0::real
           when lower(coalesce(d.course_code,''))=lower((select q from params)) then 1000::real
           when lower(coalesce(d.course_stable_key,''))=lower((select q from params)) then 1000::real
           when lower(d.course_title)=lower((select q from params)) then 500::real
           when lower(d.provider_name)=lower((select q from params)) then 250::real
           else ts_rank_cd(d.search_tsv,(select tsq from params))::real
         end score,
         case
           when lower(coalesce(d.course_code,''))=lower((select q from params)) then 'exact_course_code'
           when lower(coalesce(d.course_stable_key,''))=lower((select q from params)) then 'exact_course_id'
           when lower(d.course_title)=lower((select q from params)) then 'exact_course_title'
           when lower(d.provider_name)=lower((select q from params)) then 'exact_provider'
           else 'fts'
         end match_type
  from search.course_documents d
  where (p_country_codes is null or d.country_code=any(p_country_codes))
    and (p_provider_keys is null or d.provider_stable_key=any(p_provider_keys))
    and (p_provider_name is null or d.provider_name ilike '%'||trim(p_provider_name)||'%')
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_level_codes is null or d.study_level_code=any(p_level_codes))
    and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_provider_annual_tuition_min is null or d.provider_annual_tuition_amount>=p_provider_annual_tuition_min)
    and (p_provider_annual_tuition_max is null or d.provider_annual_tuition_amount<=p_provider_annual_tuition_max)
    and (p_has_intake is null or d.has_intake=p_has_intake)
    and (p_has_english is null or d.has_english=p_has_english)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and ((select q from params)=''
      or lower(coalesce(d.course_code,''))=lower((select q from params))
      or lower(coalesce(d.course_stable_key,''))=lower((select q from params))
      or lower(d.course_title)=lower((select q from params))
      or lower(d.provider_name)=lower((select q from params))
      or d.search_tsv @@ (select tsq from params))
), paged as (
  select * from ranked
  order by
    case when (select sort_code from params)='relevance' then score end desc,
    case when (select sort_code from params)='title' then course_title end asc,
    case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
    case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
    course_title,course_stable_key
  limit (select lim from params) offset (select off from params)
), state as (
  select generation,content_hash,metadata from search.projection_state where projection_code='course'
)
select jsonb_build_object(
  'contract_version','website-course-search-preview-v1',
  'boundary','server-side-showcase-only',
  'meta',jsonb_build_object(
    'mode','deterministic_fts','limit',(select lim from params),'offset',(select off from params),
    'projection_version','course-v3','projection_generation',(select generation from state),
    'projection_hash',(select content_hash from state),'sort',(select sort_code from params),
    'publication_authority','not_granted'
  ),
  'items',coalesce(jsonb_agg(jsonb_build_object(
    'course_id',course_stable_key,'title',course_title,'course_code',course_code,
    'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
    'country',country_code,'study_level',study_level_code,
    'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
    'locations',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
    'regulatory_tuition',jsonb_build_object('state',regulatory_tuition_state,'amount',regulatory_tuition_amount,'currency',trim(regulatory_tuition_currency),'basis',regulatory_tuition_basis),
    'provider_current_tuition',jsonb_build_object('has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,'annual_currency',trim(provider_annual_tuition_currency),'options',provider_tuition_options),
    'official_course_url',official_course_url,'intakes',intake_options,'english_requirements',english_requirement_options,'scholarships',scholarship_options,
    'visibility',jsonb_build_object('publication_status',publication_status),
    'freshness',jsonb_build_object('source_updated_at',source_updated_at,'generated_at',generated_at),
    'match',jsonb_build_object('mode',match_type,'keyword_score',score)
  ) order by
    case when (select sort_code from params)='relevance' then score end desc,
    case when (select sort_code from params)='title' then course_title end asc,
    case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
    case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
    course_title,course_stable_key),'[]'::jsonb)
) from paged;
$function$;

revoke all on function api.website_course_search_preview_v1(text,text[],text[],text,text[],text[],text[],text[],numeric,numeric,boolean,boolean,boolean,text,integer,integer) from public,anon,authenticated;
grant execute on function api.website_course_search_preview_v1(text,text[],text[],text,text[],text[],text[],text[],numeric,numeric,boolean,boolean,boolean,text,integer,integer) to service_role;
