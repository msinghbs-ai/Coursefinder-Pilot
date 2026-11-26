-- CF-247 s1275 (S2-Data-Gaps; Atlas brief 26 Nov 2026 19:51 AEDT, Platform Admin live UAT of the StudySearch Portal): three Portal data-display gaps.
-- Version above the live head 20261129210000 (s1273) and the open 20261129180000 (s1274, #1683) and 20261129190000 (s1261, #1675).
-- Measured live 26 Nov 2026 (rolled-back reads): 34,362 published-provider courses in search; 144 are domestic-only (open_to_international is false)
-- and 4,287 have no international answer (null); 8,509 have campuses in several cities (4,186 in several states, 5,054 in one state, no primary).
-- 1. Domestic-only courses are not shown to international counsellors. catalogue.portal_course_search_v1 (read by public.portal_course_search_v1)
--    and portal.aer_list_v1 (read by public.portal_aer_list_v1) leave out open_to_international = false, in the one step every later step reads
--    (the passing set), so the total, the ranking, the near misses and the relaxation counts agree. A course with no answer (null) stays, and the
--    cards and Entry Requirements rows return open_to_international (true or null) so the Portal can say "Check international availability".
--    A saved course is never removed from a person's saved list, and Course details still say a domestic-only course is not open to
--    international students.
-- 2. Multi-campus location. A course with no primary campus and campuses in several cities no longer leaves LOCATION blank:
--    state_campus              a state is part of the search and exactly one campus city of the course is in it: that city;
--    multiple_campuses_state   a state is part of the search and the course has campuses in several cities of it: "Multiple campuses (VIC)";
--    multiple_campuses         no state in the search: "Multiple campuses" (with the state when every campus is in one state).
--    No primary campus is guessed and no city is picked between campuses (s1271 stands). A typed city or postcode still shows its campus first.
--    portal.place_label_v1(basis, state) is the one wording; the search cards, Entry Requirements rows and saved courses read it.
-- The search function is changed by three anchored edits of its live text (the passing-set join, and the two card calls that now pass the search's
-- state); the Entry Requirements and saved-course functions by anchored edits too; the cards function is replaced in full. Each is applied only if
-- its live body is the one read back (md5) and every anchor is found exactly as many times as expected. Not the consumer API (G3 checked).
-- G1: no job. G2: no setting or value written into code. Locks untouched. Nothing dropped. No AI call. US$0.
-- Replaces: the s1271 bodies of catalogue.portal_course_cards_v1, portal.aer_list_v1 and public.portal_saved_list_v1 (place only for saved), and the
--   s1212 body of catalogue.portal_course_search_v1 (passing set and card calls).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces

create temp table s1275_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_search_v1(jsonb)'::regprocedure) <> 'f91226e37714679a6799ad9451f3eb02'
     or (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_cards_v1(uuid[], text[], numeric, jsonb)'::regprocedure) <> 'cbd8d27478cd43f72526f141a65b8070'
     or (select md5(prosrc) from pg_proc where oid = 'portal.aer_list_v1(jsonb)'::regprocedure) <> '88bae8930ac30704c961714f92e1f15d'
     or (select md5(prosrc) from pg_proc where oid = 'public.portal_saved_list_v1()'::regprocedure) <> 'cd125b53b6a7738ac4c3e1787e52f38c' then
    raise exception 'pre-check: a portal read is not the body this change was written against (s1212 search, s1271 cards, Entry Requirements and saved courses)';
  end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

-- one wording for a course with campuses in several cities and no primary campus
create or replace function portal.place_label_v1(p_basis text, p_state_code text)
returns text language sql immutable set search_path = '' as $function$
  select case p_basis
           when 'several_cities' then 'Multiple campuses'
           when 'one_state' then case when nullif(btrim(p_state_code), '') is not null
                                      then 'Multiple campuses (' || coalesce(nullif(split_part(p_state_code, '-', 2), ''), p_state_code) || ')'
                                      else 'Multiple campuses' end
         end
$function$;
comment on function portal.place_label_v1(text, text) is 'CF-247 s1275: the Portal wording for a course with campuses in several cities and no primary campus: "Multiple campuses", with the state when every campus is in one state. Null for any other place basis.';
revoke all on function portal.place_label_v1(text, text) from public, anon, authenticated;

-- cards: the international answer, and the place for a multi-campus course (the search's state arrives in p_near->'states')
create or replace function catalogue.portal_course_cards_v1(p_ids uuid[], p_cities text[], p_simmin numeric, p_near jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_states text[] := array(select jsonb_array_elements_text(case when jsonb_typeof(p_near->'states') = 'array' then p_near->'states' else '[]'::jsonb end));  -- s1275: the state the search names
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'course_id', c.id, 'title', coalesce(nullif(c.display_title, ''), c.canonical_title),
      'provider_id', p.id, 'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name),
      'level', sl.name, 'country_code', d.country_code,
      'open_to_international', c.open_to_international,  -- s1275: true, or null when the platform does not hold the answer (false is not searched)
      'state_code', case when cam.city is not null then cam.state_code
                         when pl.basis in ('several_cities', 'one_state') and fs.n_place = 1 then fs.state_code
                         when pl.basis = 'provider' then ps.code else pl.state_code end,
      'city', case when cam.city is not null then cam.city
                   when pl.basis in ('several_cities', 'one_state') and fs.n_place = 1 then fs.city
                   when pl.basis = 'provider' then p.primary_city else pl.city end,
      'place_basis', case when cam.city is not null then 'searched_campus'
                          when pl.basis in ('several_cities', 'one_state') and fs.n_place = 1 then 'state_campus'
                          when pl.basis in ('several_cities', 'one_state') and fs.n_place > 1 then 'multiple_campuses_state'
                          when pl.basis in ('several_cities', 'one_state') then 'multiple_campuses'
                          else pl.basis end,  -- s1271, s1275: why this place is shown
      'place_label', case when cam.city is not null then null
                          when pl.basis in ('several_cities', 'one_state') and fs.n_place = 1 then null
                          when pl.basis in ('several_cities', 'one_state') and fs.n_place > 1 then 'Multiple campuses (' || fs.shorts || ')'
                          else portal.place_label_v1(pl.basis, pl.state_code) end,  -- s1275: said when no one city can be named
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
               case when cam.city is not null and cardinality(p_cities) > 0 then 'Campus in ' || cam.city end,
               case when cam.city is null and pl.basis in ('several_cities', 'one_state') and fs.n_place = 1 then 'Campus in ' || fs.city || ' (' || fs.shorts || ')' end], null)),
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
  -- s1275: the course's campus cities inside the state the search names (when the search names none, no row is read)
  left join lateral (select count(distinct (lower(btrim(ca.city)), s.code)) n_place, min(btrim(ca.city)) city, min(s.code) state_code,
                            string_agg(distinct coalesce(nullif(split_part(s.code, '-', 2), ''), s.code), ' / ') shorts
                       from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id join ref.subdivisions s on s.id = ca.subdivision_id
                      where cardinality(v_states) > 0 and cc.course_id = c.id and coalesce(ca.status, 'active') = 'active'
                        and nullif(btrim(ca.city), '') is not null and s.code = any(v_states)) fs on true
  left join pg_temp.portal_search_rank rk on rk.course_id = c.id);
end $function$;

-- the anchored edits of the live texts
create function pg_temp.s1275_patch(p_def text, p_old text, p_new text, p_expect integer) returns text language plpgsql as $p$
begin
  if (length(p_def) - length(replace(p_def, p_old, ''))) <> length(p_old) * p_expect then
    raise exception 'guard: anchor "%" is not present exactly % time(s); rebase and re-verify', left(p_old, 60), p_expect;
  end if;
  return replace(p_def, p_old, p_new);
end $p$;

do $f$
declare v_def text; v_fn regprocedure;
begin
  -- search: domestic-only courses leave the passing set; the card calls carry the search's state
  v_fn := 'catalogue.portal_course_search_v1(jsonb)'::regprocedure;
  v_def := pg_get_functiondef(v_fn);
  v_def := pg_temp.s1275_patch(v_def,
    $a$join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')$a$,
    $b$join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
                     and c.open_to_international is not false  -- s1275: a domestic-only course is not shown (null, not known, stays and is flagged on the card)$b$, 1);
  v_def := pg_temp.s1275_patch(v_def,
    $a$jsonb_build_object('postcodes', to_jsonb(v_city_pcs))$a$,
    $b$jsonb_build_object('postcodes', to_jsonb(v_city_pcs), 'states', to_jsonb(v_states))$b$, 2);
  execute v_def;
  if strpos(pg_get_functiondef(v_fn), 'c.open_to_international is not false') = 0 or strpos(pg_get_functiondef(v_fn), $c$'states', to_jsonb(v_states)$c$) = 0 then
    raise exception 'post-check: the search edit was not applied';
  end if;

  -- Entry Requirements rows: no domestic-only course; the international answer and the place wording on each row
  v_fn := 'portal.aer_list_v1(jsonb)'::regprocedure;
  v_def := pg_get_functiondef(v_fn);
  v_def := pg_temp.s1275_patch(v_def,
    $a$where c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')$a$,
    $b$where c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
       and c.open_to_international is not false  -- s1275: a domestic-only course is not shown$b$, 1);
  v_def := pg_temp.s1275_patch(v_def,
    $a$'country_code', d.country_code, 'level_code', d.study_level_code,$a$,
    $b$'country_code', d.country_code, 'open_to_international', c.open_to_international, 'level_code', d.study_level_code,$b$, 1);
  v_def := pg_temp.s1275_patch(v_def,
    $a$'state_code', case when pl.basis = 'provider' then ps.code else pl.state_code end, 'place_basis', pl.basis,$a$,
    $b$'state_code', case when pl.basis = 'provider' then ps.code else pl.state_code end, 'place_basis', pl.basis, 'place_label', portal.place_label_v1(pl.basis, pl.state_code),$b$, 1);
  execute v_def;
  if strpos(pg_get_functiondef(v_fn), 'portal.place_label_v1') = 0 or strpos(pg_get_functiondef(v_fn), 'c.open_to_international is not false') = 0 then
    raise exception 'post-check: the Entry Requirements edit was not applied';
  end if;

  -- saved courses: the place wording only (a saved course is never taken off a person's list)
  v_fn := 'public.portal_saved_list_v1()'::regprocedure;
  v_def := pg_get_functiondef(v_fn);
  v_def := pg_temp.s1275_patch(v_def,
    $a$'city', case when pl.basis = 'provider' then p.primary_city else pl.city end, 'place_basis', pl.basis,$a$,
    $b$'city', case when pl.basis = 'provider' then p.primary_city else pl.city end, 'place_basis', pl.basis, 'place_label', portal.place_label_v1(pl.basis, pl.state_code),$b$, 1);
  execute v_def;
  if strpos(pg_get_functiondef(v_fn), 'portal.place_label_v1') = 0 then raise exception 'post-check: the saved-course edit was not applied'; end if;
end $f$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); x jsonb; r record; pid uuid; n_expect integer; n_bad integer;
        a_course uuid; a_city text; a_state text; b_course uuid; b_state text; v_scope text := security.portal_search_text_v1('visibility_scope', 'active');
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1275_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1275_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'portal.place_label_v1(text, text)', 'execute') or has_function_privilege('authenticated', 'portal.place_label_v1(text, text)', 'execute') then
    raise exception 'post-check: portal.place_label_v1 must not be callable from outside';
  end if;
  if portal.place_label_v1('several_cities', 'AU-VIC') <> 'Multiple campuses' or portal.place_label_v1('one_state', 'AU-VIC') <> 'Multiple campuses (VIC)'
     or portal.place_label_v1('sole_city', 'AU-VIC') is not null then raise exception 'post-check: the place wording is wrong'; end if;
  create temp table if not exists portal_search_rank (course_id uuid primary key, pos integer, fts real, sim real) on commit drop;  -- the cards read the search's rank table

  -- 1. a provider that has domestic-only courses: the search total and rows leave them out (no topic, so no phrase is sent for embedding)
  select c.provider_id into pid from catalogue.courses c join search.course_documents d on d.course_id = c.id
   where c.open_to_international is false and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
   group by c.provider_id order by count(*) desc, c.provider_id limit 1;
  if pid is not null then
    select count(*) into n_expect from search.course_documents d join catalogue.courses c on c.id = d.course_id
     where d.provider_id = pid and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published') and c.open_to_international is not false;
    x := catalogue.portal_course_search_v1(jsonb_build_object('q', '', 'provider_id', pid));
    if (x->>'total')::int <> n_expect then raise exception 'post-check: the search total % is not the % courses open or not known to international students', x->>'total', n_expect; end if;
    select count(*) into n_bad from jsonb_array_elements(x->'exact') e join catalogue.courses c on c.id = (e->>'course_id')::uuid where c.open_to_international is false;
    if n_bad <> 0 then raise exception 'post-check: % domestic-only course(s) were returned by the search', n_bad; end if;
    if jsonb_array_length(x->'exact') > 0 and not exists (select 1 from jsonb_array_elements(x->'exact') e where e ? 'open_to_international') then
      raise exception 'post-check: the search cards do not return open_to_international';
    end if;
    x := portal.aer_list_v1(jsonb_build_object('provider_id', pid));
    select count(*) into n_bad from jsonb_array_elements(x->'items') e join catalogue.courses c on c.id = (e->>'course_id')::uuid where c.open_to_international is false;
    if n_bad <> 0 then raise exception 'post-check: % domestic-only course(s) were returned by Entry Requirements', n_bad; end if;
  end if;

  -- 2a. a course with no primary campus, campuses in several cities, and exactly one city in one state: a search naming that state shows the city
  with cs as (select cc.course_id, s.code sc, count(distinct lower(btrim(ca.city))) n_city, min(btrim(ca.city)) city
                from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id join ref.subdivisions s on s.id = ca.subdivision_id
               where coalesce(ca.status, 'active') = 'active' and nullif(btrim(ca.city), '') is not null
                 and not exists (select 1 from catalogue.course_campuses p where p.course_id = cc.course_id and coalesce(p.is_primary, false))
               group by 1, 2),
       ct as (select course_id, sum(n_city) total_city, count(*) n_state from cs group by 1)
  select cs.course_id, cs.city, cs.sc into a_course, a_city, a_state from cs join ct on ct.course_id = cs.course_id
   where cs.n_city = 1 and ct.total_city >= 2 and ct.n_state >= 2 order by cs.course_id, cs.sc limit 1;
  if a_course is null then raise exception 'post-check: no multi-campus course with one city in a state found'; end if;
  x := catalogue.portal_course_cards_v1(array[a_course], '{}'::text[], 1, jsonb_build_object('states', jsonb_build_array(a_state))) -> 0;
  if x->>'place_basis' <> 'state_campus' or lower(x->>'city') is distinct from lower(a_city) or x->>'state_code' is distinct from a_state or x->>'place_label' is not null then
    raise exception 'post-check: a state search did not name the course''s one campus city in it: %', x;
  end if;
  -- 2b. the same course with no state in the search: no city, "Multiple campuses"
  x := catalogue.portal_course_cards_v1(array[a_course], '{}'::text[], 1, '{}'::jsonb) -> 0;
  if x->>'city' is not null or x->>'place_basis' not in ('multiple_campuses') or x->>'place_label' is distinct from portal.place_label_v1((select basis from portal.course_place_v1(a_course)), (select state_code from portal.course_place_v1(a_course))) then
    raise exception 'post-check: a multi-campus course without a state in the search was not labelled: %', x;
  end if;
  -- 2c. several campus cities inside the state: "Multiple campuses (VIC)", never a guessed city
  with cs as (select cc.course_id, s.code sc, count(distinct lower(btrim(ca.city))) n_city
                from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id join ref.subdivisions s on s.id = ca.subdivision_id
               where coalesce(ca.status, 'active') = 'active' and nullif(btrim(ca.city), '') is not null
                 and not exists (select 1 from catalogue.course_campuses p where p.course_id = cc.course_id and coalesce(p.is_primary, false))
               group by 1, 2)
  select cs.course_id, cs.sc into b_course, b_state from cs where cs.n_city >= 2 order by cs.course_id, cs.sc limit 1;
  if b_course is null then raise exception 'post-check: no course with several campus cities in one state found'; end if;
  x := catalogue.portal_course_cards_v1(array[b_course], '{}'::text[], 1, jsonb_build_object('states', jsonb_build_array(b_state))) -> 0;
  if x->>'city' is not null or x->>'place_basis' <> 'multiple_campuses_state'
     or x->>'place_label' <> 'Multiple campuses (' || coalesce(nullif(split_part(b_state, '-', 2), ''), b_state) || ')' then
    raise exception 'post-check: several campus cities in the state were not labelled: %', x;
  end if;
  -- 2d. the s1271 places are unchanged: a sole-city course still names its city
  select d.course_id into a_course from search.course_documents d
   where (select basis from portal.course_place_v1(d.course_id)) = 'sole_city'
     and exists (select 1 from catalogue.course_campuses cc where cc.course_id = d.course_id group by cc.course_id having count(*) > 1)
   order by d.course_id limit 1;
  if a_course is not null then
    x := catalogue.portal_course_cards_v1(array[a_course], '{}'::text[], 1, jsonb_build_object('states', '[]'::jsonb)) -> 0;
    if x->>'place_basis' <> 'sole_city' or x->>'city' is null or x->>'place_label' is not null then raise exception 'post-check: a sole-city card changed: %', x; end if;
  end if;
end $post$;
