-- CF-247 complete coverage: 604 Australian providers (4,975 courses) have no website in the CRICOS-derived catalogue.
-- Website discovery: a web search for the provider's name with "CRICOS" (Firecrawl search, 2 credits per search,
-- inside the monthly budget guard); a result is accepted only when its home page prints the provider's own CRICOS
-- provider code (ESOS requires the code on provider marketing), and directories/registers are skipped. The found
-- website is kept in the sweep tables (catalogue.providers is not changed); discovery then proceeds as usual.
alter table pipeline.coverage_provider_discovery add column if not exists site_searched_at timestamptz,
  add column if not exists site_source text, add column if not exists site_evidence jsonb;

create or replace function public.svc_coverage_site_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline' as $f$
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
           'cricos',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='cricos'))),'[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id=u.provider_id;
  return v;
end $f$;
revoke all on function public.svc_coverage_site_next(int) from public, anon, authenticated;
grant execute on function public.svc_coverage_site_next(int) to service_role;

create or replace function public.svc_coverage_site_record(p_provider_id uuid, p_website text, p_evidence jsonb)
returns void language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence,
         website=coalesce(nullif(p_website,''),website), site_source=case when nullif(p_website,'') is not null then 'search_verified_cricos_code' else site_source end,
         status=case when nullif(p_website,'') is not null then 'pending' else status end, attempts=case when nullif(p_website,'') is not null then 0 else attempts end,
         updated_at=now()
   where provider_id=p_provider_id;
end $f$;
revoke all on function public.svc_coverage_site_record(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_coverage_site_record(uuid,text,jsonb) to service_role;

select cron.schedule('coverage-find-site','1-59/3 * * * *',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"find_site","limit":5}'::jsonb)$$);
