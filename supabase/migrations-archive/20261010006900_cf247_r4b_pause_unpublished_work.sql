-- CF-247 v2.15.237 (R4 part 2): Platform Admin bug list of 10 Oct 2026 — Feature 4, Published switch. Decision: "Hide and pause work".
-- A provider that is unpublished (or not active) no longer has background work picked up for it. Each automatic picker below skips
-- providers in security.provider_hidden_v1 (released in v2.15.236); work already in flight finishes, and everything resumes on its own
-- when the provider is published again. Work a Platform Admin starts by hand (adapter builder, a Firecrawl run, edits) is not blocked,
-- so a provider can be fixed before it is published again.
--  Paused: site search and site hints, course page discovery and binding, page reads and re-reads, AI matching, course link search,
--          tuition hand-off, adapter overwrite, provider facts (search and read), scholarships (discover, search, candidates, read),
--          public contact reads and CRICOS contact reads.
-- Also: public contact emails that the v0.17.35 worker no longer accepts (another service's domain; library, vet hospital, media,
-- security, feedback and similar mailboxes) are cleared from the provider record where the job wrote them, and those providers are
-- read again. Values entered by hand are kept.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('public.svc_coverage_discovery_next(integer)', 'fbf36cac0afff896ea3c57d78f267321', 'public.svc_coverage_site_next(integer)', '541fc3bc341b791870c5d782f224d897', 'public.svc_coverage_read_next(integer)', '1fa1e0343306c940074cb71deb212dcd', 'public.svc_coverage_ai_match_next(integer)', '39a5b17a3ad672f0d4d3178f2ef38459', 'public.svc_course_link_search_next(integer)', 'b33d7a228299a54bdd24f2bf6846ecdd', 'public.svc_site_hint_next(integer)', 'a15edf558246bd8cea4f8166bcf44fb1', 'public.svc_provider_contact_next(integer)', '56a2166538e89ffcfb78ec86acb5fdcc', 'public.svc_cricos_peo_next(integer)', 'ba54cb4dbae2911e0486f99b44473599', 'public.svc_provider_facts_read_next(integer)', '5055f4e5b983a4cabd1288053c26d28f', 'public.svc_provider_facts_search_next(integer)', 'd07880a255ee67a36e8a1f9ee343dad8', 'public.svc_scholarship_candidate_next(integer)', '1e814a8711b173a11ae91008bcd35158', 'public.svc_scholarship_discover_next(integer)', 'def42c139793e3960fb0a7f69b22bde4', 'public.svc_scholarship_read_next(integer)', 'b80a6bde38504b5fe1c85c977387e34b', 'public.svc_scholarship_search_next(integer)', 'a5080c508fbc9b5f360b7ec9142e70b2', 'public.svc_coverage_tuition_handoff_next(integer)', '3c6ac403fac3d2c9ab1f3e178a8ace9b', 'public.svc_coverage_reextract_next(integer,text)', '47741ef26ceaf6243c48d345de1854b0', 'public.svc_coverage_reidentify_next(integer,text)', '72ac3025d4ae233e88c56d1d40045833', 'security.coverage_bind_tick_v1(integer)', '097055efde54b1b2aea050f2cb4ce878', 'security.course_link_search_tick_v1(integer)', '6ec9d1c6b0cc116d389d753af6cadb00', 'security.adapter_overwrite_v1(integer)', '4ac19108008011bf23a98bdd77d63957');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.svc_coverage_discovery_next(p_limit integer)
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
     where (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,
           'courses',(select count(*) from catalogue.courses c where c.provider_id=u.provider_id and c.lifecycle_status='active'))),'[]'::jsonb) into v from upd u;
  return v;
end $function$;

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
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes' from pick where d.provider_id=pick.provider_id returning d.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'name',coalesce(p.display_name,p.canonical_name),'trading',p.short_name,
           'cricos',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='cricos'),'country',security.coverage_country(u.provider_id),
           'dli',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='ircc_dli'))),'[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id=u.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with due as (
    select p.course_id, p.provider_id, p.status st, coalesce(pp.rank,100000) prank, coalesce(cp.sort,1000000) csort, row_number() over (partition by p.provider_id order by (p.status<>'bound'), p.next_read_at) rk
      from pipeline.coverage_course_pages p left join pipeline.provider_priority pp on pp.provider_id=p.provider_id left join pipeline.course_priority cp on cp.course_id=p.course_id
     where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)),  -- v2.15.237: paused while the provider is unpublished or archived
  pick as (select course_id from due where rk<=8 order by csort, least(prank,101), (st<>'bound'), rk, random() limit greatest(1,least(coalesce(p_limit,20),60))),
  upd as (update pipeline.coverage_course_pages p set leased_until=now()+interval '10 minutes', read_attempts=p.read_attempts+1
            from pick where p.course_id=pick.course_id returning p.course_id, p.provider_id, p.url, p.status, p.basis)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'provider_id',u.provider_id,'url',u.url,'title',c.canonical_title,'code',c.course_code,'country',security.coverage_country(u.provider_id),'status',u.status,'basis',u.basis,'manual',coalesce(u.basis='manual',false),'rendered_before',(exists (select 1 from pipeline.coverage_course_pages q where q.course_id=u.course_id and q.fetched_via='firecrawl') or exists (select 1 from pipeline.page_link_repairs x where x.course_id=u.course_id and x.reason like 'university adapter: international view read%')),'priority',coalesce((select pp.rank<=100 from pipeline.provider_priority pp where pp.provider_id=u.provider_id),false) or exists (select 1 from pipeline.course_priority cp where cp.course_id=u.course_id))),'[]'::jsonb)
    into v from upd u join catalogue.courses c on c.id=u.course_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_ai_match_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select q.id from pipeline.coverage_ai_match q
      left join pipeline.course_priority cp on cp.course_id = q.course_id
      left join pipeline.provider_priority pp on pp.provider_id = q.provider_id
     where (q.state = 'ready' or (q.state = 'leased' and q.leased_until < now()))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (q.state = 'leased'), coalesce(cp.sort, 1000000), coalesce(pp.rank, 100000), q.id
     limit greatest(1, least(coalesce(p_limit, 20), 80)) for update of q skip locked),
  upd as (update pipeline.coverage_ai_match q set state = 'leased', leased_until = now() + interval '10 minutes' from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'course_id', u.course_id, 'provider_id', u.provider_id, 'title', co.canonical_title,
           'code', case when co.course_code ~ '^[0-9a-f]{8}-' then null else co.course_code end,
           'level', (select sl.name from ref.study_levels sl where sl.id = co.study_level_id),
           'provider', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(u.provider_id),
           'candidates', u.candidates)), '[]'::jsonb)
    into v from upd u join catalogue.courses co on co.id = u.course_id join catalogue.providers pr on pr.id = u.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_course_link_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on boolean; v_cap numeric; v_used numeric; v_lim int := greatest(1, least(coalesce(p_limit, 40), 200)); v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if not coalesce(v_on, false) or v_used + 2 * v_lim > v_cap then return '[]'::jsonb; end if;
  with pick as (
    select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
      from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
      join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
      left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
     where s.state = 'queued'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (s.stage <> 'cricos'), coalesce(pp.rank, 100000), md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
     limit v_lim
     for update of s skip locked),
  upd as (
    update pipeline.course_link_search s set state = 'sent', sent_at = now(), req_id = null,
           query = case p.stage when 'cricos' then '"' || p.course_code || '" site:' || p.search_domain
                                else case when security.coverage_country(p.provider_id) = 'CA'
                                     then trim(regexp_replace(regexp_replace(regexp_replace(p.canonical_title, '\s*\([^)]*\)', ' ', 'g'), '\s+-\s+(UBCV|UBCO|Major|Honours|Open Learning)\M.*$', '', 'i'), '[:"]+', ' ', 'g')) || ' site:' || p.search_domain
                                     else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end end
      from pick p where s.course_id = p.course_id
    returning s.course_id, s.provider_id, s.stage, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'provider_id', provider_id, 'stage', stage, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_site_hint_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with hints as (
    -- v2.15.233 (Feature 3): hints from third-party directories (Hotcourses, univ.cc) are no longer used; Hotcourses stays for logos only
    select r.provider_id, u url, 'hipo' via from pipeline.reference_institutions r, unnest(r.web_pages) u where r.provider_id is not null),
  todo as (
    select h.provider_id, jsonb_agg(distinct jsonb_build_object('url', h.url, 'via', h.via)) urls
      from hints h
      left join pipeline.coverage_provider_discovery d on d.provider_id = h.provider_id
     where (d.provider_id is null or d.status in ('no_website', 'failed') or d.website is null)
       and exists (select 1 from catalogue.courses co where co.provider_id = h.provider_id and co.lifecycle_status = 'active')
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = h.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and not exists (select 1 from pipeline.site_hint_checks c where c.provider_id = h.provider_id and c.url = h.url
                         and (c.accepted or coalesce(c.evidence->>'worker', '') not in ('coverage-sweep-worker-v0.10.0', 'coverage-sweep-worker-v0.10.1', 'coverage-sweep-worker-v0.10.2', 'coverage-sweep-worker-v0.10.3')))
     group by 1 limit greatest(1, least(coalesce(p_limit, 20), 60)))
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', t.provider_id, 'name', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(t.provider_id),
           'cricos', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'cricos' limit 1),
           'dli', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'ircc_dli' limit 1),
           'urls', t.urls)), '[]'::jsonb)
    into v from todo t join catalogue.providers pr on pr.id = t.provider_id;
  return v;
end $function$;

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
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)  -- v2.15.237: paused while the provider is unpublished or archived
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'public_general' and k.checked_at > now() - interval '90 days')
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 8), 20))),
  lease as (insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome) select id, 'public_general', now(), 'leased' from pick
            on conflict (provider_id, kind) do update set checked_at = now(), outcome = 'leased' returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.name, 'website', p.website, 'country', p.country)), '[]'::jsonb) into v
    from pick p where p.id in (select provider_id from lease);
  return v;
end $function$;

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
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)  -- v2.15.237: paused while the provider is unpublished or archived
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
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_facts_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select f.id from pipeline.provider_fact_sources f
     where ((f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id))
            or f.kind in ('english_policy', 'intake_calendar'))
       and (f.status = 'found' or (f.status = 'reading' and f.updated_at < now() - interval '20 minutes')) and f.attempts < 3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (f.linked_from is null), f.rank,
              (select count(*) from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active') desc, f.created_at limit greatest(1, least(coalesce(p_limit, 10), 30))
     for update skip locked),
  upd as (update pipeline.provider_fact_sources f set status = 'reading', attempts = f.attempts + 1, updated_at = now() from pick where f.id = pick.id
          returning f.id, f.provider_id, f.kind, f.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'kind', u.kind, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'currency', (select a.currency_code from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_facts_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id, s.kind, r.search_domain
      from pipeline.provider_fact_search s join pipeline.course_link_recipes r on r.provider_id = s.provider_id and r.active
     where (s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < 3))
       and (s.kind <> 'fee_schedule' or security.tuition_chase_enabled(s.provider_id))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (s.kind <> 'fee_schedule'), s.queued_at, s.provider_id limit greatest(1, least(coalesce(p_limit, 20), 60))
     for update of s skip locked),
  upd as (
    update pipeline.provider_fact_search s set state = 'sent', sent_at = now(), attempts = s.attempts + 1,
           query = case p.kind when 'fee_schedule' then 'international student tuition fees site:' || p.search_domain
                               when 'english_policy' then 'English language requirements international students site:' || p.search_domain
                               else 'academic calendar key dates intakes site:' || p.search_domain end
      from pick p where s.provider_id = p.provider_id and s.kind = p.kind
    returning s.provider_id, s.kind, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'kind', kind, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with ranked as (
    select c.id, d.priority, row_number() over (partition by c.provider_id order by (c.url ~* 'international') desc, c.found_at, c.id) rn
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)),  -- v2.15.237: paused while the provider is unpublished or archived
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by r.rn, (r.priority not in (0,3)), c.id
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_discover_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.scholarship_discovery_providers d
     where d.status='pending' and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by d.priority, d.provider_id limit greatest(1,least(coalesce(p_limit,3),6)) for update skip locked),
  upd as (update pipeline.scholarship_discovery_providers d set leased_until=now()+interval '5 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website, d.reason, d.allowed_hosts)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,'reason',u.reason,'hosts',to_jsonb(u.allowed_hosts),
           'names',security.provider_name_list(u.provider_id),'held',security.scholarship_held_without_page(u.provider_id))),'[]'::jsonb) into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.scholarship_id from pipeline.scholarship_pages p join scholarship.scholarships s on s.id=p.scholarship_id and s.lifecycle_status='active'
     where p.next_read_at<=now() and coalesce(p.leased_until,'-infinity')<now() and p.attempts<5
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by p.read_at nulls first limit greatest(1,least(coalesce(p_limit,20),40)) for update of p skip locked),
  upd as (update pipeline.scholarship_pages p set leased_until=now()+interval '10 minutes', attempts=p.attempts+1 from pick where p.scholarship_id=pick.scholarship_id
          returning p.scholarship_id, p.url, p.url_source)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',u.scholarship_id,'url',u.url,'name',s.name,'provider_id',s.provider_id,'currency',scholarship.provider_currency(s.provider_id),'url_source',u.url_source,'names',security.provider_name_list(s.provider_id))),'[]'::jsonb) into v
    from upd u join scholarship.scholarships s on s.id=u.scholarship_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.id, s.name, s.provider_id, coalesce(d.site_origin,d.website) site, d.allowed_hosts from scholarship.scholarships s
      join pipeline.scholarship_discovery_providers d on d.provider_id=s.provider_id and d.status in ('mapped','empty','failed')
     where s.lifecycle_status='active' and security.reference_url_has_use(s.source_url, 'scholarship_placeholder')
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and not (sp.url_source='discovered' and sp.read_status in ('name_mismatch','robots_disallowed','gone')))
       and not exists (select 1 from pipeline.scholarship_page_searches q where q.scholarship_id=s.id)
     order by d.priority, s.provider_id, s.name limit greatest(1,least(coalesce(p_limit,5),20))),
  ins as (insert into pipeline.scholarship_page_searches(scholarship_id,status) select id,'leased' from pick on conflict do nothing returning scholarship_id)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',p.id,'name',p.name,'provider_id',p.provider_id,'site',p.site,'hosts',to_jsonb(p.allowed_hosts),'names',security.provider_name_list(p.provider_id))),'[]'::jsonb)
    into v from pick p join ins on ins.scholarship_id=p.id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_tuition_handoff_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)) then return '[]'::jsonb; end if;
  with pick as (
    select p.course_id
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id=p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
      join catalogue.providers pr on pr.id=p.provider_id
      join pipeline.coverage_admission_countries ca on ca.country_id=pr.country_id and ca.active
     where p.read_status='read' and p.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb
       and coalesce(p.candidates->'fee'->>'basis','')<>'total' and security.coverage_identity_allowed(p.provider_id, p.identity_basis, 'tuition') and p.l3_work_item_id is null
       and (p.l3_handoff_at is null or p.l3_handoff_at < now()-interval '1 day')
       and security.coverage_tuition_target_v1(p.candidates->'fee') is not null
       and not exists (select 1 from catalogue.course_fees f where f.course_id=p.course_id and f.fee_type='provider_current_tuition' and f.status='active')
       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by p.read_at limit greatest(1,least(coalesce(p_limit,50),100)) for update of p skip locked),
  upd as (update pipeline.coverage_course_pages p set l3_handoff_at=now() from pick where p.course_id=pick.course_id returning p.course_id, p.url, p.evidence_id)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'storage_path',e.storage_path,'url',u.url)),'[]'::jsonb) into v
    from upd u join pipeline.evidence_artifacts e on e.id=u.evidence_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_reextract_next(p_limit integer, p_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('course_id',cp.course_id,'storage_path',e.storage_path,'title',c.canonical_title,'code',c.course_code,'status',cp.status,'url',cp.url,'country',security.coverage_country(cp.provider_id))),'[]'::jsonb)
    into v
    from (select * from pipeline.coverage_course_pages cp0
           where cp0.read_status='read' and cp0.identity_basis is not null and cp0.evidence_id is not null
             and coalesce(cp0.candidates->>'extractor','')<>p_version
             and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = cp0.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
           order by exists (select 1 from pipeline.layer4_review_items r4 where r4.entity_id = cp0.course_id and r4.status = 'pending'
                          and r4.field_code = 'provider_current_tuition_validation') desc, cp0.read_at limit greatest(1,least(coalesce(p_limit,50),200))) cp
    join pipeline.evidence_artifacts e on e.id=cp.evidence_id join catalogue.courses c on c.id=cp.course_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_reidentify_next(p_limit integer, p_rule text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v from (
    select p.course_id, p.evidence_id, e.storage_path, coalesce(nullif(p.candidates->>'final_url', ''), p.url) url, co.canonical_title title, co.course_code code,
           security.coverage_country(p.provider_id) country
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id = p.evidence_id
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.status = 'mismatch' and p.read_status = 'identity_mismatch' and coalesce(p.basis, '') <> 'manual' and e.storage_path is not null
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and not exists (select 1 from pipeline.coverage_reidentify_done d where d.course_id = p.course_id and d.evidence_id = p.evidence_id and d.rule = p_rule)
     order by p.course_id limit greatest(1, least(coalesce(p_limit, 100), 400)) for update of p skip locked) x;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.coverage_bind_tick_v1(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r record; v jsonb:='[]'::jsonb;
begin
  for r in select provider_id from pipeline.coverage_provider_discovery
            where mapped_at is not null and (bound_at is null or bound_at<mapped_at)
              and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = coverage_provider_discovery.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
            order by mapped_at limit greatest(1,least(p_limit,50)) loop
    v:=v||jsonb_build_object('provider_id',r.provider_id,'result',security.coverage_bind_v2(r.provider_id));
  end loop;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.course_link_search_tick_v1(p_batch integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_urls text[]; v_c text[]; v_cap numeric; v_on boolean; v_used numeric; v_key text; v_dom text;
        n_harvest int := 0; n_found int := 0; n_moved int := 0; n_sent int := 0; v_next text;
begin
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;

  -- 1. Collect finished searches.
  for r in select s.*, h.status_code, h.content from pipeline.course_link_search s join net._http_response h on h.id = s.req_id
            where s.state = 'sent' loop
    n_harvest := n_harvest + 1;
    if r.status_code = 200 and left(r.content, 1) = '{' then
      perform public.svc_coverage_usage(2, 'course_link_search', r.provider_id, r.query);
      v_urls := array(select e->>'url' from jsonb_array_elements(coalesce((r.content::jsonb)->'data', '[]'::jsonb)) e);
      v_c := security.course_link_pick_v1(r.provider_id, v_urls);
      if cardinality(v_c) > 0 then
        update pipeline.course_link_search set state = 'found', results = to_jsonb(v_urls), candidates = to_jsonb(v_c), cand_idx = 1,
               bound_url = v_c[1], done_at = now() where course_id = r.course_id;
        perform security.course_link_bind_v1(r.course_id, r.provider_id, v_c[1], case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
        n_found := n_found + 1;
      elsif r.stage = 'cricos' then
        update pipeline.course_link_search set stage = 'title', state = 'queued', results = to_jsonb(v_urls), attempts = 0 where course_id = r.course_id;
      else
        update pipeline.course_link_search set state = 'none', results = to_jsonb(v_urls), done_at = now() where course_id = r.course_id;
      end if;
    else
      update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= 3 then 'error' else 'queued' end,
             results = jsonb_build_object('http_status', r.status_code, 'body', left(r.content, 300)) where course_id = r.course_id;
    end if;
  end loop;
  -- searches with no response after 20 minutes are sent again
  update pipeline.course_link_search set state = 'queued', attempts = attempts + 1
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);

  -- 2. Pages the reader could not confirm move to the next candidate, then to the title search.
  for r in select s.*, p.status pstatus, p.read_status, p.read_attempts from pipeline.course_link_search s
             join pipeline.coverage_course_pages p on p.course_id = s.course_id and p.url = s.bound_url
            where s.state = 'found' and (p.status = 'mismatch' or (p.read_status in ('fetch_failed','blocked','robots_disallowed') and (p.read_attempts >= 2 or p.http_status in (404, 410)))) loop
    if r.cand_idx < jsonb_array_length(r.candidates) then
      v_next := r.candidates->>r.cand_idx;
      update pipeline.course_link_search set cand_idx = cand_idx + 1, bound_url = v_next where course_id = r.course_id;
      perform security.course_link_bind_v1(r.course_id, r.provider_id, v_next, case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
    elsif r.stage = 'cricos' then
      update pipeline.course_link_search set stage = 'title', state = 'queued', attempts = 0, done_at = null where course_id = r.course_id;
    else
      update pipeline.course_link_search set state = 'none', done_at = now() where course_id = r.course_id;
    end if;
    n_moved := n_moved + 1;
  end loop;
  update pipeline.course_link_search s set state = 'verified' from pipeline.coverage_course_pages p
   where s.state = 'found' and p.course_id = s.course_id and p.url = s.bound_url and p.status = 'bound' and p.identity_basis is not null;

  -- 2b. Decision 217: courses without a CRICOS code whose earlier page was read again and is not theirs are searched by title.
  insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
  select p.course_id, p.provider_id, 'title', 'queued', now()
    from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
   where p.status = 'mismatch' and p.basis not in ('cricos_search', 'title_search')
     and coalesce(c.course_code, '') !~ '^[0-9]{6}[0-9A-Z]$'
     and exists (select 1 from pipeline.course_link_recipes rc where rc.provider_id = p.provider_id and rc.active)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     and not exists (select 1 from pipeline.course_link_search s where s.course_id = p.course_id)
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p.course_id and k.field = 'official_url')
   limit 200
  on conflict (course_id) do nothing;

  -- 2c. Decision 252: pages from the Serper search pass, after the reader.
  perform security.search_pass_advance_v1();

  -- 3. Send the next batch, inside the monthly credit cap.
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if v_on and coalesce((select x.send_via from pipeline.course_link_search_settings x where x.id = 1), 'pg_net') = 'pg_net' and v_used + 2 * p_batch <= v_cap then
    v_key := public.svc_coverage_firecrawl()->>'secret';
    if v_key is not null then
      for r in select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
                 from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
                 join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
                 left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
                where s.state = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
                order by (s.stage <> 'cricos'), row_number() over (partition by s.provider_id order by md5(s.course_id::text)), coalesce(pp.rank, 100000)
                limit greatest(1, least(coalesce(p_batch, 40), 100)) loop
        v_dom := case r.stage when 'cricos' then '"' || r.course_code || '" site:' || r.search_domain
                                         else '"' || replace(regexp_replace(r.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || r.search_domain end;
        update pipeline.course_link_search set state = 'sent', sent_at = now(), query = v_dom,
               req_id = net.http_post(url := 'https://api.firecrawl.dev/v1/search',
                          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
                          body := jsonb_build_object('query', v_dom, 'limit', 5), timeout_milliseconds := 60000)
         where course_id = r.course_id;
        n_sent := n_sent + 1;
      end loop;
    end if;
  end if;
  return jsonb_build_object('collected', n_harvest, 'found', n_found, 'moved_on', n_moved, 'sent', n_sent, 'credits_this_month', v_used, 'cap', v_cap);
end $function$;

CREATE OR REPLACE FUNCTION security.adapter_overwrite_v1(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_src uuid; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}'; v_payload jsonb; v_itk text[]; v_ielts numeric; v_band numeric; v_fee numeric; v_fy int; v_cur text; v_mode_n int := 0;
begin
  for r in
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, e.content_hash, pg.candidates c, pg.identity_basis ib, u.admit_fields af, u.reading rd, co.delivery_mode cur_mode, coalesce(security.delivery_mode_from_text(pg.candidates->'adapter_extra'->>'mode'), security.delivery_mode_from_location(coalesce(pg.candidates->'adapter_extra'->>'location', pg.candidates->'adapter_extra'->>'campus'))) new_mode,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id = pg.provider_id and lower(pr.registration_scheme) = 'cricos' and coalesce(pr.status, 'active') not in ('inactive', 'cancelled', 'archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) cc,
           (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') cur_itk,
           (select r2.overall_score from catalogue.course_english_requirements r2 join ref.english_tests t on t.id = r2.english_test_id where r2.course_id = pg.course_id and t.code = 'IELTS' and coalesce(r2.status, 'active') = 'active' limit 1) cur_ielts,
           (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' order by f.fee_year desc nulls last limit 1) cur_fee,
           u.admit adm,
           (select (select array_agg(distinct z::int order by z::int) from jsonb_array_elements_text(l.cv->'months') z)
                   = (select array_agg(distinct extract(month from to_date(i.intake_label, 'Month'))::int order by extract(month from to_date(i.intake_label, 'Month'))::int)
                        from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active' and i.intake_label ~ '^(January|February|March|April|May|June|July|August|September|October|November|December)$')
              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_intake_validation' and jsonb_typeof(x.candidate_value->'months') = 'array' order by x.created_at desc limit 1) l) r5_itk,
           (select (select (t->>'overall')::numeric from jsonb_array_elements(l.cv->'tests') t where t->>'test' = 'IELTS' limit 1)
                   = (select r3.overall_score from catalogue.course_english_requirements r3 join ref.english_tests t3 on t3.id = r3.english_test_id where r3.course_id = pg.course_id and t3.code = 'IELTS' and coalesce(r3.status, 'active') = 'active' limit 1)
              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_english_validation' and jsonb_typeof(x.candidate_value->'tests') = 'array' order by x.created_at desc limit 1) l) r5_eng,
           (select abs((l.cv->>'amount')::numeric - (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' order by f.fee_year desc nulls last limit 1))
                   <= 0.01 * (l.cv->>'amount')::numeric
              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_current_tuition_validation' and (x.candidate_value->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' order by x.created_at desc limit 1) l) r5_fee
      from pipeline.coverage_course_pages pg
      join pipeline.evidence_artifacts e on e.id = pg.evidence_id
      join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
      join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled
       and (u.admit or exists (select 1 from pipeline.layer3_interpretations l3 where l3.entity_type = 'course' and l3.entity_id = pg.course_id and l3.status = 'validated'
                                and l3.task_class in ('provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation')))
     where pg.read_status = 'read' and pg.identity_basis is not null
       and (pg.candidates->>'intakes_by' = 'adapter' or pg.candidates->>'english_by' = 'adapter' or pg.candidates->>'fee_by' = 'adapter' or pg.candidates->'adapter_extra' ? 'mode' or pg.candidates->'adapter_extra' ? 'campus' or pg.candidates->'adapter_extra' ? 'location')
       and security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, null)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pg.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and not security.layer4_entity_or_parent_blocked('course', pg.course_id, 'operational')
  loop
    exit when v_ok >= greatest(1, least(coalesce(p_limit, 200), 1000));
    v_payload := '{}'::jsonb;
    v_itk := (select array_agg(distinct m order by m) from jsonb_array_elements_text(coalesce(r.c->'intakes', '[]'::jsonb)) m);
    if r.c->>'intakes_by' = 'adapter' and v_itk is not null and r.cur_itk is distinct from v_itk
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'intakes') and (('intakes' = any (r.af) and r.adm) or coalesce(r.r5_itk, false)) and not security.uni_adapter_excluded(r.course_id, 'intakes')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('intakes', 'intake')) then
      v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', lower(coalesce(r.cc, r.course_id::text)) || ':current:' || lower(m))) from unnest(v_itk) m));
    end if;
    v_ielts := nullif(r.c->'english'->>'ielts_overall', '')::numeric;
    v_band := nullif(r.c->'english'->>'ielts_min_band', '')::numeric;
    if r.c->>'english_by' = 'adapter' and v_ielts is not null and r.cur_ielts is distinct from v_ielts
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'english') and (('english' = any (r.af) and r.adm) or coalesce(r.r5_eng, false)) and not security.uni_adapter_excluded(r.course_id, 'english')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('english', 'english_requirements')) then
      v_payload := v_payload || jsonb_build_object('english_requirements', jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', v_ielts,
                      'component_scores', case when v_band is null then '{}'::jsonb else jsonb_build_object('listening', v_band, 'reading', v_band, 'writing', v_band, 'speaking', v_band) end,
                      'notes', 'University adapter reading of the course page')));
    end if;
    -- v0.17 (Platform Admin 23:41, decision 4): the international annual fee the adapter read is admitted too
    v_fee := nullif(r.c->'fee'->>'value', '')::numeric;
    v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, security.adapter_fee_year_setting(r.rd), extract(year from now() at time zone 'Australia/Melbourne')::int);
    v_cur := coalesce(nullif(r.c->'fee'->>'currency', ''), case security.coverage_country(r.provider_id) when 'NZ' then 'NZD' when 'CA' then 'CAD' else 'AUD' end);
    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_fee between 1000 and 500000 and (select f.amount from catalogue.course_fees f where f.course_id = r.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fy, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee
       and (('fee' = any (r.af) and r.adm) or coalesce(r.r5_fee, false)) and not security.uni_adapter_excluded(r.course_id, 'fee') and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('tuition', 'fee', 'fees')) then
      v_payload := v_payload || jsonb_build_object('fee_amount', v_fee, 'fee_year', v_fy, 'currency_code', v_cur, 'fee_basis', 'annual', 'audience', 'international',
                     'fee_notes', 'University adapter reading of the course page (international annual fee)',
                     'fee_key', lower(coalesce(r.cc, r.course_id::text)) || ':international:' || coalesce(v_fy::text, 'current') || ':annual');
    end if;
    -- 5 Oct (Platform Admin 11:48): delivery read from the international view of the course page
    if r.new_mode is not null and r.cur_mode is distinct from r.new_mode and ('delivery' = any (r.af) and r.adm) and not security.uni_adapter_excluded(r.course_id, 'delivery')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('delivery_mode', 'delivery')) then
      begin
        update catalogue.courses set delivery_mode = r.new_mode, updated_at = now() where id = r.course_id;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'delivery', to_jsonb(r.cur_mode), to_jsonb(r.new_mode), r.evidence_id, r.url);
        v_mode_n := v_mode_n + 1; v_courses := v_courses || r.course_id;
      exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
      end;
    end if;
    continue when v_payload = '{}'::jsonb;
    begin
      v_src := security.coverage_sweep_source(r.provider_id);
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
        select 'courses', d, v_src, 'approved', 'CF-CHG-20260915-247, Decision 253, Platform Admin 4 Oct 2026 22:43 (adapter readings replace held values)', now(), now(), now()
        from unnest(array_remove(array[case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'provider_current_tuition' end], null)) d
        where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = d and g.source_id = v_src);
      if v_payload ? 'intakes' then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'intakes', to_jsonb(r.cur_itk), to_jsonb(v_itk), r.evidence_id, r.url);
      end if;
      if v_payload ? 'english_requirements' then
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'english_ielts', to_jsonb(r.cur_ielts), to_jsonb(v_ielts), r.evidence_id, r.url);
      end if;
      if v_payload ? 'fee_amount' then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fy, 0) and amount <> v_fee;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'fee', to_jsonb(r.cur_fee), jsonb_build_object('amount', v_fee, 'year', v_fy, 'currency', v_cur), r.evidence_id, r.url);
      end if;
      if r.pc is null or r.cc is null then
        perform security.coverage_apply_course_v1(r.course_id, v_src, r.evidence_id, r.url, r.content_hash, v_payload);
      else
        perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'coverage:' || r.course_id, r.url, r.content_hash, v_payload, true);
      end if;
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where entity_type = 'course' and entity_id = r.course_id and status = 'pending' and field_code in (case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'course_tuition' end);
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('delivery', v_mode_n, 'replaced', v_ok, 'errors', v_err, 'last_error', v_last);
end $function$;

-- Existing data: public contact emails the v0.17.35 worker would not accept are cleared where the job wrote them (the provider's
-- email still equals the job's current value and is not locked by hand); those providers are read again on the next run.
create temp table _r4b_bad on commit drop as
with c as (
  select cp.provider_id, cp.email, lower(split_part(cp.email, '@', 1)) l, lower(split_part(cp.email, '@', 2)) d,
         regexp_replace(lower(substring(p.website from '^(?:https?://)?([^/?#:]+)')), '^www\.', '') h
    from pipeline.provider_contact_points cp join catalogue.providers p on p.id = cp.provider_id
   where cp.kind = 'public_general' and cp.is_current and cp.email is not null and p.email is not distinct from cp.email
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = cp.provider_id and k.field = 'email')),
r as (
  select c.*, substring(regexp_replace(d, '\.((com|net|org|edu|gov|asn|id)\.au|(act|nsw|nt|qld|sa|tas|vic|wa)\.edu\.au|(ac|co|org|net|govt|school)\.nz|com|net|org|edu|ca|nz|au|io|co)$', '') from '([^.]+)$') dl,
              substring(regexp_replace(h, '\.((com|net|org|edu|gov|asn|id)\.au|(act|nsw|nt|qld|sa|tas|vic|wa)\.edu\.au|(ac|co|org|net|govt|school)\.nz|com|net|org|edu|ca|nz|au|io|co)$', '') from '([^.]+)$') hl
    from c)
select provider_id, email from r
 where l ~ '(librar|vethosp|veterinar|hospital|clinic|ethics|philanthrop|partnership|helpdesk|facilit|research)'
    or l ~ '^(media|press|news|security|privacy|feedback|complain|careers?|jobs|hr|alumni|donat|giving|library|helpdesk|service-?desk|research|grants|events|marketing|web(master)?|accounts?|finance|procurement|noreply|no-reply)'
    or not (d = h or d like '%.' || h or h like '%.' || d or dl = hl);

update catalogue.providers p set email = null, updated_at = now() from _r4b_bad b where p.id = b.provider_id and p.email = b.email;
update pipeline.provider_contact_checks k set checked_at = now() - interval '91 days' from _r4b_bad b where k.provider_id = b.provider_id and k.kind = 'public_general';
insert into search.refresh_requests(requested_by) values ('v2.15.237: public contact emails from other services or non-enquiry mailboxes cleared');

do $post$
declare v_expected jsonb := jsonb_build_object('public.svc_coverage_discovery_next(integer)', '7d6ae2fafb981e5b702e8609f18f2460', 'public.svc_coverage_site_next(integer)', '3858a8abeb37fc807c1a3c44880aa659', 'public.svc_coverage_read_next(integer)', '57d2b0878db36196a17995c777116690', 'public.svc_coverage_ai_match_next(integer)', '101f769a77f612817470f2151c4fc3e9', 'public.svc_course_link_search_next(integer)', '1359e0d8038c886520411395e1429d08', 'public.svc_site_hint_next(integer)', '484249152176de062fd1e8415baa1dff', 'public.svc_provider_contact_next(integer)', 'a3ba9860d336963a91b43ffa0b5e350b', 'public.svc_cricos_peo_next(integer)', '448741d90d54f25862567a6caa1af5ec', 'public.svc_provider_facts_read_next(integer)', 'bcc118122628b820d864081b99e215c5', 'public.svc_provider_facts_search_next(integer)', 'ad0e080213c7317450144a5137f00498', 'public.svc_scholarship_candidate_next(integer)', '2f3ccd5c904ea959007a1d2c2120491f', 'public.svc_scholarship_discover_next(integer)', 'cf7cd3c072d589503b53bae1e87cc830', 'public.svc_scholarship_read_next(integer)', 'e2d5ab79976c3d4ff8dc4cc5ed2072f4', 'public.svc_scholarship_search_next(integer)', '3e5ae07b3112bbd1915eda9319d084fe', 'public.svc_coverage_tuition_handoff_next(integer)', 'e93adb4885b70d6a4991e1d8640ab12b', 'public.svc_coverage_reextract_next(integer,text)', '0ddd2a75e0f36303cee45ac10765e1b3', 'public.svc_coverage_reidentify_next(integer,text)', '3e8689f92e9f742e43d821d7617cd441', 'security.coverage_bind_tick_v1(integer)', 'ea26c91e8d74c73f2d0d6569ec1c6fde', 'security.course_link_search_tick_v1(integer)', '9d53e2995f2fb1c80fd2296b8f86c608', 'security.adapter_overwrite_v1(integer)', 'eeeae4a72954f7e1669b45eacc4842c5');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.237 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
