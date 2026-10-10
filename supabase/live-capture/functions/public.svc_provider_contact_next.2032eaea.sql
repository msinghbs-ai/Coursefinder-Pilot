CREATE OR REPLACE FUNCTION public.svc_provider_contact_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.id, coalesce(p.display_name, p.canonical_name) name, p.website, security.coverage_country(p.id) country
      from catalogue.providers p
     where p.lifecycle_status = 'active' and p.website ~* '^https?://' and (p.phone is null or p.email is null)
       and not security.third_party_host_v1(p.website)
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'public_general' and k.checked_at > now() - interval '90 days')
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 8), 20))),
  lease as (insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome) select id, 'public_general', now(), 'leased' from pick
            on conflict (provider_id, kind) do update set checked_at = now(), outcome = 'leased' returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.name, 'website', p.website, 'country', p.country)), '[]'::jsonb) into v
    from pick p where p.id in (select provider_id from lease);
  return v;
end $function$
