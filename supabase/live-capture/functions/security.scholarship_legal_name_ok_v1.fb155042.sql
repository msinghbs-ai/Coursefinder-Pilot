CREATE OR REPLACE FUNCTION security.scholarship_legal_name_ok_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 (IQ-00215): a provider whose record joins its trading names with ';' passes when its legal name (the first name) passes the existing
  -- university name test; the whole joined text is never tested here
  select exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id
                  where p.id = p_provider_id and c.scholarship_ingestion_enabled and p.lifecycle_status = 'active' and position(';' in coalesce(p.canonical_name, '')) > 0
                    and btrim(split_part(p.canonical_name, ';', 1)) ~* '\m(university|université|universite)\M'
                    and btrim(split_part(p.canonical_name, ';', 1)) !~* '(college|pathways?|language cent|senior|theology|divinity)')
$function$
