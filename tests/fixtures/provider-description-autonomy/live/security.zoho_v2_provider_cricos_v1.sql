CREATE OR REPLACE FUNCTION security.zoho_v2_provider_cricos_v1(p_provider_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select upper(pr.registration_code) from catalogue.provider_registrations pr
   where pr.provider_id = p_provider_id and lower(pr.registration_scheme) = 'cricos' and nullif(btrim(pr.registration_code), '') is not null
   order by (coalesce(pr.status, 'active') in ('inactive', 'cancelled', 'archived')), pr.checked_at desc nulls last limit 1
$function$
;

