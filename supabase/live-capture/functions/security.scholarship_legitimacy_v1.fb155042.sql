CREATE OR REPLACE FUNCTION security.scholarship_legitimacy_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id
                  where p.id = p_provider_id and p.lifecycle_status = 'active' and p.publication_status = 'published'
                    and p.enrols_international is not false and t.status = 'active' and t.code <> 'school'
                    and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)
                    and (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
                        >= security.pipeline_num_v1('scholarship.legitimacy_min_courses', 1))
      -- F-SCH 13 Nov 2026: a classified university with its own official website, without loaded courses or a provider type yet
      or exists (select 1 from catalogue.providers p where p.id = p_provider_id and p.lifecycle_status = 'active' and p.publication_status = 'published'
                    and p.enrols_international is not false and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)
                    and security.scholarship_university(p.id))
$function$
