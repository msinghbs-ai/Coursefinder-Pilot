CREATE OR REPLACE FUNCTION public.svc_coverage_site_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.coverage_provider_discovery d
     where d.status='no_website' and coalesce(d.site_searched_at,'-infinity')<now()-interval '30 days' and coalesce(d.leased_until,'-infinity')<now()
     order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes' from pick where d.provider_id=pick.provider_id returning d.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'name',coalesce(p.display_name,p.canonical_name),'trading',p.short_name,
           'cricos',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='cricos'),'country',security.coverage_country(u.provider_id),
           'dli',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='ircc_dli'))),'[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id=u.provider_id;
  return v;
end $function$
