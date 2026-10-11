CREATE OR REPLACE FUNCTION api.zoho_course_search_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_has_scholarship boolean DEFAULT NULL::boolean, p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
  with base as (
    select d.*
    from search.course_documents d
    where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and (
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
$function$
