CREATE OR REPLACE FUNCTION security.scholarship_admission_provider_ok_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select security.scholarship_university(p_provider_id)
      or (security.scholarship_flag_v1('scholarship.non_university_admission', false)
          -- CF-247 scholarships beyond universities (decision 3 Nov 2026 08:44 §4): the pilot providers only while scholarship.pilot_only is on
          and security.scholarship_pilot_scope_v1(p_provider_id)
          and exists (select 1 from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id join ref.countries k on k.id = p.country_id
                       where p.id = p_provider_id and p.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
                         and t.status = 'active' and p.provider_type_basis is not null
                         and t.code in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.non_university_types'), '[]'::jsonb)))
                         and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)))
$function$
