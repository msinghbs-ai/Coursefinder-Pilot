CREATE OR REPLACE FUNCTION security.scholarship_university(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select security.australian_university(p_provider_id)
      or exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id
                  where p.id = p_provider_id and c.iso_alpha2 <> 'AU' and c.scholarship_ingestion_enabled and p.lifecycle_status = 'active'
                    and (jsonb_array_length(coalesce(security.provider_university_groups(p.id), '[]')) > 0
                         or (p.canonical_name ~* '\m(university|université|universite)\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
      -- CF-247 IQ-00215 (4 Nov 2026): joined trading names are tested on the legal name while sch_cov.legal_name_identity_on is 1
      or (security.pipeline_num_v1('sch_cov.legal_name_identity_on', 0) >= 1 and security.scholarship_legal_name_ok_v1(p_provider_id))
$function$
