CREATE OR REPLACE FUNCTION security.scholarship_country_readiness_v1()
 RETURNS TABLE(country_code text, country text, active_courses bigint, providers bigint, universities bigint, switched_on boolean, status text, domestic_terms boolean, nationality_term boolean, registers_live integer, registers_planned integer, discovery_queued bigint, ready boolean, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with c as (
    select k.id, k.iso_alpha2::text cc, k.name, k.scholarship_ingestion_enabled sw,
           (select count(*) from catalogue.courses co join catalogue.providers p on p.id = co.provider_id where p.country_id = k.id and co.lifecycle_status = 'active') courses,
           (select count(*) from catalogue.providers p where p.country_id = k.id and p.lifecycle_status = 'active') providers,
           o.status, o.domestic_terms, o.government_registers
      from ref.countries k left join scholarship.country_onboarding o on o.country_code = k.iso_alpha2
     where k.scholarship_ingestion_enabled or o.country_code is not null
        or exists (select 1 from catalogue.providers p join catalogue.courses co on co.provider_id = p.id where p.country_id = k.id and co.lifecycle_status = 'active'))
  select c.cc, c.name, c.courses, c.providers,
         (select count(*) from catalogue.providers p where p.country_id = c.id and p.lifecycle_status = 'active'
             and (security.australian_university(p.id) or jsonb_array_length(coalesce(security.provider_university_groups(p.id), '[]')) > 0
                  or (p.canonical_name ~* '\m(university|université|universite)\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)'))) unis,
         c.sw, coalesce(c.status, 'not listed'),
         c.cc in ('AU','NZ','CA') or coalesce(c.domestic_terms, '') <> '',
         c.cc = 'AU' or exists (select 1 from ref.nationality_terms x where x.code = c.cc),
         (select count(*)::int from scholarship.registers r where r.country_code = c.cc and r.status = 'live'),
         (select count(*)::int from scholarship.registers r where r.country_code = c.cc and r.status = 'planned'),
         (select count(*) from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = c.id),
         x.missing = '{}', x.missing
    from c cross join lateral (select array_remove(array[
         case when c.courses = 0 then 'no active courses in the catalogue yet' end,
         case when c.status is null then 'no onboarding entry (scholarship.country_onboarding)' end,
         case when not (c.cc in ('AU','NZ','CA') or coalesce(c.domestic_terms, '') <> '') then 'no domestic-student wording for the audience reader' end,
         case when not (c.cc = 'AU' or exists (select 1 from ref.nationality_terms x where x.code = c.cc)) then 'no nationality term for the country' end,
         case when c.courses > 0 and not exists (select 1 from catalogue.providers p where p.country_id = c.id and p.lifecycle_status = 'active'
                and (security.australian_university(p.id) or jsonb_array_length(coalesce(security.provider_university_groups(p.id), '[]')) > 0
                     or (p.canonical_name ~* '\m(university|université|universite)\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
              then 'no university providers recognised' end,
         case when c.sw and c.courses > 0 and not exists (select 1 from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = c.id)
              then 'switched on but no provider queued for scholarship discovery' end
       ], null) missing) x
   order by (c.courses > 0) desc, c.cc
$function$
