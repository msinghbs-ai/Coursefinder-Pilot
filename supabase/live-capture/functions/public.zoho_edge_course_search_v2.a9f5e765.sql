CREATE OR REPLACE FUNCTION public.zoho_edge_course_search_v2(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_study_level_codes text[] DEFAULT NULL::text[], p_primary_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_scholarship boolean DEFAULT NULL::boolean, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_provider_current_tuition boolean DEFAULT NULL::boolean, p_has_regulatory_tuition boolean DEFAULT NULL::boolean, p_has_link boolean DEFAULT NULL::boolean, p_intake_years integer[] DEFAULT NULL::integer[], p_intake_labels text[] DEFAULT NULL::text[], p_english_test_codes text[] DEFAULT NULL::text[], p_min_provider_annual_tuition numeric DEFAULT NULL::numeric, p_max_provider_annual_tuition numeric DEFAULT NULL::numeric, p_min_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_max_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_publication_statuses text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'api'
AS $function$
  select api.zoho_course_search_v2(
    p_query,p_country_codes,p_provider_ids,p_subdivision_codes,p_study_level_codes,p_primary_field_codes,
    p_delivery_modes,p_has_scholarship,p_has_intake,p_has_english,p_has_provider_current_tuition,
    p_has_regulatory_tuition,p_has_link,p_intake_years,p_intake_labels,p_english_test_codes,
    p_min_provider_annual_tuition,p_max_provider_annual_tuition,p_min_regulatory_total_tuition,
    p_max_regulatory_total_tuition,p_publication_statuses,p_changed_since,p_limit,p_offset
  );
$function$
