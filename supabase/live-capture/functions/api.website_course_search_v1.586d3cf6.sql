CREATE OR REPLACE FUNCTION api.website_course_search_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_fee boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search'
AS $function$
with params as (
  select greatest(1,least(coalesce(p_limit,20),50)) as lim,
         greatest(coalesce(p_offset,0),0) as off,
         websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
), ranked as (
  select d.*,
    case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end as score
  from search.course_documents d
  where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and d.publication_status='published'
    and (p_country_codes is null or d.country_code=any(p_country_codes))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_level_codes is null or d.study_level_code=any(p_level_codes))
    and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_fee is null or d.has_fee=p_has_fee)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
), paged as (
  select * from ranked
  order by score desc,course_title,course_stable_key
  limit (select lim from params) offset (select off from params)
)
select jsonb_build_object(
  'contract_version','website-course-search-v1',
  'meta',jsonb_build_object(
    'mode','keyword',
    'limit',(select lim from params),
    'offset',(select off from params),
    'projection_version','course-v2'
  ),
  'items',coalesce(jsonb_agg(jsonb_build_object(
    'course_key',course_stable_key,
    'title',course_title,
    'course_code',course_code,
    'provider',jsonb_build_object('provider_key',provider_stable_key,'name',provider_name),
    'country',country_code,
    'study_level',study_level_code,
    'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
    'states',to_jsonb(subdivision_codes),
    'delivery_modes',to_jsonb(delivery_modes),
    'readiness',jsonb_build_object('has_state',has_state,'has_link',has_link,'has_fee',has_fee,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship),
    'match',jsonb_build_object('keyword_score',score)
  ) order by score desc,course_title,course_stable_key),'[]'::jsonb)
)
from paged
$function$
