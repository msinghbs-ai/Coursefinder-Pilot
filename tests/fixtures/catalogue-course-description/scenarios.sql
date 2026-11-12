-- Guards: Platform Admin 12 Nov 2026 20:50 (Course catalogue: a filter for updated course descriptions; the description shown as wrapped text, not "Populated").
-- Runs on the course-catalogue-columns fixture (production-representative volume, live definitions md5-checked), as role authenticated with a JWT subject, the way
-- PostgREST runs courses_page. Every row added here is invented. Each case prints PASS or stops the run.
\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, msg text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL %', msg; end if; raise notice 'PASS %', msg; end $$;
create or replace function pg_temp.page(p_args jsonb) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', md5('admin')::uuid::text, true); set local role authenticated;
  r := public.admin_read('courses_page', p_args); reset role; return r; end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.page(jsonb) to authenticated;
create or replace function pg_temp.has(p jsonb, p_id uuid) returns boolean language sql as $$ select exists (select 1 from jsonb_array_elements(p -> 'items') e where e ->> 'id' = p_id::text) $$;
create or replace function pg_temp.item(p jsonb, p_id uuid) returns jsonb language sql as $$ select e from jsonb_array_elements(p -> 'items') e where e ->> 'id' = p_id::text $$;

begin;
-- four courses of one provider: A written by the reader an hour ago, B three days ago, C no description; D read two hours ago, then edited by hand
create temporary table t_c as
  select (array_agg(c.id order by c.id))[1] a, (array_agg(c.id order by c.id))[2] b, (array_agg(c.id order by c.id))[3] c, (array_agg(c.id order by c.id))[4] d, c.provider_id p
    from catalogue.courses c group by c.provider_id having count(*) >= 4 order by c.provider_id limit 1;
grant select on t_c to authenticated;
update catalogue.courses set description = 'Studio units cover design thinking and user research, then prototyping and usability testing over three years. The final year centres on an industry brief.' where id = (select a from t_c);
update catalogue.courses set description = 'A two-year programme in applied data analysis with a supervised capstone project.' where id = (select b from t_c);
update catalogue.courses set description = null where id = (select c from t_c);
update catalogue.courses set description = 'Set by hand in the catalogue.' where id = (select d from t_c);
delete from pipeline.field_enrich_items where course_id in (select unnest(array[a, b, c, d]) from t_c) and field = 'description';
-- each reading holds the text it wrote (value.text, as security.enrich_course_text_record_v1 records it); E was read, then edited by hand
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, updated_at, value)
select (select job_id from pipeline.field_enrich_items where job_id is not null limit 1), p, a, 'description', 'filled', 'ai_stored', now() - interval '1 hour',
       jsonb_build_object('text', (select description from catalogue.courses where id = a)) from t_c
union all
select (select job_id from pipeline.field_enrich_items where job_id is not null limit 1), p, b, 'description', 'filled', 'ai_stored', now() - interval '3 days',
       jsonb_build_object('text', (select description from catalogue.courses where id = b)) from t_c
union all
select (select job_id from pipeline.field_enrich_items where job_id is not null limit 1), p, d, 'description', 'filled', 'ai_stored', now() - interval '2 hours',
       jsonb_build_object('text', 'The reader wrote this before a person edited it.') from t_c;

create temporary table t_p as select
  pg_temp.page(jsonb_build_object('provider_id', (select p from t_c), 'limit', 200)) allp,
  pg_temp.page(jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'description', 'updated_24h')) d1,
  pg_temp.page(jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'description', 'updated_7d')) d7,
  pg_temp.page(jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'description', 'populated')) pop,
  pg_temp.page(jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'description', 'missing')) mis,
  pg_temp.page(jsonb_build_object('provider_id', (select p from t_c), 'limit', 200, 'description', 'updated_7d', 'sort', 'fee', 'direction', 'desc')) d7fee,
  pg_temp.page(jsonb_build_object('limit', 50, 'description', 'populated', 'sort', 'fee', 'direction', 'desc')) feep,
  pg_temp.page(jsonb_build_object('limit', 50, 'description', 'missing', 'sort', 'completeness', 'direction', 'asc')) comp,
  pg_temp.page(jsonb_build_object('limit', 50)) simple;

-- the description itself, on every path
select pg_temp.ok(pg_temp.item(allp, (select a from t_c)) ->> 'description_text' = (select description from catalogue.courses where id = (select a from t_c)), 'REGRESSION text: a page item carries the description itself (description_text), whole') from t_p;
select pg_temp.ok((pg_temp.item(allp, (select a from t_c)) ->> 'description_updated_at')::timestamptz between now() - interval '61 minutes' and now() - interval '59 minutes', 'REGRESSION text: and when the description reader last wrote it') from t_p;
select pg_temp.ok(pg_temp.item(allp, (select c from t_c)) -> 'description_text' = 'null'::jsonb and pg_temp.item(allp, (select c from t_c)) -> 'description_updated_at' = 'null'::jsonb, 'a course with no description carries null for both (the screen shows its field state)') from t_p;
select pg_temp.ok(pg_temp.item(allp, (select d from t_c)) ->> 'description_text' = 'Set by hand in the catalogue.' and pg_temp.item(allp, (select d from t_c)) -> 'description_updated_at' = 'null'::jsonb, 'REGRESSION text: a description edited by hand after the reading is shown with no reader time (QA of #1081)') from t_p;
select pg_temp.ok((simple -> 'items' -> 0) ? 'description_text' and (simple -> 'items' -> 0) ? 'field_states', 'REGRESSION text: the unfiltered first page (its own fast path) carries it too, beside the existing columns') from t_p;
-- the filter
select pg_temp.ok(pg_temp.has(d1, (select a from t_c)) and not pg_temp.has(d1, (select b from t_c)) and not pg_temp.has(d1, (select c from t_c)) and not pg_temp.has(d1, (select d from t_c)), 'REGRESSION filter: Written by the reader in the last 24 hours lists the reading of an hour ago only (not the hand-edited one read two hours ago)') from t_p;
select pg_temp.ok(pg_temp.has(d7, (select a from t_c)) and pg_temp.has(d7, (select b from t_c)) and not pg_temp.has(d7, (select d from t_c)), 'REGRESSION filter: Updated in the last 7 days adds the one of three days ago') from t_p;
select pg_temp.ok(pg_temp.has(pop, (select d from t_c)) and not pg_temp.has(pop, (select c from t_c)) and pg_temp.has(mis, (select c from t_c)) and not pg_temp.has(mis, (select a from t_c)), 'REGRESSION filter: Has a description and No description split the courses') from t_p;
select pg_temp.ok((pop ->> 'total')::int + (mis ->> 'total')::int = (allp ->> 'total')::int, 'held and not held add up to the whole list (with the provider''s other filters kept)') from t_p;
select pg_temp.ok(pg_temp.has(d7fee, (select a from t_c)) and not pg_temp.has(d7fee, (select c from t_c)) and (d7fee ->> 'total')::int = (d7 ->> 'total')::int, 'the filter holds under the fee sort too') from t_p;
-- the fee and completeness sorts are applied with the filter (QA of #1081): the page comes back in that order
select pg_temp.ok((select array_agg(coalesce((e ->> 'fee_amount')::numeric, -1) order by o) from t_p, jsonb_array_elements(feep -> 'items') with ordinality x(e, o))
                  = (select array_agg(coalesce((e ->> 'fee_amount')::numeric, -1) order by (e ->> 'fee_amount')::numeric desc nulls last, o) from t_p, jsonb_array_elements(feep -> 'items') with ordinality x(e, o)),
  'REGRESSION sort: with the filter, Tuition sorts high to low (no fee last)');
select pg_temp.ok((select array_agg((e ->> 'completeness_score_v2')::numeric order by o) from t_p, jsonb_array_elements(comp -> 'items') with ordinality x(e, o))
                  = (select array_agg((e ->> 'completeness_score_v2')::numeric order by (e ->> 'completeness_score_v2')::numeric asc, o) from t_p, jsonb_array_elements(comp -> 'items') with ordinality x(e, o)),
  'REGRESSION sort: with the filter, Completeness sorts low to high');
select pg_temp.ok((allp ->> 'total')::int = (select count(*) from catalogue.courses where provider_id = (select p from t_c)), 'without the filter the list is unchanged') from t_p;
commit;
-- at production volume (every course): the filtered page stays bounded
do $$ declare t0 timestamptz; ms numeric; r jsonb;
begin
  for i in 1 .. 2 loop t0 := clock_timestamp(); r := pg_temp.page('{"description": "updated_7d", "limit": 50}'); ms := extract(epoch from clock_timestamp() - t0) * 1000; end loop;
  perform pg_temp.ok(ms < 3000, format('benchmark: Updated in the last 7 days over %s courses: %s ms (under 3,000), total %s', (select count(*) from catalogue.courses), round(ms, 1), r ->> 'total'));
  t0 := clock_timestamp(); r := pg_temp.page('{"description": "missing", "limit": 50, "lifecycle_status": "active"}'); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  perform pg_temp.ok(ms < 3000, format('benchmark: No description, active: %s ms (under 3,000), total %s', round(ms, 1), r ->> 'total'));
end $$;
