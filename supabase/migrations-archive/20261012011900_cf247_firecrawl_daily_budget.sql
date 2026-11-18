-- CF-247 v2.15.262 (Platform Admin, 12 Oct 2026 21:47, Firecrawl credits): "Report Firecrawl credit used per uni and pages produced,
-- that will give us how much waste is happening, and tweak it along." Decisions: all five tweaks, a daily budget of 15,000 credits.
-- 388,706 credits were left for 21 days (about 18,500 a day); after v2.15.261 the use was about 31,000 a day.
--   1 Daily Firecrawl budget (Melbourne day), split by purpose: course search 6,000, fallback reads 3,000, scholarships 3,500,
--     central pages 1,500, other 1,000; and the day's billed credits (vendor balance readings) never past 15,000. Every worker spend
--     goes through public.svc_fc_spend (it checks, then records); refusals are counted in pipeline.firecrawl_budget_refusals.
--     Settings on Toolsets › Firecrawl › Daily budget (Platform Admin, with a reason).
--   2 Course-page search stops for a university after 30 searches (more than an hour old) in 7 days with no correct page read; it is
--     listed as "search stopped" and resumes when a person presses Search again (pipeline.firecrawl_search_resumes).
--   3 Wrong pages: the next stored candidate is already tried first, read directly (course_link_search_tick_v1 step 2); no change.
--   4 Per-university caps: scholarship work 150 credits in 30 days; central pages read again only after 30 days.
--   5 Credits by university: security.firecrawl_credits_report_v1(hours) (credits by purpose, correct and wrong pages, credits per correct
--     page, waste flags), read by admin_firecrawl_credits on Toolsets › Firecrawl and by the hourly pilot update.
--   Notices: a share or the day's total at 80% or more, and universities whose search has stopped.
-- Nothing is dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "f0aa2519e42b7258e3951deb736db72f", "security.platform_notices_v1()": "e2d636a28c72efbe828eee385da67f00"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create index if not exists coverage_vendor_usage_at_idx on pipeline.coverage_vendor_usage (at);
create index if not exists coverage_vendor_usage_provider_at_idx on pipeline.coverage_vendor_usage (provider_id, at);
create index if not exists coverage_course_pages_provider_read_at_idx on pipeline.coverage_course_pages (provider_id, read_at);

create table if not exists pipeline.firecrawl_budget_refusals(
  day date not null, grp text not null, reason text not null, n int not null default 0, last_at timestamptz not null default now(),
  primary key (day, grp, reason));
create table if not exists pipeline.firecrawl_search_resumes(
  id bigserial primary key, provider_id uuid not null, resumed_at timestamptz not null default now(), reason text not null, set_by uuid);
alter table pipeline.firecrawl_budget_refusals enable row level security;
alter table pipeline.firecrawl_search_resumes enable row level security;
revoke all on pipeline.firecrawl_budget_refusals, pipeline.firecrawl_search_resumes from anon, authenticated;

insert into pipeline.platform_toolset_settings(toolset_key, key, value, kind, label, help, unit, section, sort, min_value, max_value, reason, updated_at)
values
 ('firecrawl', 'daily_budget_on', 'true', 'boolean', 'Keep to the daily budget', 'Yes: Firecrawl work stops for the day (Melbourne time) when its share or the day''s total is used. No: observe only.', null, 'Daily budget', 600, null, null, 'Platform Admin, 12 Oct 2026 21:47: 15,000 a day', now()),
 ('firecrawl', 'daily_budget_total', '15000', 'number', 'Credits a day (billed)', 'The most credits Firecrawl may bill in a Melbourne day, from the balance read every 15 minutes.', 'credits', 'Daily budget', 610, 0, 100000, 'Platform Admin, 12 Oct 2026 21:47: 15,000 a day', now()),
 ('firecrawl', 'daily_share_course_search', '6000', 'number', 'Share: finding course pages (search)', 'Course-page searches (2 credits each).', 'credits', 'Daily budget', 620, 0, 100000, 'Platform Admin, 12 Oct 2026 21:47', now()),
 ('firecrawl', 'daily_share_reads', '3000', 'number', 'Share: reading pages Firecrawl must read', 'Pages a direct read could not get (blocked, failed or needing a browser), sample pages for adapters, Firecrawl runs.', 'credits', 'Daily budget', 630, 0, 100000, 'Platform Admin, 12 Oct 2026 21:47', now()),
 ('firecrawl', 'daily_share_scholarships', '3500', 'number', 'Share: scholarships', 'Scholarship site maps, searches and page reads.', 'credits', 'Daily budget', 640, 0, 100000, 'Platform Admin, 12 Oct 2026 21:47', now()),
 ('firecrawl', 'daily_share_central', '1500', 'number', 'Share: central pages', 'English policy, academic calendar and other university-wide pages.', 'credits', 'Daily budget', 650, 0, 100000, 'Platform Admin, 12 Oct 2026 21:47', now()),
 ('firecrawl', 'daily_share_other', '1000', 'number', 'Share: other', 'Finding websites, site checks and anything else.', 'credits', 'Daily budget', 660, 0, 100000, 'Platform Admin, 12 Oct 2026 21:47', now()),
 ('firecrawl', 'search_stop_after', '30', 'number', 'Stop searching a university after', 'Searches in 7 days (older than an hour) with no correct course page read. A person presses Search again to resume.', 'searches', 'Daily budget', 670, 5, 1000, 'Platform Admin, 12 Oct 2026 21:47', now()),
 ('firecrawl', 'scholarship_cap_per_uni', '150', 'number', 'Scholarship credits per university (30 days)', 'Scholarship work for one university stops at this many credits in 30 days.', 'credits', 'Daily budget', 680, 0, 5000, 'Platform Admin, 12 Oct 2026 21:47', now()),
 ('firecrawl', 'central_refresh_days', '30', 'number', 'Read central pages again after', 'A university''s central pages are read again only after this many days.', 'days', 'Daily budget', 690, 1, 365, 'Platform Admin, 12 Oct 2026 21:47', now())
on conflict (toolset_key, key) do nothing;

create or replace function security.fc_purpose_group_v1(p text) returns text language sql immutable set search_path = '' as $f$
  select case when p = 'course_link_search' then 'course_search'
              when p like 'sch\_%' then 'scholarships'
              when p in ('central_map', 'central_scrape') or p like 'provider\_facts%' then 'central'
              when p in ('scrape', 'fc_read', 'fc_probe', 'site_hint', 'adapter_builder') or p like 'fcx\_%' then 'reads'
              else 'other' end
$f$;

create or replace function security.fc_day_start_v1() returns timestamptz language sql stable set search_path = '' as $f$
  select date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne'
$f$;

-- Credits Firecrawl billed since the start of the Melbourne day (balance readings; a new billing period counts from its first reading)
create or replace function security.fc_billed_today_v1() returns numeric language sql stable security definer set search_path = '' as $f$
  with o as (select v.observed_at, v.remaining_units, v.period_end from pipeline.vendor_credit_observations v
               join pipeline.layer2_acquisition_providers p on p.id = v.provider_id and p.provider_key = 'firecrawl'
              where v.observed_at > security.fc_day_start_v1() - interval '1 hour'),
       l as (select * from o order by observed_at desc limit 1),
       f as (select o.* from o, l where o.period_end = l.period_end order by o.observed_at limit 1)
  select coalesce(greatest(0, (select remaining_units from f) - (select remaining_units from l)), 0)
$f$;

create or replace function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable security definer set search_path = '' as $f$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default)
$f$;

-- Universities whose course-page search has stopped: N searches (older than an hour) in 7 days, since the last Search again, and no
-- correct page read in that time
create or replace function security.fc_search_stopped_v1() returns table(provider_id uuid, searches bigint, since timestamptz)
language sql stable security definer set search_path = '' as $f$
  with w as (select u.provider_id, greatest(now() - interval '7 days', coalesce(max(r.resumed_at), '-infinity'::timestamptz)) since
               from (select distinct x.provider_id from pipeline.coverage_vendor_usage x where x.purpose = 'course_link_search' and x.at > now() - interval '7 days') u
               left join pipeline.firecrawl_search_resumes r on r.provider_id = u.provider_id group by u.provider_id)
  select w.provider_id, count(*) searches, w.since
    from w join pipeline.coverage_vendor_usage x on x.provider_id = w.provider_id and x.purpose = 'course_link_search' and x.at > w.since and x.at < now() - interval '1 hour'
   where not exists (select 1 from pipeline.coverage_course_pages pg where pg.provider_id = w.provider_id and pg.read_at > w.since and pg.status = 'bound' and pg.read_status = 'read')
   group by w.provider_id, w.since
  having count(*) >= security.fc_setting_num_v1('search_stop_after', 30)
$f$;

-- Today's budget by purpose group
create or replace function security.fc_budget_status_v1() returns jsonb language sql stable security definer set search_path = '' as $f$
  with g(grp, label, sort) as (values ('course_search', 'Finding course pages', 1), ('reads', 'Reading pages', 2), ('scholarships', 'Scholarships', 3), ('central', 'Central pages', 4), ('other', 'Other', 5)),
       u as (select security.fc_purpose_group_v1(x.purpose) grp, sum(x.units) used from pipeline.coverage_vendor_usage x where x.at >= security.fc_day_start_v1() group by 1),
       r as (select f.grp, sum(f.n) n from pipeline.firecrawl_budget_refusals f where f.day = (now() at time zone 'Australia/Melbourne')::date group by 1)
  select jsonb_build_object(
    'on', coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false),
    'day_start', security.fc_day_start_v1(), 'total', security.fc_setting_num_v1('daily_budget_total', 15000), 'billed_today', security.fc_billed_today_v1(),
    'used_today', (select coalesce(sum(used), 0) from u),
    'groups', (select jsonb_agg(jsonb_build_object('group', g.grp, 'label', g.label, 'share', security.fc_setting_num_v1('daily_share_' || g.grp, 0),
                                                   'used', coalesce(u.used, 0), 'refused', coalesce(r.n, 0)) order by g.sort)
                 from g left join u on u.grp = g.grp left join r on r.grp = g.grp))
$f$;

create or replace function security.fc_budget_left_v1(p_purpose text) returns numeric language plpgsql stable security definer set search_path = '' as $f$
declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_used numeric;
begin
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then return 1000000; end if;
  if security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then return 0; end if;
  select coalesce(sum(x.units), 0) into v_used from pipeline.coverage_vendor_usage x where x.at >= security.fc_day_start_v1() and security.fc_purpose_group_v1(x.purpose) = v_grp;
  return greatest(0, security.fc_setting_num_v1('daily_share_' || v_grp, 0) - v_used);
end $f$;

-- Every Firecrawl spend of the worker: checks the day's share and total and the per-university caps, then records the use.
create or replace function public.svc_fc_spend(p_units numeric, p_purpose text, p_provider_id uuid, p_url text) returns boolean
language plpgsql security definer set search_path = '' as $f$
declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then
    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    if security.fc_budget_left_v1(p_purpose) < p_units then
      v_why := case when security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then 'day_total' else 'share' end;
    elsif p_provider_id is not null and v_grp = 'scholarships'
          and (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > now() - interval '30 days')
              + p_units > security.fc_setting_num_v1('scholarship_cap_per_uni', 150) then
      v_why := 'university_cap';
    elsif p_provider_id is not null and v_grp = 'central'
          and exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and security.fc_purpose_group_v1(x.purpose) = 'central'
                         and x.at > now() - make_interval(days => security.fc_setting_num_v1('central_refresh_days', 30)::int) and x.at < now() - interval '6 hours') then
      v_why := 'not_due';
    elsif p_provider_id is not null and v_grp = 'course_search' and exists (select 1 from security.fc_search_stopped_v1() s where s.provider_id = p_provider_id) then
      v_why := 'search_stopped';
    end if;
    if v_why is not null then
      insert into pipeline.firecrawl_budget_refusals(day, grp, reason, n, last_at) values ((now() at time zone 'Australia/Melbourne')::date, v_grp, v_why, 1, now())
      on conflict (day, grp, reason) do update set n = pipeline.firecrawl_budget_refusals.n + 1, last_at = now();
      return false;
    end if;
  end if;
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500) from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return true;
end $f$;
revoke all on function public.svc_fc_spend(numeric, text, uuid, text) from public, anon, authenticated;
grant execute on function public.svc_fc_spend(numeric, text, uuid, text) to service_role;

create or replace function public.svc_fc_budget_left(p_purpose text) returns numeric language plpgsql stable security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.fc_budget_left_v1(p_purpose);
end $f$;
revoke all on function public.svc_fc_budget_left(text) from public, anon, authenticated;
grant execute on function public.svc_fc_budget_left(text) to service_role;

-- Credits by university: what Firecrawl was used for and what it produced (correct and wrong course pages)
create or replace function security.firecrawl_credits_report_v1(p_hours int default 24) returns jsonb language sql stable security definer set search_path = '' as $f$
  with since as (select now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720))) t),
  u as (select x.provider_id, sum(x.units) units,
               sum(x.units) filter (where security.fc_purpose_group_v1(x.purpose) = 'course_search') course_search,
               sum(x.units) filter (where security.fc_purpose_group_v1(x.purpose) = 'reads') reads,
               sum(x.units) filter (where security.fc_purpose_group_v1(x.purpose) = 'scholarships') scholarships,
               sum(x.units) filter (where security.fc_purpose_group_v1(x.purpose) = 'central') central,
               sum(x.units) filter (where security.fc_purpose_group_v1(x.purpose) = 'other') other
          from pipeline.coverage_vendor_usage x, since where x.at > since.t group by 1),
  pg as (select p.provider_id,
                count(*) filter (where p.fetched_via = 'firecrawl' and p.status = 'bound' and p.read_status = 'read') fc_ok,
                count(*) filter (where p.fetched_via = 'firecrawl' and not (p.status = 'bound' and p.read_status = 'read')) fc_wrong,
                count(*) filter (where p.fetched_via is distinct from 'firecrawl' and p.status = 'bound' and p.read_status = 'read') direct_ok
           from pipeline.coverage_course_pages p, since where p.read_at > since.t group by 1),
  st as (select * from security.fc_search_stopped_v1()),
  rows as (select coalesce(u.provider_id, pg.provider_id, st.provider_id) provider_id, coalesce(u.units, 0) units, coalesce(u.course_search, 0) course_search, coalesce(u.reads, 0) reads,
                  coalesce(u.scholarships, 0) scholarships, coalesce(u.central, 0) central, coalesce(u.other, 0) other,
                  coalesce(pg.fc_ok, 0) fc_ok, coalesce(pg.fc_wrong, 0) fc_wrong, coalesce(pg.direct_ok, 0) direct_ok, st.provider_id is not null stopped, st.searches stopped_searches
             from u full join pg on pg.provider_id = u.provider_id full join st on st.provider_id = coalesce(u.provider_id, pg.provider_id)
            where coalesce(u.provider_id, pg.provider_id, st.provider_id) is not null),
  rated as (select r.*, r.fc_ok + r.direct_ok correct,
                   case when r.course_search + r.reads > 0 and r.fc_ok + r.direct_ok > 0 then round((r.course_search + r.reads) / (r.fc_ok + r.direct_ok)::numeric, 1) end per_correct,
                   case when r.stopped then 'search_stopped'
                        when r.course_search + r.reads >= 100 and r.fc_ok + r.direct_ok = 0 then 'no_pages'
                        when r.fc_wrong >= 20 and r.fc_wrong > r.fc_ok then 'mostly_wrong'
                        when r.scholarships >= 300 then 'scholarships_high' end flag
              from rows r)
  select jsonb_build_object('generated_at', now(), 'hours', greatest(1, least(coalesce(p_hours, 24), 720)), 'budget', security.fc_budget_status_v1(),
    'totals', (select jsonb_build_object('units', coalesce(sum(units), 0), 'course_search', coalesce(sum(course_search), 0), 'reads', coalesce(sum(reads), 0),
                       'scholarships', coalesce(sum(scholarships), 0), 'central', coalesce(sum(central), 0), 'other', coalesce(sum(other), 0),
                       'fc_ok', coalesce(sum(fc_ok), 0), 'fc_wrong', coalesce(sum(fc_wrong), 0), 'direct_ok', coalesce(sum(direct_ok), 0),
                       'universities', count(*) filter (where units > 0), 'flagged', count(*) filter (where flag is not null), 'stopped', count(*) filter (where stopped)) from rated),
    'universities', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'name', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(z.provider_id),
                        'units', z.units, 'course_search', z.course_search, 'reads', z.reads, 'scholarships', z.scholarships, 'central', z.central, 'other', z.other,
                        'fc_ok', z.fc_ok, 'fc_wrong', z.fc_wrong, 'direct_ok', z.direct_ok, 'correct', z.correct, 'per_correct', z.per_correct,
                        'flag', z.flag, 'stopped', z.stopped, 'stopped_searches', z.stopped_searches) order by z.units desc, z.correct desc), '[]'::jsonb)
                       from (select * from rated where units > 0 or stopped order by units desc limit 150) z left join catalogue.providers pr on pr.id = z.provider_id))
$f$;

create or replace function public.admin_firecrawl_credits(p_hours int default 24) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return security.firecrawl_credits_report_v1(p_hours) || jsonb_build_object('can_manage', v_rank >= 6);
end $f$;
revoke all on function public.admin_firecrawl_credits(int) from public, anon;
grant execute on function public.admin_firecrawl_credits(int) to authenticated;

create or replace function public.admin_firecrawl_search_resume(p_provider_id uuid, p_reason text) returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 4 then raise exception 'a reason is required'; end if;
  insert into pipeline.firecrawl_search_resumes(provider_id, reason, set_by) values (p_provider_id, trim(p_reason), auth.uid());
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('firecrawl', 'search_resume', p_provider_id::text, jsonb_build_object('reason', trim(p_reason), 'change', 'CF-247 v2.15.262'), auth.uid());
  return jsonb_build_object('ok', true);
end $f$;
revoke all on function public.admin_firecrawl_search_resume(uuid, text) from public, anon;
grant execute on function public.admin_firecrawl_search_resume(uuid, text) to authenticated;

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

do $post$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "6867d7ed9ce10e937353f3804d9155e8", "security.platform_notices_v1()": "67bb25dadb4f6af897d261496b2b752a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.262 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $chk$ begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and section = 'Daily budget') <> 10 then raise exception 'v2.15.262 post-check: daily budget settings missing'; end if;
  if (security.fc_budget_status_v1()->>'total')::numeric <> 15000 then raise exception 'v2.15.262 post-check: total is not 15000'; end if;
  if jsonb_typeof(security.firecrawl_credits_report_v1(24)->'universities') <> 'array' then raise exception 'v2.15.262 post-check: report'; end if;
  if jsonb_typeof(security.platform_notices_v1()) <> 'array' then raise exception 'v2.15.262 post-check: notices'; end if;
  if security.fc_budget_left_v1('scrape') is null or public.svc_fc_budget_left('sch_map') is null then raise exception 'v2.15.262 post-check: budget left'; end if;
  perform count(*) from security.fc_search_stopped_v1();
end $chk$;
