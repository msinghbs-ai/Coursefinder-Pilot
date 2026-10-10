CREATE OR REPLACE FUNCTION public.svc_cricos_peo_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.id, coalesce(p.display_name, p.canonical_name) name,
           (select min(upper(r.registration_code)) from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos') cricos
      from catalogue.providers p
     where p.lifecycle_status = 'active'
       and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos' and r.registration_code ~* '^[0-9]{5}[A-Z]$')
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'regulatory_peo'
                         and (k.checked_at > now() - interval '180 days' and k.outcome <> 'budget' or k.checked_at > now() - interval '1 hour'))
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 4), 8))),
  lease as (insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome) select id, 'regulatory_peo', now(), 'leased' from pick
            on conflict (provider_id, kind) do update set checked_at = now(), outcome = 'leased' returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.name, 'cricos', p.cricos)), '[]'::jsonb) into v
    from pick p where p.id in (select provider_id from lease);
  return v;
end $function$
