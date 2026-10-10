CREATE OR REPLACE FUNCTION public.website_edge_course_search_v3_1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_study_level_codes text[] DEFAULT NULL::text[], p_primary_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_scholarship boolean DEFAULT NULL::boolean, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_provider_current_tuition boolean DEFAULT NULL::boolean, p_has_regulatory_tuition boolean DEFAULT NULL::boolean, p_has_link boolean DEFAULT NULL::boolean, p_intake_years integer[] DEFAULT NULL::integer[], p_intake_labels text[] DEFAULT NULL::text[], p_english_test_codes text[] DEFAULT NULL::text[], p_min_provider_annual_tuition numeric DEFAULT NULL::numeric, p_max_provider_annual_tuition numeric DEFAULT NULL::numeric, p_min_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_max_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_publication_statuses text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 12, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'api', 'search'
AS $function$
declare v_base jsonb; v_items jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  v_base:=public.zoho_edge_course_search_v2(
    p_query,p_country_codes,p_provider_ids,p_subdivision_codes,p_study_level_codes,p_primary_field_codes,p_delivery_modes,
    p_has_scholarship,p_has_intake,p_has_english,p_has_provider_current_tuition,p_has_regulatory_tuition,p_has_link,
    p_intake_years,p_intake_labels,p_english_test_codes,p_min_provider_annual_tuition,p_max_provider_annual_tuition,
    p_min_regulatory_total_tuition,p_max_regulatory_total_tuition,p_publication_statuses,p_changed_since,p_limit,p_offset
  );

  select coalesce(jsonb_agg(
    i.item || jsonb_build_object(
      'intake_summary',case when coalesce((i.item->>'has_intake')::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object(
        'year',x->'year','label',x->'label','start_date',x->'start_date','application_deadline',x->'application_deadline'
      )) from (select x from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) x limit 3) q),'[]'::jsonb) else '[]'::jsonb end,
      'english_summary',case when coalesce((i.item->>'has_english')::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object(
        'test_code',x->'test_code','test_name',x->'test_name','overall_score',x->'overall_score','component_scores',coalesce(x->'component_scores','{}'::jsonb),'valid_from',x->'valid_from','valid_to',x->'valid_to'
      )) from (select x from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) x limit 3) q),'[]'::jsonb) else '[]'::jsonb end
    ) order by i.ord
  ),'[]'::jsonb) into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) with ordinality i(item,ord)
  left join search.course_documents d on d.course_stable_key=i.item->>'course_id';

  return jsonb_set(jsonb_set(v_base,'{items}',v_items,true),'{contract_version}','"website-integration-v3.1-pilot"'::jsonb,true)
    || jsonb_build_object(
      'card_enrichment',jsonb_build_object(
        'intake_summary_max_items',3,
        'english_summary_max_items',3,
        'full_detail_action','lookup',
        'null_semantics','summary arrays are empty when no admitted value is present; missing scalar values remain null'
      )
    );
end $function$
