CREATE OR REPLACE FUNCTION security.australian_university(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'security'
AS $function$
  select exists (select 1 from catalogue.providers p join ref.countries c on c.id=p.country_id
     where p.id=p_provider_id and c.iso_alpha2='AU' and p.lifecycle_status='active'
       and (jsonb_array_length(coalesce(security.provider_university_groups(p.id),'[]'))>0
            or (p.canonical_name ~* '\muniversity\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
$function$
