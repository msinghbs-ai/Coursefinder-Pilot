-- CF-247 s1271 (S2-Build; Atlas brief 26 Nov 2026 18:18 AEDT, from the S2-AER gap audit, admin #1186): a course with no primary campus
-- whose campuses are all in one city shows that city on the portal's cards. Version above main's 20261129150000 and the open
-- 20261129160000 (s1261, #1675).
-- The audit counted 34,362 published-provider courses: 4,279 with a primary campus, 15,469 more with no primary campus but every campus in
-- one city, 8,509 with campuses in several cities, 5,377 with no campus link.
-- portal.course_place_v1(course) decides one place, deterministically, from the course's active campuses:
--   primary_campus  the course's primary campuses (course_campuses.is_primary) name one city and state;
--   sole_city       otherwise, every campus has a city and they are all one (city, state);
--   one_state       campuses in several cities of one state: the state, no city;
--   several_cities  campuses in several cities and states: no city and no state (no tie-break, no guess; design v1.12 C.3);
--   provider        the course has no campus link: the provider's own city and state, as before.
-- The search cards (catalogue.portal_course_cards_v1, read by public.portal_course_search_v1), the Entry Requirements rows
-- (portal.aer_list_v1) and saved courses (public.portal_saved_list_v1) read it, each with 'place_basis'. A search that names a city or
-- postcode still shows the matching campus first. Before, the cards took the alphabetically first campus of a multi-city course (a guess) and
-- saved courses showed the provider's city.
-- The three replaced functions are replaced only if their bodies are the s1222 texts (md5 checked). Not the consumer API (G3 checked).
-- G1: no job. G2: no setting. Locks untouched. Nothing dropped. US$0.
-- Replaces: the first-campus city in catalogue.portal_course_cards_v1 and portal.aer_list_v1, and the provider city in
-- public.portal_saved_list_v1 (s1222 bodies).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces

create temp table s1271_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_cards_v1(uuid[], text[], numeric, jsonb)'::regprocedure) <> '7cac99bac0e19a06f34f2357dda727fb'
     or (select md5(prosrc) from pg_proc where oid = 'portal.aer_list_v1(jsonb)'::regprocedure) <> '60b50705e19a4e16a8ee435ebfdeecbf'
     or (select md5(prosrc) from pg_proc where oid = 'public.portal_saved_list_v1()'::regprocedure) <> '3fd363d0003f148b8040ddd6bf6dd112' then
    raise exception 'pre-check: a portal read is not the s1222 body this change was written against';
  end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

-- one place for a course, from its active campuses; no tie-break between cities
create or replace function portal.course_place_v1(p_course_id uuid)
returns table (city text, state_code text, basis text) language sql stable security definer set search_path = '' as $function$
  with cam as (
    select nullif(btrim(ca.city), '') city, s.code state_code, coalesce(cc.is_primary, false) prim  -- the course's own primary flag, not the provider's main campus
      from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id
      left join ref.subdivisions s on s.id = ca.subdivision_id
     where cc.course_id = p_course_id and coalesce(ca.status, 'active') = 'active'),
  pr as (select min(city) city, min(state_code) state_code, count(distinct (lower(city), coalesce(state_code, ''))) n
           from cam where prim and city is not null),
  al as (select count(*) n, count(city) n_city, count(distinct (lower(city), coalesce(state_code, ''))) filter (where city is not null) n_place,
                count(state_code) n_state_rows, count(distinct state_code) n_state, min(city) city, min(state_code) state_code from cam)
  select case when pr.n = 1 then pr.city when al.n > 0 and al.n_city = al.n and al.n_place = 1 then al.city end,
         case when pr.n = 1 then pr.state_code when al.n > 0 and al.n_city = al.n and al.n_place = 1 then al.state_code
              when al.n > 0 and al.n_state_rows = al.n and al.n_state = 1 then al.state_code end,
         case when pr.n = 1 then 'primary_campus' when al.n > 0 and al.n_city = al.n and al.n_place = 1 then 'sole_city'
              when al.n = 0 then 'provider' when al.n_state_rows = al.n and al.n_state = 1 then 'one_state' else 'several_cities' end
    from pr, al
$function$;
comment on function portal.course_place_v1(uuid) is 'CF-247 s1271: one place for a course from its active campuses: primary campus, else the one (city, state) every campus shares, else the one state, else none; provider when the course has no campus. Never a tie-break.';
revoke all on function portal.course_place_v1(uuid) from public, anon, authenticated;

create or replace function catalogue.portal_course_cards_v1(p_ids uuid[], p_cities text[], p_simmin numeric, p_near jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'course_id', c.id, 'title', coalesce(nullif(c.display_title, ''), c.canonical_title),
      'provider_id', p.id, 'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name),
      'level', sl.name, 'country_code', d.country_code,
      'state_code', case when cam.city is not null then cam.state_code when pl.basis = 'provider' then ps.code else pl.state_code end,
      'city', case when cam.city is not null then cam.city when pl.basis = 'provider' then p.primary_city else pl.city end,
      'place_basis', case when cam.city is not null then 'searched_campus' else pl.basis end,  -- s1271: why this place is shown
      'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
      'fee', portal.primary_fee_v1(d.provider_tuition_options, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency),  -- s1222: one annual fee, the current year's first
      'regulator', portal.regulator_code_v1(c.id),  -- s1222
      'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date) from catalogue.course_intakes i
                       where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= (now() at time zone 'Australia/Melbourne')::date)  -- fixed: Melbourne day
                       order by i.start_date nulls last, i.id limit 1),
      'topic_match', coalesce(rk.fts > 0, false) or coalesce(rk.sim >= p_simmin, false),
      'topic_score', case when rk.sim is not null then round(rk.sim::numeric, 3) end,
      'why', to_jsonb(array_remove(array[
               case when rk.sim >= p_simmin then 'Topic match by meaning' end,
               case when rk.fts > 0 then 'Topic words in the course text' end,
               case when cam.city is not null and cardinality(p_cities) > 0 then 'Campus in ' || cam.city end], null)),
      'course_url', coalesce(d.official_course_url, c.course_url),
      'saved', exists (select 1 from portal.saved_courses sc where sc.course_id = c.id and sc.user_id = auth.uid()))
    order by x.ord), '[]'::jsonb)
  from unnest(p_ids) with ordinality x(id, ord)
  join catalogue.courses c on c.id = x.id
  join catalogue.providers p on p.id = c.provider_id
  left join search.course_documents d on d.course_id = c.id
  left join ref.study_levels sl on sl.id = c.study_level_id
  left join ref.subdivisions ps on ps.id = p.subdivision_id
  -- s1271: a campus in the place the counsellor searched for is shown first (the course is taught there); otherwise portal.course_place_v1
  left join lateral (select nullif(btrim(ca.city), '') city, s.code state_code from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id left join ref.subdivisions s on s.id = ca.subdivision_id
                      where cc.course_id = c.id and coalesce(ca.status, 'active') = 'active' and nullif(btrim(ca.city), '') is not null
                        and (lower(trim(ca.city)) = any(p_cities) or ca.postcode = any(array(select jsonb_array_elements_text(coalesce(p_near->'postcodes', '[]'::jsonb)))))
                      order by cc.is_primary desc nulls last, lower(btrim(ca.city)), s.code limit 1) cam on true  -- fixed: one matching campus names the searched place
  left join lateral portal.course_place_v1(c.id) pl on true
  left join pg_temp.portal_search_rank rk on rk.course_id = c.id);
end $function$;

create or replace function portal.aer_list_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_size integer := least(greatest(coalesce(security.portal_setting_v1('aer_page_size'), 20), 10), 100);  -- fixed: the setting's own range
        v_page integer := greatest(coalesce(case when jsonb_typeof(p_args->'page') = 'number' then (p_args->>'page')::numeric::int end, 1), 1);
        v_q text := nullif(btrim(regexp_replace(coalesce(p_args->>'q', ''), '\s+', ' ', 'g')), '');
        v_country text := case when upper(btrim(coalesce(p_args->>'country', ''))) ~ '^[A-Z]{2}$' then upper(btrim(p_args->>'country')) end;
        v_src text := case when upper(btrim(coalesce(p_args->>'source_country', ''))) ~ '^[A-Z]{2}$' then upper(btrim(p_args->>'source_country')) end;
        v_level text := nullif(btrim(lower(coalesce(p_args->>'level', ''))), '');
        v_provider uuid := case when btrim(coalesce(p_args->>'provider_id', '')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then btrim(p_args->>'provider_id')::uuid end;
        v_has text := case when lower(coalesce(p_args->>'has', '')) in ('academic', 'english', 'both') then lower(p_args->>'has') else 'any' end;
        v_scope text := security.portal_search_text_v1('visibility_scope', 'active');
        v_like text; v_total integer; v_items jsonb; v_counts jsonb;
begin
  if char_length(coalesce(v_q, '')) > 200 then v_q := left(v_q, 200); end if;  -- fixed: a search phrase is short
  v_like := case when v_q is not null then security.portal_like_v1(v_q) end;
  create temp table if not exists portal_aer_set (course_id uuid primary key, ac boolean, en boolean, prov text, title text) on commit drop;
  truncate pg_temp.portal_aer_set;
  insert into pg_temp.portal_aer_set
  select x.course_id, x.ac, x.en, x.prov, x.title from (
    select d.course_id, d.provider_name prov, d.course_title title,
           exists (select 1 from catalogue.course_entry_requirements e left join ref.countries co on co.id = e.country_id
                    where e.course_id = d.course_id and e.status = 'active' and (v_src is null or co.iso_alpha2 = v_src or e.country_id is null)) ac,  -- a requirement naming no country applies to every applicant
           exists (select 1 from catalogue.course_english_requirements g where g.course_id = d.course_id and g.status = 'active') en
      from search.course_documents d join catalogue.courses c on c.id = d.course_id
     where c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
       and (v_country is null or d.country_code = v_country)
       and (v_level is null or d.study_level_code = v_level or d.study_level_code like v_level || '\_%')
       and (v_provider is null or d.provider_id = v_provider)
       and (v_like is null or d.course_title ilike v_like or d.provider_name ilike v_like)) x
   where case v_has when 'academic' then x.ac when 'english' then x.en when 'both' then x.ac and x.en
                    else x.ac or x.en end;
  select count(*), jsonb_build_object('academic', count(*) filter (where ac), 'english', count(*) filter (where en), 'both', count(*) filter (where ac and en))
    into v_total, v_counts from pg_temp.portal_aer_set;
  select coalesce(jsonb_agg(jsonb_build_object(
           'course_id', c.id, 'title', coalesce(nullif(c.display_title, ''), c.canonical_title), 'provider_id', d.provider_id, 'provider_name', d.provider_name,
           'country_code', d.country_code, 'level_code', d.study_level_code, 'level_name', sl.name, 'official_url', coalesce(d.official_course_url, c.course_url),
           'city', case when pl.basis = 'provider' then p.primary_city else pl.city end,  -- s1271: primary campus, else the one city every campus shares, else none
           'state_code', case when pl.basis = 'provider' then ps.code else pl.state_code end, 'place_basis', pl.basis,
           'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
           'annual_tuition_fee', portal.primary_fee_v1(d.provider_tuition_options, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency),  -- s1222: one annual fee, the current year's first
           'regulator', portal.regulator_code_v1(c.id),
           'entry_requirements', portal.course_entry_json_v1(c.id), 'english_requirements', portal.course_english_json_v1(c.id))
         order by s.prov, s.title, s.course_id), '[]'::jsonb)
    into v_items
    from (select * from pg_temp.portal_aer_set order by prov, title, course_id limit v_size offset (v_page - 1) * v_size) s
    join catalogue.courses c on c.id = s.course_id join search.course_documents d on d.course_id = s.course_id
    left join ref.study_levels sl on sl.id = c.study_level_id
    join catalogue.providers p on p.id = c.provider_id left join ref.subdivisions ps on ps.id = p.subdivision_id
    left join lateral portal.course_place_v1(c.id) pl on true;
  return jsonb_build_object('items', v_items, 'total', v_total, 'page', v_page, 'page_size', v_size, 'facets', jsonb_build_object('counts', v_counts),
    'filters', jsonb_build_object('q', v_q, 'country', v_country, 'source_country', v_src, 'level', v_level, 'provider_id', v_provider, 'has', v_has));
end $function$;

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
        'state_code', case when pl.basis = 'provider' then sd.code else pl.state_code end,  -- s1271: the course's place, the provider's only when the course has no campus
        'state_name', case when pl.basis = 'provider' then sd.name else ps2.name end,
        'city', case when pl.basis = 'provider' then p.primary_city else pl.city end, 'place_basis', pl.basis,
        'fee', security.admin_course_fee_summary(c.id) -> 'fee_used',
        'primary_fee', portal.primary_fee_v1(dd.provider_tuition_options, dd.provider_annual_tuition_amount, dd.provider_annual_tuition_currency),  -- s1222
        'regulator', portal.regulator_code_v1(c.id),
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
      left join search.course_documents dd on dd.course_id = c.id
      left join lateral portal.course_place_v1(c.id) pl on true
      left join ref.subdivisions ps2 on ps2.code = pl.state_code
     where sc.user_id = auth.uid()), '[]'::jsonb));
end $function$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); s uuid; m uuid; x jsonb; r record;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1271_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1271_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'portal.course_place_v1(uuid)', 'execute') or has_function_privilege('authenticated', 'portal.course_place_v1(uuid)', 'execute') then
    raise exception 'post-check: portal.course_place_v1 must not be callable from outside';
  end if;
  create temp table if not exists portal_search_rank (course_id uuid primary key, pos integer, fts real, sim real) on commit drop;  -- the cards read the search's rank table
  -- a course with no primary campus and every campus in one city: the card names it
  select d.course_id into s from search.course_documents d
   where (select basis from portal.course_place_v1(d.course_id)) = 'sole_city'
     and exists (select 1 from catalogue.course_campuses cc where cc.course_id = d.course_id group by cc.course_id having count(*) > 1)
   order by d.course_id limit 1;
  if s is null then raise exception 'post-check: no sole-city course with two or more campuses found'; end if;
  x := catalogue.portal_course_cards_v1(array[s], '{}'::text[], 1, '{}'::jsonb) -> 0;
  select * into r from portal.course_place_v1(s);
  if x->>'city' is distinct from r.city or x->>'place_basis' <> 'sole_city' or x->>'city' is null then
    raise exception 'post-check: a sole-city card does not name its city: % / %', x->>'city', r.city;
  end if;
  -- a course with campuses in several cities and no primary: no city on the card
  select d.course_id into m from search.course_documents d
   where (select basis from portal.course_place_v1(d.course_id)) in ('several_cities', 'one_state') order by d.course_id limit 1;
  if m is not null then
    x := catalogue.portal_course_cards_v1(array[m], '{}'::text[], 1, '{}'::jsonb) -> 0;
    if x->>'city' is not null then raise exception 'post-check: a multi-city course was given a city: %', x->>'city'; end if;
  end if;
end $post$;
