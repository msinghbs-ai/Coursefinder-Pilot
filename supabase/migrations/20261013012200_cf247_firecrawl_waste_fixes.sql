-- CF-247 v2.15.265 (Platform Admin, 13 Oct 2026 09:38-10:0x): credit waste report by university. Over 30 days 63% of scholarship
-- credits and 59% of course-search credits produced nothing; in the last 24 hours 94% of course search went on small and overseas
-- providers. Causes: directory sites used as a provider's site (171 course-search recipes and 178 scholarship rows on ACIR, oneuedu,
-- Study Melbourne, higherstudy and others, which security.third_party_host_v1 already names), small providers and pathway colleges, and the
-- scholarship cap holding the top-50 because of spend before they joined onboarding. Decisions (Platform Admin, 13 Oct 2026):
--   "Block directory sites", "Universities only", "Refusals per university", "Reset cap for top-50"; overseas: "Keep going";
--   course search: "Australia and 30+ courses first", "Flag Victoria Uni and Adelaide Uni", "Never search directory sites",
--   "CRICOS code before title"; "learn and establish how best to find the uni official website ... directory sites never give the
--   provider website, don't search them for it ... use training.gov.au or ASQA ... use CRICOS/RTO code, flag the exceptions";
--   "Credit fixes first".
--   1 One guard at the point of spend: public.svc_fc_spend refuses any Firecrawl spend whose page, or the site: of a search, is a
--     directory (security.third_party_host_v1), whatever the purpose. Every refusal is also counted per university
--     (pipeline.firecrawl_refusals_by_provider).
--   2 Scholarship discovery is for Australian providers with 30+ active CRICOS courses (setting scholarship_min_courses) and overseas
--     universities (unchanged); scholarships already on record are still read again. The 150-credit cap counts from the later of
--     30 days ago and when the university joined onboarding (cohort pick or onboarding start), so the top-50 start afresh.
--     Pickers skip universities that are held, so refused reads no longer churn every minute.
--   3 Search order (course pages and scholarship discovery): top-50, then Australian providers with 30+ CRICOS courses, then overseas,
--     then small providers. CRICOS-code searches already run before title searches for each course; kept within each tier.
--   4 Directory recipes and scholarship rows are switched off (active = false / status 'directory_site'), not deleted.
--   5 Course search held for Victoria University and Adelaide University (pipeline.firecrawl_search_holds) for an adapter check;
--     Search again releases a hold. Needs attention: held universities, providers with no official website found, providers sharing
--     a website.
-- Nothing is dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.svc_fc_spend(numeric,text,uuid,text)": "d6c215dd477d37350fe6346019ab2c76", "public.svc_course_link_search_next(integer)": "6867d7ed9ce10e937353f3804d9155e8", "security.fc_search_stopped_v1()": "5d549edda32f0535a48dad9309c9ced1", "security.scholarship_discovery_refill_v1(integer)": "db4f9875b5ed04d09af730bdc45ef167", "public.svc_scholarship_discover_next(integer)": "cf7cd3c072d589503b53bae1e87cc830", "public.svc_scholarship_candidate_next(integer)": "e712f443fe298d75a89352cdf19b17f7", "public.svc_scholarship_listing_next(integer)": "133c192da3a61c7d41881ba494117dc6", "public.svc_scholarship_read_next(integer)": "bd0b48fcf536e56e4e83a739a26e70b5", "security.platform_notices_v1()": "67bb25dadb4f6af897d261496b2b752a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create table if not exists pipeline.firecrawl_refusals_by_provider(
  day date not null, provider_id uuid not null, grp text not null, reason text not null, n int not null default 0,
  last_at timestamptz not null default now(), primary key (day, provider_id, grp, reason));
create table if not exists pipeline.firecrawl_search_holds(
  provider_id uuid primary key, reason text not null, held_at timestamptz not null default now(), set_by text not null);
alter table pipeline.firecrawl_refusals_by_provider enable row level security;
alter table pipeline.firecrawl_search_holds enable row level security;
revoke all on pipeline.firecrawl_refusals_by_provider, pipeline.firecrawl_search_holds from anon, authenticated;

insert into pipeline.platform_toolset_settings(toolset_key, key, value, kind, label, help, unit, section, sort, min_value, max_value, reason, updated_at)
values ('firecrawl', 'scholarship_min_courses', '30', 'number', 'Scholarships only for Australian providers with at least',
        'Active CRICOS courses. Smaller providers, schools and pathway colleges are not searched for scholarships; scholarships already on record are still read again. Overseas universities are not affected.',
        'courses', 'Daily budget', 685, 0, 1000, 'Platform Admin, 13 Oct 2026: "Universities only"', now())
on conflict (toolset_key, key) do nothing;

-- Active CRICOS-coded courses of a provider
create or replace function security.fc_courses_v1(p_provider_id uuid) returns int language sql stable security definer set search_path = '' as $f$
  select count(*)::int from catalogue.courses c where c.provider_id = p_provider_id and c.lifecycle_status = 'active' and c.course_code ~ '^[0-9]{6}[0-9A-Z]$'
$f$;

-- Search order: 0 top-50 cohort, 1 Australian with 30+ CRICOS courses, 2 overseas, 3 small Australian providers
create or replace function security.fc_provider_tier_v1(p_provider_id uuid) returns int language sql stable security definer set search_path = '' as $f$
  select case when exists (select 1 from pipeline.onboarding_pilot o where o.provider_id = p_provider_id and o.cohort = 'au-top-2026-10-12') then 0
              when security.coverage_country(p_provider_id) is distinct from 'AU' then 2
              when security.fc_courses_v1(p_provider_id) >= 30 then 1 else 3 end
$f$;

-- The site a spend is for: the site: of a search query, or the host of a page
create or replace function security.fc_spend_host_v1(p_url text) returns text language sql immutable set search_path = '' as $f$
  select case when p_url ~* '(^|\s)site:\S+' then regexp_replace(substring(lower(p_url) from 'site:([^\s/]+)'), '^www\.', '')
              when p_url ~* '^https?://' then regexp_replace(substring(lower(p_url) from '^https?://([^/:?#]+)'), '^www\.', '')
              else null end
$f$;

-- Scholarship discovery: Australian providers with enough courses; overseas providers as before
create or replace function security.fc_sch_eligible_v1(p_provider_id uuid) returns boolean language sql stable security definer set search_path = '' as $f$
  select security.coverage_country(p_provider_id) is distinct from 'AU' or security.fc_courses_v1(p_provider_id) >= security.fc_setting_num_v1('scholarship_min_courses', 30)
$f$;

-- The scholarship cap counts from the later of 30 days ago and when the university joined onboarding
create or replace function security.fc_sch_cap_since_v1(p_provider_id uuid) returns timestamptz language sql stable security definer set search_path = '' as $f$
  select greatest(now() - interval '30 days',
                  coalesce((select max(o.picked_at) from pipeline.onboarding_pilot o where o.provider_id = p_provider_id), '-infinity'::timestamptz),
                  coalesce((select max(po.started_at) from pipeline.provider_onboarding po where po.provider_id = p_provider_id), '-infinity'::timestamptz))
$f$;

-- A university whose scholarship work is held: past its cap (or, with p_discovery, not eligible)
create or replace function security.fc_sch_held_v1(p_provider_id uuid, p_discovery boolean) returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false)
     and ((p_discovery and not security.fc_sch_eligible_v1(p_provider_id))
          or (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > security.fc_sch_cap_since_v1(p_provider_id))
             >= security.fc_setting_num_v1('scholarship_cap_per_uni', 150))
$f$;

revoke all on function security.fc_courses_v1(uuid), security.fc_provider_tier_v1(uuid), security.fc_spend_host_v1(text), security.fc_sch_eligible_v1(uuid),
  security.fc_sch_cap_since_v1(uuid), security.fc_sch_held_v1(uuid, boolean) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.svc_fc_spend(p_units numeric, p_purpose text, p_provider_id uuid, p_url text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.265 (Platform Admin, 13 Oct 2026): never a credit on a directory site (a page on it, or a search limited to it), whatever the purpose
  if v_host is not null and security.third_party_host_v1('https://' || v_host) then
    v_why := 'directory_site';
  -- v2.15.265: scholarship site maps and searches only for providers that qualify (Australian with enough courses; overseas as before)
  elsif p_provider_id is not null and p_purpose in ('sch_map', 'sch_search') and not security.fc_sch_eligible_v1(p_provider_id) then
    v_why := 'not_eligible';
  elsif coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then
    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    if security.fc_budget_left_v1(p_purpose) < p_units then
      v_why := case when security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then 'day_total' else 'share' end;
    elsif p_provider_id is not null and v_grp = 'scholarships'
          and (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > security.fc_sch_cap_since_v1(p_provider_id))
              + p_units > security.fc_setting_num_v1('scholarship_cap_per_uni', 150) then
      v_why := 'university_cap';
    elsif p_provider_id is not null and v_grp = 'central'
          and exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and security.fc_purpose_group_v1(x.purpose) = 'central'
                         and x.at > now() - make_interval(days => security.fc_setting_num_v1('central_refresh_days', 30)::int) and x.at < now() - interval '6 hours') then
      v_why := 'not_due';
    elsif p_provider_id is not null and v_grp = 'course_search' and exists (select 1 from security.fc_search_stopped_v1() s where s.provider_id = p_provider_id) then
      v_why := 'search_stopped';
    end if;
  end if;
  if v_why is not null then
    insert into pipeline.firecrawl_budget_refusals(day, grp, reason, n, last_at) values ((now() at time zone 'Australia/Melbourne')::date, v_grp, v_why, 1, now())
    on conflict (day, grp, reason) do update set n = pipeline.firecrawl_budget_refusals.n + 1, last_at = now();
    -- v2.15.265: and per university
    if p_provider_id is not null then
      insert into pipeline.firecrawl_refusals_by_provider(day, provider_id, grp, reason, n, last_at) values ((now() at time zone 'Australia/Melbourne')::date, p_provider_id, v_grp, v_why, 1, now())
      on conflict (day, provider_id, grp, reason) do update set n = pipeline.firecrawl_refusals_by_provider.n + 1, last_at = now();
    end if;
    return false;
  end if;
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500) from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_course_link_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on boolean; v_cap numeric; v_used numeric; v_lim int := greatest(1, least(coalesce(p_limit, 40), 200)); v jsonb; v_stopped uuid[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if not coalesce(v_on, false) or v_used + 2 * v_lim > v_cap then return '[]'::jsonb; end if;
  -- v2.15.262: inside the day's Firecrawl share for course search, and not for universities whose search has stopped
  v_lim := least(v_lim, floor(security.fc_budget_left_v1('course_link_search') / 2)::int);
  if v_lim < 1 then return '[]'::jsonb; end if;
  v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);
  with pick as (
    select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
      from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
      join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
      left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
     where s.state = 'queued'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       -- v2.15.255: while Firecrawl is for target universities only, take only their searches (others were refused and starved the queue)
       and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
            or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = s.provider_id and tc.included))
       and s.provider_id <> all (v_stopped)
       -- v2.15.265: never a search limited to a directory site
       and not security.third_party_host_v1('https://' || rc.search_domain)
     -- v2.15.265: top-50, Australian 30+ courses, overseas, small providers; CRICOS-code searches first within each
     order by security.fc_provider_tier_v1(s.provider_id), (s.stage <> 'cricos'), coalesce(pp.rank, 100000), md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
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

CREATE OR REPLACE FUNCTION security.fc_search_stopped_v1()
 RETURNS TABLE(provider_id uuid, searches bigint, since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with s as (
  with w as (select u.provider_id, greatest(now() - interval '7 days', coalesce(max(r.resumed_at), '-infinity'::timestamptz)) since
               from (select distinct x.provider_id from pipeline.coverage_vendor_usage x where x.purpose = 'course_link_search' and x.at > now() - interval '7 days') u
               left join pipeline.firecrawl_search_resumes r on r.provider_id = u.provider_id group by u.provider_id)
  select w.provider_id, count(*) searches, w.since
    from w join pipeline.coverage_vendor_usage x on x.provider_id = w.provider_id and x.purpose = 'course_link_search' and x.at > w.since and x.at < now() - interval '1 hour'
   where not exists (select 1 from pipeline.coverage_course_pages pg where pg.provider_id = w.provider_id and pg.read_at > w.since and pg.status = 'bound' and pg.read_status = 'read')
   group by w.provider_id, w.since
  having count(*) >= security.fc_setting_num_v1('search_stop_after', 30))
  select s.provider_id, s.searches, s.since from s
  union all
  -- v2.15.265: held by the Platform Admin for an adapter check, until Search again
  select h.provider_id, 0::bigint, h.held_at from pipeline.firecrawl_search_holds h
   where not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at)
     and h.provider_id not in (select s2.provider_id from s s2)
$function$;

CREATE OR REPLACE FUNCTION security.scholarship_discovery_refill_v1(p_keep integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pending int; v_added int := 0;
begin
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status = 'pending';
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'
      from (select p.id provider_id, k.iso_alpha2 cc,
                   coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) website,
                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
               and (k.iso_alpha2 = 'AU' or security.scholarship_university(p.id))
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website, k.iso_alpha2) q
     where q.website is not null
       -- v2.15.265: qualifying providers only, never a directory site; top-50, Australian 30+, overseas
       and security.fc_sch_eligible_v1(q.provider_id) and not security.third_party_host_v1(q.website)
     order by security.fc_provider_tier_v1(q.provider_id), q.n desc, q.provider_id limit greatest(0, p_keep - v_pending)
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  return jsonb_build_object('pending_before', v_pending, 'added', v_added);
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
       and not security.fc_sch_held_v1(d.provider_id, true) and not security.third_party_host_v1(coalesce(d.website, ''))  -- v2.15.265
     order by security.fc_provider_tier_v1(d.provider_id), d.priority, d.provider_id limit greatest(1,least(coalesce(p_limit,3),6)) for update skip locked),
  upd as (update pipeline.scholarship_discovery_providers d set leased_until=now()+interval '5 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website, d.reason, d.allowed_hosts)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,'reason',u.reason,'hosts',to_jsonb(u.allowed_hosts),
           'names',security.provider_name_list(u.provider_id),'held',security.scholarship_held_without_page(u.provider_id))),'[]'::jsonb) into v from upd u;
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
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_listing_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select l.id from pipeline.scholarship_listing_pages l
     where l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = l.provider_id)
       and not security.fc_sch_held_v1(l.provider_id, true) and not security.third_party_host_v1(l.url)  -- v2.15.265
     order by l.next_read_at nulls first, l.id limit greatest(1, least(coalesce(p_limit, 6), 20)) for update skip locked),
  upd as (update pipeline.scholarship_listing_pages l set next_read_at = now() + interval '15 minutes' from pick where l.id = pick.id returning l.id, l.provider_id, l.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url,
           'hosts', (select to_jsonb(coalesce(d.allowed_hosts, '{}') || array[regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '')])
                       from pipeline.scholarship_discovery_providers d where d.provider_id = u.provider_id))), '[]'::jsonb) into v from upd u;
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
       and not security.fc_sch_held_v1(s.provider_id, false)  -- v2.15.265: scholarships on record are read again unless the university is past its cap
     order by (p.requested_at is not null) desc, p.read_at nulls first limit greatest(1,least(coalesce(p_limit,20),40)) for update of p skip locked), -- 11 Oct 2026: on-demand pages first
  upd as (update pipeline.scholarship_pages p set leased_until=now()+interval '10 minutes', attempts=p.attempts+1 from pick where p.scholarship_id=pick.scholarship_id
          returning p.scholarship_id, p.url, p.url_source)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',u.scholarship_id,'url',u.url,'name',s.name,'provider_id',s.provider_id,'currency',scholarship.provider_currency(s.provider_id),'url_source',u.url_source,'names',security.provider_name_list(s.provider_id))),'[]'::jsonb) into v
    from upd u join scholarship.scholarships s on s.id=u.scholarship_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.platform_notices_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w_or int := coalesce((security.toolset_setting('openrouter', 'notice_window_hours'))::text::int, 24);
  w_job int := coalesce((security.toolset_setting('scheduled_jobs', 'notice_window_hours'))::text::int, 24);
  w_edge int := coalesce((security.toolset_setting('edge_functions', 'notice_window_hours'))::text::int, 6);
  v_or_mode text := coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop');
  v jsonb := '[]'::jsonb;
begin
  -- v2.15.258 (bug 12/10-01): OpenRouter notices for the AI uses that run now (Layer 3 retired on 12 Oct 2026). Refused calls
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:refused:' || z.code, 'layer', 2, 'toolset', 'openrouter', 'kind', 'refused', 'severity', 'high',
      'title', case z.code when 'credit' then 'OpenRouter refused calls: out of credit'
                           when 'key_limit' then 'OpenRouter refused calls: the key''s own spending limit was reached'
                           when 'rate' then 'OpenRouter refused calls: rate limit'
                           else 'OpenRouter refused calls: key not accepted' end,
      'detail', format('%s AI calls in the last %s hours were refused; those pages are read again later.', z.n, w_or),
      'hint', case z.code when 'credit' then 'Top up the OpenRouter balance; the refused pages are read again by themselves.'
                          when 'key_limit' then 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in StudySearch. Raise or clear it there.'
                          when 'rate' then 'Usually clears by itself; the pages are read again.'
                          else 'Check the OpenRouter key on Settings.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select case when r.e ilike '%key limit%' or r.e ilike '%weekly limit%' then 'key_limit' when r.e ~ 'HTTP 402' or r.e ilike '%credit%' then 'credit'
                      when r.e ~ 'HTTP 429' then 'rate' else 'key' end code, count(*) n, min(r.at) first_at, max(r.at) last_at
          from (select x.error e, x.at from pipeline.scholarship_ai_extractions x where x.at > now() - make_interval(hours => w_or) and x.error ~ 'HTTP (40[123]|429)'
                union all
                select q.error, coalesce(q.done_at, q.created_at) from pipeline.central_ai_queue q where q.created_at > now() - make_interval(hours => w_or) and q.error ~ 'HTTP (40[123]|429)') r
          group by 1) z), '[]'::jsonb);

  -- OpenRouter balance: below the warning level, below the credit floor, or not read recently (read by the openrouter-balance job)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'openrouter:2:low_balance', 'layer', 2, 'toolset', 'openrouter', 'kind', 'low_balance',
      'severity', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0) then 'high' else 'warning' end,
      'title', format('OpenRouter balance is US$%s', round(o.remaining_usd, 2)),
      'detail', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0)
                     then format('Below the credit floor of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'credit_floor_usd'),
                                 case v_or_mode when 'observe' then 'observe only, so it keeps running until OpenRouter refuses calls' else 'stop at limits, so the scholarship AI and central pages AI have stopped' end)
                     else format('Below the warning level of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'low_balance_warn_usd'),
                                 case v_or_mode when 'observe' then 'observe only' else 'stop at limits' end) end,
      'hint', 'Top up the OpenRouter account the platform''s key uses.',
      'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select * from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1) o
    where o.remaining_usd < greatest(coalesce((security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric, 0),
                                     coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0))
    union all
    select jsonb_build_object('key', 'openrouter:2:not_observed', 'layer', 2, 'toolset', 'openrouter', 'kind', 'not_observed', 'severity', 'warning',
      'title', 'OpenRouter balance has not been read recently',
      'detail', format('Last reading %s.', coalesce(to_char(o.observed_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), 'never')),
      'hint', 'The balance is read every 15 minutes by the scheduled job "Read the OpenRouter balance" (openrouter-balance); check it in Scheduled jobs.',
      'count', 1, 'first_at', o.observed_at, 'last_at', now())
    from (select max(observed_at) observed_at from pipeline.layer3_openrouter_observations where kind = 'credits') o
    where o.observed_at is null or o.observed_at < now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30))
  ) q), '[]'::jsonb);

  -- An AI use past its daily guard today (UTC day)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:over_guard:' || g.use || ':' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'openrouter', 'kind', 'over_guard',
      'severity', case v_or_mode when 'observe' then 'info' else 'warning' end,
      'title', format('%s spent US$%s today, past its guard of US$%s', g.label, g.spent, g.guard),
      'detail', case v_or_mode when 'observe' then 'Observe only: it keeps running. This is recorded for the top-up review.'
                     else 'Stop at limits: it has stopped until the UTC day changes (adapter proposals stop at their own allowance; course-page matching is observed only).' end,
      'hint', 'Change the guard or the mode on Models & services › OpenRouter (AI models) › Daily guards.',
      'count', 1, 'first_at', now(), 'last_at', now()))
    from security.ai_spend_today_v1() g where g.guard > 0 and g.spent >= g.guard), '[]'::jsonb);

  -- Firecrawl balance, scholarship share, course-link search cap (Layer 2)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'firecrawl:2:low_balance', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('Firecrawl has %s credits left this month', o.remaining_units),
      'detail', format('Below the warning level of %s. The period ends %s.', security.toolset_setting('firecrawl', 'low_balance_warn_units'), to_char(o.period_end at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
      'hint', 'Work that needs Firecrawl stops at the reserve set on Scrapers & fetchers.', 'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select v2.* from pipeline.vendor_credit_observations v2 join pipeline.layer2_acquisition_providers p on p.id = v2.provider_id and p.provider_key = 'firecrawl' order by v2.observed_at desc limit 1) o
    where o.remaining_units < coalesce((security.toolset_setting('firecrawl', 'low_balance_warn_units'))::text::numeric, 0)
    union all
    -- v2.15.262: the day's Firecrawl budget (a share, or the billed total) at 80% or more
    select jsonb_build_object('key', 'firecrawl:2:daily:' || b.grp || ':' || to_char(now() at time zone 'Australia/Melbourne', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'daily_budget',
      'severity', case when b.used >= b.cap then 'high' else 'warning' end,
      'title', format('Firecrawl daily budget, %s: %s of %s credits used', b.label, round(b.used), round(b.cap)),
      'detail', case when b.used >= b.cap then 'Used up: this work waits until midnight, Melbourne time.' else 'At 80% or more; this work stops for the day when it is used up.' end,
      'hint', 'Credits by university and the budget settings are on Toolsets › Firecrawl.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select 'total' grp, 'billed today' label, (st->>'billed_today')::numeric used, (st->>'total')::numeric cap, (st->>'on')::boolean is_on from security.fc_budget_status_v1() st
          union all
          select g->>'group', g->>'label', (g->>'used')::numeric, (g->>'share')::numeric, (st->>'on')::boolean
            from security.fc_budget_status_v1() st, jsonb_array_elements(st->'groups') g) b
    where b.is_on and b.cap > 0 and b.used >= 0.8 * b.cap
    union all
    select jsonb_build_object('key', 'firecrawl:2:search_stopped', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_stopped', 'severity', 'warning',
      'title', format('Course-page search stopped for %s universities', s.n),
      'detail', format('No correct course page after %s searches. Usually the website on record is wrong or the site hides its course pages from search.', security.fc_setting_num_v1('search_stop_after', 30)),
      'hint', 'Toolsets › Firecrawl › Credits by university: check the website, then press Search again.', 'count', s.n, 'first_at', now(), 'last_at', now())
    from (select count(*) n from security.fc_search_stopped_v1()) s where s.n > 0
    union all
    -- v2.15.265: course search held for an adapter check, by name
    select jsonb_build_object('key', 'firecrawl:2:search_held', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_held', 'severity', 'warning',
      'title', format('Course-page search held for %s: %s', count(*), string_agg(coalesce(p.display_name, p.canonical_name), ', ' order by p.canonical_name)),
      'detail', string_agg(coalesce(p.display_name, p.canonical_name) || ': ' || h.reason, '; ' order by p.canonical_name),
      'hint', 'Check the university''s adapter and website, then press Search again on Toolsets › Firecrawl › Credits by university.', 'count', count(*), 'first_at', min(h.held_at), 'last_at', now())
    from pipeline.firecrawl_search_holds h join catalogue.providers p on p.id = h.provider_id
   where not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at)
  having count(*) > 0
    union all
    -- v2.15.265: Australian providers whose official website was searched for and not found
    select jsonb_build_object('key', 'firecrawl:2:no_official_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'no_official_site', 'severity', 'info',
      'title', format('%s Australian providers have no official website found', count(*)),
      'detail', 'Not in the CRICOS register, TEQSA or training.gov.au, and no site showing their CRICOS code. Course pages and scholarships are not searched for them.',
      'hint', 'Enter the website by hand on the provider if you know it.', 'count', count(*), 'first_at', min(d.site_searched_at), 'last_at', max(d.site_searched_at))
    from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id and p.lifecycle_status = 'active'
   where d.status = 'no_website' and d.site_searched_at is not null and nullif(btrim(p.website), '') is null and security.coverage_country(d.provider_id) = 'AU'
  having count(*) > 0
    union all
    -- v2.15.265: providers sharing one website (pathway colleges on their university's site): their searches read the other's pages
    select jsonb_build_object('key', 'firecrawl:2:shared_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'shared_site', 'severity', 'info',
      'title', format('%s providers share a website with another provider', sum(z.n)),
      'detail', 'Examples: ' || string_agg(z.host, ', ' order by z.n desc) filter (where z.rk <= 5),
      'hint', 'Usually a pathway college on its university''s site. Give the college its own website, or leave it: scholarships are not searched for providers with fewer than 30 courses.', 'count', sum(z.n), 'first_at', now(), 'last_at', now())
    from (select y.host, y.n, row_number() over (order by y.n desc, y.host) rk from (
            select security.fc_spend_host_v1(p.website) host, count(*) n from catalogue.providers p
             where p.lifecycle_status = 'active' and p.website ~* '^https?://' group by 1 having count(*) > 1) y where y.host is not null) z
  having count(*) > 0
    union all
    select jsonb_build_object('key', 'firecrawl:2:scholarship_share', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Scholarship Firecrawl share: %s of %s credits used', s.used, s.cap),
      'detail', format('Fewer than the reserve of %s are left, so newly found scholarship pages that refuse a direct read are not read.', s.reserve),
      'hint', 'Raise the cap on Layer 2 › Scholarships if you want them read.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select (b->>'used')::numeric used, (b->>'cap')::numeric cap, (b->>'reserve')::numeric reserve
          from (select jsonb_build_object(
                  'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
                  'cap', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_cap'),
                  'reserve', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_reserve')) b) q) s
    where s.cap - s.used <= s.reserve
    union all
    select jsonb_build_object('key', 'firecrawl:2:course_link_cap:' || to_char(now(), 'YYYY-MM'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Course-link search used %s of its %s monthly credits', l.used, l.cap),
      'detail', 'Course-link search stops for the rest of the month.', 'hint', 'Change the monthly cap on Jobs › Priority.',
      'count', 1, 'first_at', now(), 'last_at', now())
    from (select (select monthly_credit_cap from pipeline.course_link_search_settings limit 1) cap,
                 (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now())) used) l
    where l.used >= l.cap
  ) q), '[]'::jsonb);

  -- Scheduled jobs that timed out or failed (the job's layer)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'scheduled_jobs:' || z.layer || ':' || z.kind || ':' || z.jobname, 'layer', z.layer, 'toolset', 'scheduled_jobs', 'kind', z.kind,
      'severity', case when z.n >= 5 then 'high' else 'warning' end,
      'title', case z.kind when 'timeout' then format('Job "%s" hit the database time limit %s times', z.jobname, z.n)
                           else format('Job "%s" failed %s times', z.jobname, z.n) end,
      'detail', format('In the last %s hours (%s runs in all). Last message: %s', w_job, z.runs, z.msg),
      'hint', case z.kind when 'timeout' then 'Lower the job''s batch size setting so each run finishes inside the limit.' else 'Usually clears by itself (for example a deadlock); if it repeats, the job needs a fix.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    -- (11 Oct 2026: the run history is read once, last 7 days; only the jobs that failed are ranked for "last three runs succeeded")
    from (with hist as materialized (select h.jobid, h.status, h.return_message, h.start_time, h.end_time
                                       from cron.job_run_details h where h.start_time > now() - interval '7 days'),
               fd as materialized (select * from hist where status = 'failed' and end_time > now() - make_interval(hours => w_job)),
               fj as materialized (select distinct jobid from fd),
               last3 as (select f.jobid, bool_and(t.status = 'succeeded') ok, count(*) c from fj f
                           cross join lateral (select x.status from hist x where x.jobid = f.jobid and x.status in ('succeeded', 'failed')
                                               order by x.start_time desc limit 3) t group by f.jobid),
               runs as (select x.jobid, count(*) n from hist x where x.jobid in (select jobid from fj)
                          and x.end_time > now() - make_interval(hours => w_job) group by x.jobid)
          select j.jobname, coalesce(l.layer, 2) layer,
                 case when d.return_message ilike '%statement timeout%' then 'timeout' else 'failed' end kind,
                 count(*) n, min(d.end_time) first_at, max(d.end_time) last_at, left(max(d.return_message), 140) msg,
                 max(coalesce(rn.n, 0)) runs
          from fd d join cron.job j on j.jobid = d.jobid left join pipeline.platform_job_layers l on l.jobname = j.jobname
          left join last3 l3 on l3.jobid = d.jobid left join runs rn on rn.jobid = d.jobid
          where not (coalesce(l3.ok, false) and coalesce(l3.c, 0) = 3)
          group by j.jobid, j.jobname, l.layer, 3
          having count(*) >= coalesce((security.toolset_setting('scheduled_jobs', 'min_failures'))::text::int, 1)) z), '[]'::jsonb);

  -- Edge function calls that timed out (platform)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'edge_functions:0:timeout', 'layer', 0, 'toolset', 'edge_functions', 'kind', 'timeout', 'severity', 'warning',
      'title', format('%s edge function calls timed out or hit the worker limit', z.n),
      'detail', format('In the last %s hours.', w_edge), 'hint', 'The worker runs too long per call; lower its per-run limit.',
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select count(*) n, min(r.created) first_at, max(r.created) last_at from net._http_response r
          where r.created > now() - make_interval(hours => w_edge) and (r.timed_out or r.status_code in (504, 546))) z
    where z.n >= coalesce((security.toolset_setting('edge_functions', 'min_timeouts'))::text::int, 1)), '[]'::jsonb);

  return v;
end $function$;

-- 4 Directory sites switched off (kept, with a note)
update pipeline.course_link_recipes rc set active = false, updated_at = now(),
       notes = coalesce(rc.notes || ' ', '') || '[v2.15.265, 13 Oct 2026: switched off, ' || rc.search_domain || ' is a directory, not the provider''s own site]'
 where rc.active and security.third_party_host_v1('https://' || rc.search_domain);
update pipeline.scholarship_discovery_providers d set status = 'directory_site', updated_at = now(),
       last_error = '[v2.15.265, 13 Oct 2026: the website on record is a directory, not the provider''s own site]'
 where d.status <> 'directory_site' and security.third_party_host_v1(coalesce(d.site_origin, d.website, ''));

-- 5 Held for an adapter check
insert into pipeline.firecrawl_search_holds(provider_id, reason, set_by) values
 ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7', '676 search credits in 30 days for 1 correct course page and 133 wrong ones; check the adapter''s course pages (vu.edu.au)', 'Platform Admin, 13 Oct 2026'),
 ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', '1,048 search credits in 30 days for 23 correct course pages and 219 wrong ones; check the website and adapter after the 2026 merger (adelaideuni.edu.au)', 'Platform Admin, 13 Oct 2026')
on conflict (provider_id) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('firecrawl', 'waste_fixes', 'v2.15.265', jsonb_build_object('decided', 'Platform Admin, 13 Oct 2026',
        'recipes_off', (select count(*) from pipeline.course_link_recipes where not active and notes like '%v2.15.265%'),
        'scholarship_rows_off', (select count(*) from pipeline.scholarship_discovery_providers where status = 'directory_site'),
        'held', (select count(*) from pipeline.firecrawl_search_holds), 'change', 'CF-247 v2.15.265'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

do $post$
declare v_expected jsonb := '{"public.svc_fc_spend(numeric,text,uuid,text)": "b49dd1f2a71dd94e8584d02655109bdf", "public.svc_course_link_search_next(integer)": "2c4d40559740576a20b33d6f404a842a", "security.fc_search_stopped_v1()": "52f4f34ec18f4e3330330d3c15591e81", "security.scholarship_discovery_refill_v1(integer)": "ef694f93915004f2a45500f394226e42", "public.svc_scholarship_discover_next(integer)": "e95b75eebb347fe10f52da089b7df113", "public.svc_scholarship_candidate_next(integer)": "5034833c89c7e64f55b0b54541d52588", "public.svc_scholarship_listing_next(integer)": "f8184295da30ebd598115ce2ea45f616", "public.svc_scholarship_read_next(integer)": "89879c6d4ce91219aafd800906edb2de", "security.platform_notices_v1()": "d1869f4f93e6e0ff752aa72afb7fd48d"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.265 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $chk$
begin
  if exists (select 1 from pipeline.course_link_recipes rc where rc.active and security.third_party_host_v1('https://' || rc.search_domain)) then raise exception 'v2.15.265 post-check: a directory recipe is still on'; end if;
  if (select count(*) from pipeline.firecrawl_search_holds) < 2 then raise exception 'v2.15.265 post-check: holds missing'; end if;
  if security.fc_spend_host_v1('"Diploma" site:search.acir.com.au') <> 'search.acir.com.au' or security.fc_spend_host_v1('https://www.oneuedu.com/a') <> 'oneuedu.com'
     or security.fc_spend_host_v1('Name CRICOS 01234A') is not null then raise exception 'v2.15.265 post-check: fc_spend_host_v1'; end if;
  if security.fc_provider_tier_v1('bac82321-ded7-4e10-a71d-b18f3ae4d1c7') <> 0 then raise exception 'v2.15.265 post-check: tier'; end if;
end $chk$;
