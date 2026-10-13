CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 3): pages that are never scholarships are skipped before they are read, by the address
  -- rules in Scholarships › Coverage › Settings and jobs (never an address that mentions a scholarship, bursary, stipend or grant)
  update pipeline.scholarship_page_candidates c set admit_status='skipped', admit_reasons=array['skipped: '||r.label], read_status=coalesce(c.read_status,'skipped'), read_at=now(), leased_until=null
    from pipeline.scholarship_skip_rules r
   where r.active and c.admit_status is null and c.matched_scholarship_id is null and c.source<>'register' and c.url ~* r.pattern and c.url !~* r.unless_pattern;
  with ranked as (
    select c.id, d.priority, row_number() over (partition by c.provider_id order by (c.url ~* 'international') desc, c.found_at, c.id) rn
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       -- v2.15.265: not for providers that do not qualify or are past their cap, nor pages on a directory site
       and not security.fc_sch_held_v1(c.provider_id, true) and not security.third_party_host_v1(c.url)),  -- v2.15.237: paused while the provider is unpublished or archived
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by (c.requested_at is not null) desc, security.fc_provider_tier_v1(c.provider_id), r.rn, (r.priority not in (0,3)), c.id -- 11 Oct 2026: on-demand candidates first
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$
