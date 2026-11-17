-- Guards: Platform Admin 18 Nov 2026 07:03 (Courses: Study load and Empty reason columns and filters; Campuses: Primary and Locality column and filters).
-- Runs on the course-catalogue-columns fixture (production-representative volume, live definitions md5-checked), as role authenticated with a JWT subject,
-- the way PostgREST runs courses_page and campuses_page. Every row changed here is invented. Each case prints PASS or stops the run.
\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, msg text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL %', msg; end if; raise notice 'PASS %', msg; end $$;
create or replace function pg_temp.page(p_op text, p_args jsonb) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', md5('admin')::uuid::text, true); set local role authenticated;
  r := public.admin_read(p_op, p_args); reset role; return r; end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.page(text, jsonb) to authenticated;
create or replace function pg_temp.item(p jsonb, p_id uuid) returns jsonb language sql as $$ select e from jsonb_array_elements(p -> 'items') e where e ->> 'id' = p_id::text $$;
create or replace function pg_temp.ids(p jsonb) returns uuid[] language sql as $$ select coalesce(array_agg((e ->> 'id')::uuid order by o), '{}') from jsonb_array_elements(p -> 'items') with ordinality x(e, o) $$;

begin;
-- COURSES: five courses of one provider: A full-time, B part-time, C both and not published by the provider, D waiting to be read, E nothing held
create temporary table t_c as
  select (array_agg(c.id order by c.id))[1] a, (array_agg(c.id order by c.id))[2] b, (array_agg(c.id order by c.id))[3] c, (array_agg(c.id order by c.id))[4] d, (array_agg(c.id order by c.id))[5] e, c.provider_id p, count(*) n
    from catalogue.courses c group by c.provider_id having count(*) between 5 and 150 order by c.provider_id limit 1;
grant select on t_c to authenticated;
update catalogue.courses set study_load = null, empty_reason_code = null;
update catalogue.courses set study_load = 'full_time' where id = (select a from t_c);
update catalogue.courses set study_load = 'part_time' where id = (select b from t_c);
update catalogue.courses set study_load = 'both', empty_reason_code = 'not_published_by_provider' where id = (select c from t_c);
update catalogue.courses set empty_reason_code = 'pending_extraction' where id = (select d from t_c);
analyze catalogue.courses;
create temporary table t_p as select
  pg_temp.page('courses_page', jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'lifecycle_status', '')) allp,
  pg_temp.page('courses_page', jsonb_build_object('study_load', 'full_time', 'limit', 200)) ft,
  pg_temp.page('courses_page', jsonb_build_object('study_load', 'both')) both_,
  pg_temp.page('courses_page', jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'study_load', 'none')) none_,
  pg_temp.page('courses_page', jsonb_build_object('empty_reason', 'any', 'limit', 200)) er_any,
  pg_temp.page('courses_page', jsonb_build_object('empty_reason', 'pending_extraction')) er_pe,
  pg_temp.page('courses_page', jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'empty_reason', 'none')) er_none,
  pg_temp.page('courses_page', jsonb_build_object('study_load', 'both', 'empty_reason', 'not_published_by_provider', 'sort', 'fee', 'direction', 'desc')) both_fee,
  pg_temp.page('courses_page', jsonb_build_object('study_load', 'part_time', 'sort', 'completeness')) pt_comp,
  pg_temp.page('courses_page', '{"limit": 5}'::jsonb) simple;
select pg_temp.ok((select pg_temp.item(allp, (select a from t_c)) ->> 'study_load' = 'full_time' and pg_temp.item(allp, (select c from t_c)) ->> 'empty_reason_code' = 'not_published_by_provider'
  and pg_temp.item(allp, (select e from t_c)) ? 'study_load' and pg_temp.item(allp, (select e from t_c)) -> 'study_load' = 'null'::jsonb and pg_temp.item(allp, (select e from t_c)) -> 'empty_reason_code' = 'null'::jsonb from t_p),
  'REGRESSION columns: a page item carries study_load and empty_reason_code (null when not held)');
select pg_temp.ok((select (simple -> 'items' -> 0) ? 'study_load' and (simple -> 'items' -> 0) ? 'empty_reason_code' and (simple -> 'items' -> 0) ? 'description_text' from t_p), 'the unfiltered first page carries the two fields too, beside the description');
select pg_temp.ok((select (ft ->> 'total')::int = 1 and pg_temp.ids(ft) = array[(select a from t_c)] and (both_ ->> 'total')::int = 1 and pg_temp.ids(both_) = array[(select c from t_c)] from t_p), 'Study load filter: full-time and both each find their one course');
select pg_temp.ok((select (none_ ->> 'total')::int = (select count(*) from catalogue.courses c where c.provider_id = (select p from t_c) and c.lifecycle_status = 'active' and c.study_load is null)
  and not (pg_temp.ids(none_) && array[(select a from t_c), (select b from t_c), (select c from t_c)]) from t_p), 'Study load filter: not held leaves out the three courses that hold one');
select pg_temp.ok((select (er_any ->> 'total')::int = 2 and pg_temp.ids(er_any) @> array[(select c from t_c), (select d from t_c)] and (er_pe ->> 'total')::int = 1 and pg_temp.ids(er_pe) = array[(select d from t_c)] from t_p),
  'Empty reason filter: any reason finds both; one reason finds its course');
select pg_temp.ok((select not (pg_temp.ids(er_none) && array[(select c from t_c), (select d from t_c)]) and (er_none ->> 'total')::int > 0 from t_p), 'Empty reason filter: no reason leaves out the two courses with one');
select pg_temp.ok((select (both_fee ->> 'total')::int = 1 and both_fee ->> 'sort' = 'fee' and (pt_comp ->> 'total')::int = 1 and pg_temp.ids(pt_comp) = array[(select b from t_c)] from t_p),
  'the two filters combine, and hold under the fee and completeness sorts (bounded path)');
select pg_temp.ok((pg_temp.page('courses_page', '{"sort": "fee"}'::jsonb) ->> 'total')::int > 1000, 'with neither filter the fee sort keeps its earlier path and the whole catalogue');
-- the filters read the courses that hold a value, through their indexes
select pg_temp.ok((select count(*) from pg_indexes where schemaname = 'catalogue' and tablename = 'courses' and indexname in ('courses_study_load_idx', 'courses_empty_reason_code_idx')) = 2, 'both partial indexes are there');
do $b$ declare t0 timestamptz; ms numeric; r jsonb; begin
  t0 := clock_timestamp(); r := pg_temp.page('courses_page', '{"study_load": "both", "lifecycle_status": "active"}'::jsonb); ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  perform pg_temp.ok(ms < 3000, format('benchmark: Study load both, active: %s ms (under 3,000), total %s', ms, r ->> 'total'));
  t0 := clock_timestamp(); r := pg_temp.page('courses_page', '{"empty_reason": "none", "lifecycle_status": "active"}'::jsonb); ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  perform pg_temp.ok(ms < 3000, format('benchmark: no empty reason, active (the widest case): %s ms (under 3,000), total %s', ms, r ->> 'total'));
end $b$;

-- CAMPUSES: one provider's campuses; the first is primary; two postcodes map to localities (one postcode in two localities, one of them the primary match)
create temporary table t_k as
  select (array_agg(ca.id order by lower(ca.name), ca.id))[1] a, (array_agg(ca.id order by lower(ca.name), ca.id))[2] b, (array_agg(ca.id order by lower(ca.name), ca.id))[3] c, ca.provider_id p, count(*) n,
         (select co.iso_alpha2 from catalogue.providers p join ref.countries co on co.id = p.country_id where p.id = ca.provider_id) cc
    from catalogue.campuses ca group by ca.provider_id having count(*) between 3 and 40 order by ca.provider_id limit 1;
grant select on t_k to authenticated;
update catalogue.campuses set is_primary = null, primary_basis = null;
update catalogue.campuses set is_primary = true, primary_basis = 'register_head_office', postcode = ' 9001 ' where id = (select a from t_k);
update catalogue.campuses set is_primary = false, postcode = '9002' where id = (select b from t_k);
update catalogue.campuses set postcode = null where id = (select c from t_k);
delete from destination.locality_postcodes; delete from destination.localities;
insert into destination.localities(id, country_code, name, geography_type, status) values
  (md5('L1')::uuid, (select cc from t_k), 'Northside 100% Urban_Area', 'SUA', 'draft'), (md5('L2')::uuid, (select cc from t_k), 'Riverbend', 'SUA', 'published'), (md5('L3')::uuid, (select cc from t_k), 'Elsewhere', 'SUA', 'draft');
insert into destination.locality_postcodes(locality_id, country_code, postcode, containment_share, is_primary_match, boundary_vintage) values
  (md5('L1')::uuid, (select cc from t_k), '9001', 0.7, true, '2021'), (md5('L3')::uuid, (select cc from t_k), '9001', 0.3, false, '2021'), (md5('L2')::uuid, (select cc from t_k), '9002', 1, true, '2021');
create temporary table t_q as select
  pg_temp.page('campuses_page', jsonb_build_object('provider_id', (select p from t_k), 'limit', 200)) allk,
  pg_temp.page('campuses_page', jsonb_build_object('provider_id', (select p from t_k), 'primary', 'true')) prim,
  pg_temp.page('campuses_page', jsonb_build_object('provider_id', (select p from t_k), 'primary', 'false', 'limit', 200)) notprim,
  pg_temp.page('campuses_page', jsonb_build_object('locality', 'riverbend')) loc,
  pg_temp.page('campuses_page', jsonb_build_object('locality', '100% urban_')) loc_lit,
  pg_temp.page('campuses_page', jsonb_build_object('locality', '%')) loc_pct,
  pg_temp.page('campuses_page', jsonb_build_object('locality', 'Elsewhere')) loc_secondary,
  pg_temp.page('campuses_page', '{}'::jsonb) first_page,
  pg_temp.page('campuses_page', '{"sort": "courses", "direction": "desc", "limit": 3}'::jsonb) by_courses,
  pg_temp.page('campuses_page', '{"offset": 1000000}'::jsonb) beyond;
select pg_temp.ok((select (allk ->> 'total')::int = (select n from t_k) and pg_temp.ids(allk) = (select array_agg(ca.id order by lower(ca.name), ca.id) from catalogue.campuses ca where ca.provider_id = (select p from t_k))
  and allk ->> 'execution_profile' = 'campuses_page_v2' from t_q), 'campuses_page is answered by the new read, in the same name order, with the same total');
select pg_temp.ok((select pg_temp.item(allk, (select a from t_k)) ->> 'is_primary' = 'true' and pg_temp.item(allk, (select a from t_k)) ->> 'primary_basis' = 'register_head_office'
  and pg_temp.item(allk, (select b from t_k)) ->> 'is_primary' = 'false' and pg_temp.item(allk, (select c from t_k)) ->> 'is_primary' = 'false' from t_q), 'REGRESSION Primary: each item says whether it is the primary campus (not recorded reads as not primary)');
select pg_temp.ok((select pg_temp.item(allk, (select a from t_k)) ->> 'locality_name' = 'Northside 100% Urban_Area' and pg_temp.item(allk, (select a from t_k)) ->> 'locality_status' = 'draft'
  and pg_temp.item(allk, (select b from t_k)) ->> 'locality_name' = 'Riverbend' and pg_temp.item(allk, (select b from t_k)) ->> 'locality_status' = 'published'
  and pg_temp.item(allk, (select c from t_k)) -> 'locality_name' = 'null'::jsonb from t_q), 'Locality: looked up from the trimmed postcode, the primary match only, with its review status; none without a postcode');
select pg_temp.ok((select jsonb_typeof(pg_temp.item(allk, (select a from t_k)) -> 'course_count') = 'number'
  and (pg_temp.item(allk, (select a from t_k)) ->> 'course_count')::int = (select count(*) from catalogue.course_campuses cc where cc.campus_id = (select a from t_k)) from t_q), 'the course count is still on each item');
select pg_temp.ok((select (prim ->> 'total')::int = 1 and pg_temp.ids(prim) = array[(select a from t_k)] and (notprim ->> 'total')::int = (select n - 1 from t_k) from t_q), 'Primary filter: primary only, and not primary');
select pg_temp.ok((select (loc ->> 'total')::int = 1 and pg_temp.ids(loc) = array[(select b from t_k)] and (loc_lit ->> 'total')::int = 1 and pg_temp.ids(loc_lit) = array[(select a from t_k)]
  and (loc_pct ->> 'total')::int = 1 and (loc_secondary ->> 'total')::int = 0 from t_q), 'Locality search: by name, any case; typed % and _ are text; a postcode''s secondary locality is not matched');
select pg_temp.ok((select (first_page ->> 'total')::int = (select count(*) from catalogue.campuses) and jsonb_array_length(first_page -> 'items') = 50
  and pg_temp.ids(first_page) = (select array_agg(id order by lower(name), id) from (select id, name from catalogue.campuses order by lower(name), id limit 50) x) from t_q), 'the unfiltered first page: 50 rows in name order and the full total');
select pg_temp.ok((select (by_courses -> 'items' -> 0 ->> 'course_count')::int >= (by_courses -> 'items' -> 2 ->> 'course_count')::int
  and (by_courses -> 'items' -> 0 ->> 'course_count')::int = (select max(n) from (select count(*) n from catalogue.course_campuses group by campus_id) x) from t_q), 'sorting by courses puts the campus with most courses first');
select pg_temp.ok((select jsonb_array_length(beyond -> 'items') = 0 and (beyond ->> 'total')::int = (select count(*) from catalogue.campuses) from t_q), 'a page past the end is empty and still gives the total');
do $b$ declare t0 timestamptz; ms numeric; r jsonb; begin
  t0 := clock_timestamp(); r := pg_temp.page('campuses_page', '{}'::jsonb); ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  perform pg_temp.ok(ms < 1500, format('benchmark: Campuses first page: %s ms (under 1,500), total %s', ms, r ->> 'total'));
  t0 := clock_timestamp(); r := pg_temp.page('campuses_page', '{"primary": "false", "sort": "courses", "direction": "desc"}'::jsonb); ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  perform pg_temp.ok(ms < 3000, format('benchmark: Campuses not primary, sorted by courses (the widest case): %s ms (under 3,000), total %s', ms, r ->> 'total'));
end $b$;
-- a signed-in person with no role is refused; anon cannot run the read
do $r$ begin
  perform set_config('request.jwt.claim.sub', md5('nobody')::uuid::text, true);
  begin perform security.admin_campuses_page_v2('{}'::jsonb); raise exception 'FAIL a person with no role read the Campuses list';
  exception when insufficient_privilege then raise notice 'PASS a signed-in person with no role is refused'; end;
end $r$;
select pg_temp.ok(not has_function_privilege('anon', 'security.admin_campuses_page_v2(jsonb)', 'execute'), 'anon cannot run the Campuses list');
-- the ILEP draft is marked
select pg_temp.ok((select payload ->> 'notes' like 'Wave 2 draft, pre-staged 17 Nov 2026. DEPRECATING SOURCE (Platform Admin 18 Nov 2026):%TrustEd Ireland%' and length(payload ->> 'notes') <= 600
  from pipeline.layer1_source_inductions where payload ->> 'source_label' = 'Interim List of Eligible Programmes (ILEP)'), 'the ILEP draft carries the deprecation note (within the wizard''s 600 characters)');
rollback;
