CREATE OR REPLACE FUNCTION api.zoho_course_candidates_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_fee boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'security'
AS $function$
declare v_result jsonb;
begin
  if security.current_role_rank()<2 then
    raise exception 'forbidden' using errcode='42501';
  end if;
  with params as (
    select greatest(1,least(coalesce(p_limit,30),100)) as lim,
           websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
  ), ranked as (
    select d.*,
      case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end as score
    from search.course_documents d
    where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and d.publication_status in ('published','internal')
      and (p_country_codes is null or d.country_code=any(p_country_codes))
      and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
      and (p_level_codes is null or d.study_level_code=any(p_level_codes))
      and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
      and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
      and (p_has_fee is null or d.has_fee=p_has_fee)
      and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
      and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
    order by score desc,d.course_title,d.course_stable_key
    limit (select lim from params)
  )
  select jsonb_build_object(
    'contract_version','zoho-course-candidates-v1',
    'meta',jsonb_build_object('mode','keyword','limit',(select lim from params),'projection_version','course-v3'),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'course_key',course_stable_key,
      'provider_key',provider_stable_key,
      'title',course_title,
      'provider_name',provider_name,
      'country',country_code,
      'study_level',study_level_code,
      'field_code',primary_field_code,
      'states',to_jsonb(subdivision_codes),
      'delivery_modes',to_jsonb(delivery_modes),
      'academic_rank',score,
      'readiness',jsonb_build_object('has_state',has_state,'has_link',has_link,'has_fee',has_fee,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship)
    ) order by score desc,course_title,course_stable_key),'[]'::jsonb)
  ) into v_result
  from ranked;
  return v_result;
end
$function$
