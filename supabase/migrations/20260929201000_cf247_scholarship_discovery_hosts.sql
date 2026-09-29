-- CF-247 scholarship discovery, first run (29 Sep 2026): Monash's recorded website (monash.edu.au) now serves its
-- scholarship pages from monash.edu, so its pages were dropped as "not on the provider site". A provider's own other
-- domains are taken from the first-party scholarship pages already held for it (same leading name only, e.g. monash.edu
-- for monash.edu.au), and every provider-site check uses them. Monash is discovered again.
alter table pipeline.scholarship_discovery_providers add column if not exists allowed_hosts text[] not null default '{}';

update pipeline.scholarship_discovery_providers d set allowed_hosts = coalesce((
  select array_agg(h order by n desc) from (
    select security.url_base_host(i.identifier_value) h, count(*) n
      from scholarship.identifiers i join scholarship.scholarships s on s.id=i.scholarship_id
     where s.provider_id=d.provider_id and i.scheme='first_party_detail_url'
       and security.url_base_host(i.identifier_value)<>security.url_base_host(d.website)
       and split_part(security.url_base_host(i.identifier_value),'.',1)=split_part(security.url_base_host(d.website),'.',1)
     group by 1) x), '{}');

create or replace function security.url_on_provider_sites(p_url text, p_provider_id uuid)
returns boolean language sql stable security definer set search_path to 'pg_catalog','pipeline','security' as $f$
  select coalesce((select security.url_on_provider_site(p_url, coalesce(d.site_origin,d.website)) or security.url_on_provider_site(p_url, d.website)
                          or exists (select 1 from unnest(d.allowed_hosts) h where security.url_on_provider_site(p_url, h))
                     from pipeline.scholarship_discovery_providers d where d.provider_id=p_provider_id), false)
$f$;
revoke all on function security.url_on_provider_sites(text,uuid) from public, anon, authenticated;

-- the provider-site checks (functions created in 20260929200000, not yet used by anything else) use all its domains
do $patch$
declare f text; v text; pairs text[][] := array[
  array['security.scholarship_page_match_v1(uuid,text,text,bigint)', $o$if v_site is null or not security.url_on_provider_site(p_url, v_site)$o$, $n$if v_site is null or not security.url_on_provider_sites(p_url, s.provider_id)$n$],
  array['public.svc_scholarship_discover_record(uuid,text,text,text,int,jsonb,jsonb,text)', $o$security.url_on_provider_site(c->>'url', coalesce(p_site_origin,(select website from pipeline.scholarship_discovery_providers where provider_id=p_provider_id)))$o$, $n$(security.url_on_provider_sites(c->>'url', p_provider_id) or security.url_on_provider_site(c->>'url', p_site_origin))$n$],
  array['public.svc_scholarship_search_record(uuid,text,text,jsonb,jsonb)', $o$security.url_on_provider_site(x->>'url', v_site)$o$, $n$security.url_on_provider_sites(x->>'url', v_pid)$n$],
  array['security.scholarship_admit_from_provider_page_v1(bigint)', $o$not security.url_on_provider_site(v_url, coalesce(d.site_origin,d.website))$o$, $n$not security.url_on_provider_sites(v_url, c.provider_id)$n$]];
  i int;
begin
  for i in 1..array_length(pairs,1) loop
    v:=pg_get_functiondef(pairs[i][1]::regprocedure);
    if position(pairs[i][2] in v)=0 then raise exception 'anchor not found in %', pairs[i][1]; end if;
    execute replace(v, pairs[i][2], pairs[i][3]);
  end loop;
end $patch$;

-- the worker receives the provider's other domains
create or replace function public.svc_scholarship_discover_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.scholarship_discovery_providers d
     where d.status='pending' and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
     order by d.priority, d.provider_id limit greatest(1,least(coalesce(p_limit,3),6)) for update skip locked),
  upd as (update pipeline.scholarship_discovery_providers d set leased_until=now()+interval '5 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website, d.reason, d.allowed_hosts)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,'reason',u.reason,'hosts',to_jsonb(u.allowed_hosts),
           'names',security.provider_name_list(u.provider_id),'held',security.scholarship_held_without_page(u.provider_id))),'[]'::jsonb) into v from upd u;
  return v;
end $f$;
create or replace function public.svc_scholarship_search_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','scholarship','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.id, s.name, s.provider_id, coalesce(d.site_origin,d.website) site, d.allowed_hosts from scholarship.scholarships s
      join pipeline.scholarship_discovery_providers d on d.provider_id=s.provider_id and d.status in ('mapped','empty','failed')
     where s.lifecycle_status='active' and s.source_url ~* 'studyaustralia\.gov\.au'
       and not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and not (sp.url_source='discovered' and sp.read_status='name_mismatch'))
       and not exists (select 1 from pipeline.scholarship_page_searches q where q.scholarship_id=s.id)
     order by d.priority, s.provider_id, s.name limit greatest(1,least(coalesce(p_limit,5),20))),
  ins as (insert into pipeline.scholarship_page_searches(scholarship_id,status) select id,'leased' from pick on conflict do nothing returning scholarship_id)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',p.id,'name',p.name,'provider_id',p.provider_id,'site',p.site,'hosts',to_jsonb(p.allowed_hosts),'names',security.provider_name_list(p.provider_id))),'[]'::jsonb)
    into v from pick p join ins on ins.scholarship_id=p.id;
  return v;
end $f$;
create or replace function public.svc_scholarship_candidate_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select c.id from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and security.australian_university(c.provider_id)
     order by (d.priority not in (0,3)), (c.url ~* 'international') desc, c.found_at, c.id
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $f$;

update pipeline.scholarship_discovery_providers set status='pending', attempts=0, leased_until=null where cardinality(allowed_hosts)>0;
