CREATE OR REPLACE FUNCTION public.svc_scholarship_resolve_au_provider(p_cricos text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select pr.provider_id
  from catalogue.provider_registrations pr
  join catalogue.providers p on p.id=pr.provider_id
  join ref.countries c on c.id=p.country_id
  where c.iso_alpha2='AU'
    and pr.registration_scheme='cricos'
    and upper(btrim(pr.registration_code))=upper(btrim(p_cricos))
    and coalesce(pr.status,'active') not in ('inactive','cancelled','archived')
  order by pr.valid_to nulls first, pr.checked_at desc nulls last
  limit 1
$function$
