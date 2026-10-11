CREATE OR REPLACE FUNCTION api.website_course_search_v2(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_provider_tuition boolean DEFAULT NULL::boolean, p_provider_annual_tuition_max numeric DEFAULT NULL::numeric, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_sort text DEFAULT 'relevance'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search'
AS $function$
with params as (
  select greatest(1,least(coalesce(p_limit,20),50)) lim,greatest(coalesce(p_offset,0),0) off,
         websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) tsq,
         case when p_sort in ('relevance','title','regulatory_tuition_asc','regulatory_tuition_desc','provider_annual_tuition_asc','provider_annual_tuition_desc','earliest_intake') then p_sort else 'relevance' end sort_code
), ranked as (
  select d.*,case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end score
  from search.course_documents d
  where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and d.publication_status='published'
    and (p_country_codes is null or d.country_code=any(p_country_codes))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_level_codes is null or d.study_level_code=any(p_level_codes))
    and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_provider_tuition is null or d.has_provider_current_tuition=p_has_provider_tuition)
    and (p_provider_annual_tuition_max is null or d.provider_annual_tuition_amount<=p_provider_annual_tuition_max)
    and (p_has_intake is null or d.has_intake=p_has_intake)
    and (p_has_english is null or d.has_english=p_has_english)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
), paged as (
  select * from ranked
  order by
    case when (select sort_code from params)='relevance' then score end desc,
    case when (select sort_code from params)='title' then course_title end asc,
    case when (select sort_code from params)='regulatory_tuition_asc' then regulatory_tuition_amount end asc nulls last,
    case when (select sort_code from params)='regulatory_tuition_desc' then regulatory_tuition_amount end desc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
    case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
    course_title,course_stable_key
  limit (select lim from params) offset (select off from params)
)
select jsonb_build_object(
 'contract_version','website-course-search-v2',
 'meta',jsonb_build_object('mode','keyword','limit',(select lim from params),'offset',(select off from params),'projection_version','course-v3','sort',(select sort_code from params)),
 'items',coalesce(jsonb_agg(jsonb_build_object(
   'course_key',course_stable_key,'title',course_title,'course_code',course_code,
   'provider',jsonb_build_object('provider_key',provider_stable_key,'name',provider_name),
   'country',country_code,'study_level',study_level_code,
   'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
   'states',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
   'regulatory_tuition',jsonb_build_object('state',regulatory_tuition_state,'amount',regulatory_tuition_amount,'currency',trim(regulatory_tuition_currency),'basis',regulatory_tuition_basis),
   'provider_current_tuition',jsonb_build_object('has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,'annual_currency',trim(provider_annual_tuition_currency),'options',provider_tuition_options),
   'official_course_url',official_course_url,'intakes',intake_options,'english_requirements',english_requirement_options,'scholarships',scholarship_options,
   'readiness',jsonb_build_object('has_state',has_state,'has_official_url',has_link,'has_provider_current_tuition',has_provider_current_tuition,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship),
   'match',jsonb_build_object('keyword_score',score)
 ) order by
    case when (select sort_code from params)='relevance' then score end desc,
    case when (select sort_code from params)='title' then course_title end asc,
    case when (select sort_code from params)='regulatory_tuition_asc' then regulatory_tuition_amount end asc nulls last,
    case when (select sort_code from params)='regulatory_tuition_desc' then regulatory_tuition_amount end desc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
    case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
    course_title,course_stable_key),'[]'::jsonb)
) from paged
$function$
