-- CF-247 s1143 (S1-API-Frontend-Delivery; Platform Admin brief 25 Nov 2026 12:47 and 14:34): the StudySearch Portal's data layer for Release 1.
-- Adds, beside everything that exists (G3: nothing the website, Zoho or the Admin app reads is touched):
--   * schema portal and portal.saved_courses (one row per person and course; the person's own shortlist);
--   * toolset "portal" and its limits on Settings (G2): page sizes, the saved and compare limits, how many recent searches show;
--   * public.portal_settings_v1(), portal_lookups_v1(), portal_providers_v1(), portal_scholarships_v1(), portal_saved_list_v1(), portal_saved_set_v1(),
--     all read-through functions the portal calls with the person's own sign-in. Viewer (rank 1) and above read; Counsellor (rank 2) and above save.
-- Publish rules are the ones the website API v2 already uses, so the portal never shows what the website would not: providers and scholarships are
-- active and published, and not in the Layer 4 blocked views. Courses on the shortlist are shown whatever their publish state, because the
-- Platform Admin decided on 25 Nov 2026 12:26 that Release 1 search covers every active course (portal_search.visibility_scope, S1-Build).
-- Study Square route (pipeline.provider_representation) is shown as recorded; a provider with no row reads "not recorded", never a guess.
-- Not in this change: catalogue.portal_course_search_v1 (plain-English course search, S1-Build lane); the portal's Courses screen waits for it.
-- G1: no job. G2: every number a person can change is a setting row below. G3: no function, table or column the consumer API reads is changed.
-- Nothing dropped or deleted.
-- Replaces: nothing (new functions, one new table, one new toolset).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1143_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1143_cron on commit drop as select count(*) n from cron.job where active;

-- 1. The person's own shortlist. Reached only through the security definer functions below; nobody reads the table directly.
create schema if not exists portal;
create table if not exists portal.saved_courses (
  user_id   uuid        not null references auth.users (id) on delete cascade,
  course_id uuid        not null references catalogue.courses (id) on delete cascade,
  saved_at  timestamptz not null default now(),
  primary key (user_id, course_id)
);
comment on table portal.saved_courses is 'StudySearch Portal (CF-247 s1143): the courses a Counsellor has saved to compare and send. One row per person and course. Read and written only through public.portal_saved_list_v1 and public.portal_saved_set_v1.';
create index if not exists saved_courses_user_saved_idx on portal.saved_courses (user_id, saved_at desc);
alter table portal.saved_courses enable row level security;
revoke all on schema portal from public, anon, authenticated;
revoke all on portal.saved_courses from public, anon, authenticated;

-- 2. Toolset and limits (G2). They show on Settings › Toolsets & limits, with a label, a range, a unit and a used_by line.
insert into pipeline.platform_toolsets (key, label, kind, layers, help, sort, reason)
values ('portal', 'StudySearch Portal (list sizes and limits)', 'platform', array[0],
        'How many providers, scholarships and recent searches the Counsellor and Viewer portal shows at once, and how many courses a person can save and compare. The portal reads these each time it opens.',
        60, 'CF-247 s1143: Platform Admin brief 25 Nov 2026 (no operational value written into code)')
on conflict (key) do nothing;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('portal', 'providers_page_size',     'Universities & Providers: providers per page', 'How many provider cards the Universities & Providers screen shows before "Show more".',
  'number', '24'::jsonb, 6, 60, 'providers', 6010, 'Portal', 'public.portal_providers_v1', 'CF-247 s1143: Platform Admin brief 25 Nov 2026'),
 ('portal', 'scholarships_page_size',  'Scholarships: scholarships per page', 'How many scholarship cards the Scholarships screen shows before "Show more".',
  'number', '20'::jsonb, 5, 50, 'scholarships', 6020, 'Portal', 'public.portal_scholarships_v1', 'CF-247 s1143: Platform Admin brief 25 Nov 2026'),
 ('portal', 'saved_courses_max',       'Saved courses: most a person can save', 'The most courses one Counsellor can keep on their shortlist.',
  'number', '50'::jsonb, 10, 200, 'courses', 6030, 'Portal', 'public.portal_saved_set_v1', 'CF-247 s1143: Platform Admin brief 25 Nov 2026'),
 ('portal', 'compare_courses_max',     'Saved courses: most compared side by side', 'The most saved courses the comparison table shows at once (the design shows four).',
  'number', '4'::jsonb, 2, 6, 'courses', 6040, 'Portal', 'portal app (Saved courses)', 'CF-247 s1143: Platform Admin brief 25 Nov 2026'),
 ('portal', 'recent_searches_shown',   'Dashboard: recent searches shown', 'How many of a person''s last plain-English searches the Dashboard lists.',
  'number', '5'::jsonb, 1, 10, 'searches', 6050, 'Portal', 'portal app (Dashboard)', 'CF-247 s1143: Platform Admin brief 25 Nov 2026')
on conflict do nothing;

-- 3. Helpers. Both read only; the rank comes from the person's own role (security.current_role_rank), never from the screen.
create or replace function security.portal_rank_v1(p_min integer)
returns smallint language plpgsql stable security definer set search_path = '' as $function$
declare v_rank smallint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  if v_rank < p_min then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return v_rank;
end $function$;

create or replace function security.portal_setting_v1(p_key text)
returns integer language sql stable security definer set search_path = '' as $function$
  select (s.value #>> '{}')::integer from pipeline.platform_toolset_settings s where s.toolset_key = 'portal' and s.key = p_key
$function$;

-- 4. Settings for the portal screens.
create or replace function public.portal_settings_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return coalesce((select jsonb_object_agg(s.key, s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'portal'), '{}'::jsonb);
end $function$;

-- 5. Lookups read from the live tables (s930): destination countries that have published providers, and every student market.
create or replace function public.portal_lookups_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return jsonb_build_object(
    'destinations', coalesce((select jsonb_agg(jsonb_build_object('code', d.code, 'name', d.name, 'providers', d.n) order by d.name)
       from (select c.iso_alpha2 as code, c.name, count(*) n
               from catalogue.providers p join ref.countries c on c.id = p.country_id
              where p.lifecycle_status = 'active' and p.publication_status = 'published'
                and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = p.id)
              group by c.iso_alpha2, c.name) d), '[]'::jsonb),
    'markets', coalesce((select jsonb_agg(jsonb_build_object('code', c.iso_alpha2, 'name', c.name) order by c.name) from ref.countries c where c.iso_alpha2 is not null), '[]'::jsonb));
end $function$;

-- 6. Search text for ilike: a typed % or _ is a letter, not a wildcard.
create or replace function security.portal_like_v1(p_text text)
returns text language sql immutable set search_path = '' as $function$
  select '%' || replace(replace(replace(btrim(p_text), '\', '\\'), '%', '\%'), '_', '\_') || '%'
$function$;

-- 7. Universities & Providers: published providers only, paged on the server, route shown for the chosen student market.
create or replace function public.portal_providers_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_size integer := security.portal_setting_v1('providers_page_size');
  v_page integer := greatest(coalesce(nullif(p_args->>'page', '')::integer, 1), 1);  -- fixed: pages count from 1
  v_q text := nullif(btrim(coalesce(p_args->>'q', '')), '');
  v_countries text[] := array(select upper(x) from jsonb_array_elements_text(coalesce(p_args->'countries', '[]'::jsonb)) x);
  v_types text[] := array(select x from jsonb_array_elements_text(coalesce(p_args->'types', '[]'::jsonb)) x);
  v_states text[] := array(select x from jsonb_array_elements_text(coalesce(p_args->'states', '[]'::jsonb)) x);
  v_routes text[] := array(select x from jsonb_array_elements_text(coalesce(p_args->'routes', '[]'::jsonb)) x);
  v_market text := nullif(upper(btrim(coalesce(p_args->>'market', ''))), '');
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
  v_like text;
  v_total integer; v_items jsonb; v_fac jsonb;
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  if v_size is null then raise exception 'setting portal.providers_page_size is missing' using errcode = '22023'; end if;
  v_like := case when v_q is null then null else security.portal_like_v1(v_q) end;
  with base as (
    select p.id, coalesce(nullif(p.display_name, ''), p.canonical_name) as name, p.short_name,
           pt.code as type_code, pt.name as type_name, c.iso_alpha2 as country_code, sd.code as state_code, sd.name as state_name,
           p.primary_city as city, p.website, p.logo_url,
           r.representation_status as rep_status, r.restriction_mode as rep_mode, r.restriction_markets as rep_markets
      from catalogue.providers p
      left join ref.provider_types pt on pt.id = p.provider_type_id
      left join ref.countries c on c.id = p.country_id
      left join ref.subdivisions sd on sd.id = p.subdivision_id
      left join lateral (select x.* from pipeline.provider_representation x
                          where x.provider_id = p.id and (x.effective_from is null or x.effective_from <= v_today) and (x.effective_to is null or x.effective_to >= v_today)
                          order by x.effective_from desc nulls last limit 1) r on true
     where p.lifecycle_status = 'active' and p.publication_status = 'published'
       and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = p.id)
  ), routed as (
    select b.*, case when b.rep_status is null then 'not_recorded'
                     when v_market is not null and b.rep_mode = 'include' and not (v_market = any (b.rep_markets)) then 'not_represented'
                     when v_market is not null and b.rep_mode = 'exclude' and v_market = any (b.rep_markets) then 'not_represented'
                     else b.rep_status end as route
      from base b
  ), by_country as (
    select * from routed where cardinality(v_countries) = 0 or country_code = any (v_countries)
  ), filtered as (
    select * from by_country
     where (v_like is null or name ilike v_like or short_name ilike v_like)
       and (cardinality(v_types) = 0 or type_code = any (v_types))
       and (cardinality(v_states) = 0 or state_code = any (v_states))
       and (cardinality(v_routes) = 0 or route = any (v_routes))
  ), paged as (
    select * from filtered order by lower(name), id limit v_size offset (v_page - 1) * v_size
  )
  select (select count(*) from filtered),
         coalesce((select jsonb_agg(jsonb_build_object(
              'id', g.id, 'name', g.name, 'short_name', g.short_name, 'type_code', g.type_code, 'type_name', g.type_name,
              'country_code', g.country_code, 'state_code', g.state_code, 'state_name', g.state_name, 'city', g.city,
              'website', g.website, 'logo_url', g.logo_url, 'route', g.route, 'route_mode', g.rep_mode,
              'route_markets', case when g.rep_markets is null then null
                               else (select coalesce(jsonb_agg(cc.name order by cc.name), '[]'::jsonb) from ref.countries cc where cc.iso_alpha2 = any (g.rep_markets)) end,
              'course_count', (select count(*) from catalogue.courses k where k.provider_id = g.id and k.lifecycle_status = 'active'))
            order by lower(g.name), g.id) from paged g), '[]'::jsonb),
         jsonb_build_object(
           'types', coalesce((select jsonb_agg(jsonb_build_object('code', t.type_code, 'name', t.type_name, 'count', t.n) order by t.type_name)
                               from (select type_code, type_name, count(*) n from by_country where type_code is not null group by 1, 2) t), '[]'::jsonb),
           'states', coalesce((select jsonb_agg(jsonb_build_object('code', t.state_code, 'name', t.state_name, 'count', t.n) order by t.state_name)
                                from (select state_code, state_name, count(*) n from by_country where state_code is not null group by 1, 2) t), '[]'::jsonb),
           'routes', coalesce((select jsonb_agg(jsonb_build_object('code', t.route, 'count', t.n) order by t.route)
                                from (select route, count(*) n from by_country group by 1) t), '[]'::jsonb))
    into v_total, v_items, v_fac;
  return jsonb_build_object('page', v_page, 'page_size', v_size, 'total', v_total, 'items', v_items, 'facets', v_fac);
end $function$;

-- 8. Scholarships: published only; status is worked out from the stated dates on today's Melbourne date, and a missing date stays "not published".
create or replace function public.portal_scholarships_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_size integer := security.portal_setting_v1('scholarships_page_size');
  v_page integer := greatest(coalesce(nullif(p_args->>'page', '')::integer, 1), 1);  -- fixed: pages count from 1
  v_q text := nullif(btrim(coalesce(p_args->>'q', '')), '');
  v_countries text[] := array(select upper(x) from jsonb_array_elements_text(coalesce(p_args->'countries', '[]'::jsonb)) x);
  v_statuses text[] := array(select x from jsonb_array_elements_text(coalesce(p_args->'statuses', '[]'::jsonb)) x);
  v_intake text := nullif(btrim(coalesce(p_args->>'intake', '')), '');
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
  v_like text;
  v_total integer; v_items jsonb; v_fac jsonb;
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  if v_size is null then raise exception 'setting portal.scholarships_page_size is missing' using errcode = '22023'; end if;
  v_like := case when v_q is null then null else security.portal_like_v1(v_q) end;
  with base as (
    select s.id, s.name, s.provider_id, coalesce(nullif(p.display_name, ''), p.canonical_name) as provider_name, c.iso_alpha2 as country_code,
           s.award_value_text, s.award_value_type, s.award_percentage, s.award_amount, s.award_currency_code, s.award_applies_to_fee_type, s.award_value_is_maximum,
           s.study_start_label, s.application_open_date, s.application_close_date, s.application_open_precision, s.application_close_precision,
           s.application_required, s.source_url,
           case when s.application_open_date is null and s.application_close_date is null then 'dates_not_published'
                when s.application_open_date is not null and s.application_open_date > v_today then 'opens_later'
                when s.application_close_date is not null and s.application_close_date < v_today then 'closed'
                else 'open_now' end as status
      from scholarship.scholarships s
      join catalogue.providers p on p.id = s.provider_id
      left join ref.countries c on c.id = p.country_id
     where s.lifecycle_status = 'active' and s.publication_status = 'published'
       and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id)
       and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = p.id)
  ), by_country as (
    select * from base where cardinality(v_countries) = 0 or country_code = any (v_countries)
  ), filtered as (
    select * from by_country
     where (v_like is null or name ilike v_like or provider_name ilike v_like)
       and (cardinality(v_statuses) = 0 or status = any (v_statuses))
       and (v_intake is null or study_start_label = v_intake)
  ), paged as (
    select * from filtered
     order by case status when 'open_now' then 1 when 'opens_later' then 2 when 'dates_not_published' then 3 else 4 end, lower(name), id
     limit v_size offset (v_page - 1) * v_size
  )
  select (select count(*) from filtered),
         coalesce((select jsonb_agg(to_jsonb(g) - 'provider_id' || jsonb_build_object('provider_id', g.provider_id)
                    order by case g.status when 'open_now' then 1 when 'opens_later' then 2 when 'dates_not_published' then 3 else 4 end, lower(g.name), g.id) from paged g), '[]'::jsonb),
         jsonb_build_object(
           'statuses', coalesce((select jsonb_agg(jsonb_build_object('code', t.status, 'count', t.n) order by t.status) from (select status, count(*) n from by_country group by 1) t), '[]'::jsonb),
           'intakes', coalesce((select jsonb_agg(jsonb_build_object('label', t.study_start_label, 'count', t.n) order by t.study_start_label)
                                 from (select study_start_label, count(*) n from by_country where study_start_label is not null group by 1) t), '[]'::jsonb))
    into v_total, v_items, v_fac;
  return jsonb_build_object('page', v_page, 'page_size', v_size, 'total', v_total, 'items', v_items, 'facets', v_fac);
end $function$;

-- 9. The person's shortlist. Counsellor (rank 2) and above. The fee is the one the Admin app already picks (fee_used); a missing value stays null.
create or replace function public.portal_saved_list_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  return jsonb_build_object(
    'saved_max', security.portal_setting_v1('saved_courses_max'),
    'compare_max', security.portal_setting_v1('compare_courses_max'),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'course_id', c.id, 'saved_at', sc.saved_at,
        'title', coalesce(nullif(c.display_title, ''), c.canonical_title), 'course_code', c.course_code, 'course_url', c.course_url,
        'level', sl.name, 'duration_value', c.duration_value, 'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode,
        'active', c.lifecycle_status = 'active', 'published', c.publication_status = 'published', 'last_verified_at', c.last_verified_at,
        'provider_id', p.id, 'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name), 'country_code', co.iso_alpha2,
        'state_code', sd.code, 'state_name', sd.name, 'city', p.primary_city,
        'fee', security.admin_course_fee_summary(c.id) -> 'fee_used',
        'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date, 'deadline', i.application_deadline, 'status', i.status)
                          from catalogue.course_intakes i
                         where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= v_today)
                         order by i.start_date nulls last, i.id limit 1))
        order by sc.saved_at desc, c.id)
      from portal.saved_courses sc
      join catalogue.courses c on c.id = sc.course_id
      join catalogue.providers p on p.id = c.provider_id
      left join ref.study_levels sl on sl.id = c.study_level_id
      left join ref.countries co on co.id = p.country_id
      left join ref.subdivisions sd on sd.id = p.subdivision_id
     where sc.user_id = auth.uid()), '[]'::jsonb));
end $function$;

create or replace function public.portal_saved_set_v1(p_course_id uuid, p_saved boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_max integer := security.portal_setting_v1('saved_courses_max'); v_n integer;
begin
  perform security.portal_rank_v1(2);  -- fixed: Counsellor and above
  if p_course_id is null then raise exception 'INVALID_INPUT: course id required' using errcode = '22023'; end if;
  if p_saved then
    if not exists (select 1 from catalogue.courses c where c.id = p_course_id and c.lifecycle_status = 'active') then
      raise exception 'INVALID_INPUT: that course is not available' using errcode = '22023';
    end if;
    if not exists (select 1 from portal.saved_courses s where s.user_id = auth.uid() and s.course_id = p_course_id) then
      if (select count(*) from portal.saved_courses s where s.user_id = auth.uid()) >= v_max then
        raise exception 'SAVED_LIMIT: you can save up to % courses; remove one first', v_max using errcode = '22023';
      end if;
      insert into portal.saved_courses (user_id, course_id) values (auth.uid(), p_course_id);
    end if;
  else
    delete from portal.saved_courses s where s.user_id = auth.uid() and s.course_id = p_course_id;
  end if;
  select count(*) into v_n from portal.saved_courses s where s.user_id = auth.uid();
  return jsonb_build_object('course_id', p_course_id, 'saved', p_saved, 'saved_count', v_n);
end $function$;

-- 10. Who may call them: signed-in people only (each function also checks the role rank itself).
revoke all on function public.portal_settings_v1(), public.portal_lookups_v1(), public.portal_providers_v1(jsonb), public.portal_scholarships_v1(jsonb),
                       public.portal_saved_list_v1(), public.portal_saved_set_v1(uuid, boolean) from public, anon;
grant execute on function public.portal_settings_v1(), public.portal_lookups_v1(), public.portal_providers_v1(jsonb), public.portal_scholarships_v1(jsonb),
                          public.portal_saved_list_v1(), public.portal_saved_set_v1(uuid, boolean) to authenticated;
revoke all on function security.portal_rank_v1(integer), security.portal_setting_v1(text), security.portal_like_v1(text) from public, anon, authenticated;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1143_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1143_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'portal') <> 5 then raise exception 'post-check: the portal settings are not all present'; end if;
  if to_regprocedure('public.portal_providers_v1(jsonb)') is null or to_regprocedure('public.portal_scholarships_v1(jsonb)') is null
     or to_regprocedure('public.portal_saved_set_v1(uuid,boolean)') is null then raise exception 'post-check: a portal function is missing'; end if;
end $post$;
