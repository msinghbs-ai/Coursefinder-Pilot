-- CF-247 (22 Oct 2026). Platform Admin 18:26: "Why is the coverage sweep job failing" (Scheduled jobs, Workers sending back errors).
-- Second error on the list: "svc_provider_contact_next: canceling statement due to statement timeout" (30 since 13:00 Melbourne). The pick
-- ran the directory-site test on every provider with a website and a missing phone or email (1,327) before the cheap filters (checked in
-- the last 90 days, has an active course, published); it took 10.4 seconds and found none, so each run timed out instead of returning
-- nothing. The cheap filters now run first (materialized) and the directory-site test only on what is left. Same rules, order and limit.
-- Replaces: public.svc_provider_contact_next (filter order). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('public.svc_provider_contact_next(integer)'::regprocedure)) <> 'b759b7e0badf624d8e5c931f3d5bb7a6' then
    raise exception 'live public.svc_provider_contact_next differs from the definition this change replaces';
  end if;
end $guard$;

CREATE OR REPLACE FUNCTION public.svc_provider_contact_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with cand as materialized (  -- 22 Oct 2026: the cheap filters first, so the directory-site test runs only on what is left
    select p.id, coalesce(p.display_name, p.canonical_name) name, p.website,
           (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') courses
      from catalogue.providers p
     where p.lifecycle_status = 'active' and p.website ~* '^https?://' and (p.phone is null or p.email is null)
       and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'public_general' and k.checked_at > now() - interval '90 days')
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)  -- v2.15.237: paused while the provider is unpublished or archived
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
  pick as (
    select c.id, c.name, c.website, security.coverage_country(c.id) country
      from cand c
     where not security.third_party_host_v1(c.website)
     order by c.courses desc
     limit greatest(1, least(coalesce(p_limit, 8), 20))),
  lease as (insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome) select id, 'public_general', now(), 'leased' from pick
            on conflict (provider_id, kind) do update set checked_at = now(), outcome = 'leased' returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.name, 'website', p.website, 'country', p.country)), '[]'::jsonb) into v
    from pick p where p.id in (select provider_id from lease);
  return v;
end $function$;
