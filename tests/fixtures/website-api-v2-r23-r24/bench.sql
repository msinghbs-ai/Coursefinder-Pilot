-- Volume benchmark (after the checks): one provider at the size of the largest live provider (208 campuses; 3,000 returned courses, each at
-- three campuses) and 1,200 published scholarships. Times the live definitions (copied as fx.old_*) against the new ones in the same
-- database. Production timings (read-only EXPLAIN ANALYZE on live) are in the approval package; this run shows the shape of the cost.
insert into fx.ids(k) values ('PB');
create table fx.bench_ids as select 'course' t, g, gen_random_uuid() id from generate_series(1, 3000) g union all select 'scholarship', g, gen_random_uuid() from generate_series(1, 1200) g;
insert into pim.entity_registry(id, entity_type, stable_key) select fx.i('PB'), 'provider', 'fx:PB' union all select id, t, 'fx:bench:'||t||':'||g from fx.bench_ids;
insert into catalogue.providers(id, stable_key, canonical_name, country_id, primary_city) values (fx.i('PB'),'provider:fx:bench','Bench Provider',fx.i('AU'),'Sydney');
insert into catalogue.campuses(id, stable_key, provider_id, name, country_id, city, subdivision_id, status)
  select gen_random_uuid(), 'campus:fx:bench:'||g, fx.i('PB'), 'Campus '||g, fx.i('AU'), 'City '||(g % 40), fx.i('VIC'), 'active' from generate_series(1, 208) g;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, lifecycle_status)
  select id, 'course:fx:bench:'||g, fx.i('PB'), 'Bench course '||g, case when g % 50 = 0 then 'withdrawn' else 'active' end from fx.bench_ids where t = 'course';
insert into search.course_documents(course_id, provider_id, country_id, provider_name, provider_stable_key, country_code, course_title, search_text, search_tsv, publication_status)
  select c.id, c.provider_id, fx.i('AU'), 'Bench Provider', 'provider:fx:bench', 'AU', c.canonical_title, c.canonical_title, to_tsvector('simple', c.canonical_title), 'published'
    from catalogue.courses c where c.provider_id = fx.i('PB');
insert into catalogue.course_campuses(course_id, campus_id, delivery_mode)
  select c.id, k.id, 'on_campus' from (select id, row_number() over (order by stable_key) rn from catalogue.courses where provider_id = fx.i('PB')) c
    join (select id, row_number() over (order by stable_key) rn from catalogue.campuses where provider_id = fx.i('PB')) k on k.rn in ((c.rn % 208) + 1, ((c.rn + 7) % 208) + 1, ((c.rn + 61) % 208) + 1);
insert into pipeline.layer4_block_decisions(entity_type, entity_id, block_scope, event_type, reason_code, actor_id)
  select 'course', id, 'search', 'block', 'bench_hold', gen_random_uuid() from catalogue.courses where provider_id = fx.i('PB') and stable_key like '%7';
insert into scholarship.scholarships(id, stable_key, provider_id, name, publication_status)
  select id, 'scholarship:fx:bench:'||g, fx.i('PB'), 'Bench scholarship '||g, 'published' from fx.bench_ids where t = 'scholarship';
insert into scholarship.criteria(scholarship_id, criterion_type, value_codes, human_text)
  select id, 'student_type', array['international'], 'International students' from scholarship.scholarships where stable_key like 'scholarship:fx:bench:%';
insert into scholarship.nationality_readings(scholarship_id, codes, phrases, reader_version)
  select id, case when stable_key like '%3' then '{IN}'::text[] else '{}'::text[] end, '{}'::jsonb, 'scholarship-nationality-v1' from scholarship.scholarships where stable_key like 'scholarship:fx:bench:%';
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status)
  select 'scholarship', id, 'audience', 'pending' from scholarship.scholarships where stable_key like 'scholarship:fx:bench:%1';
analyze;
do $b$
declare t0 timestamptz; n int; o1 numeric; n1 numeric; o2 numeric; n2 numeric; l numeric; v jsonb; ids uuid[];
begin
  -- fixed: benchmark repetitions (a test parameter, not an operational value)
  n := 20;
  t0 := clock_timestamp(); for i in 1..n loop v := fx.old_provider_campuses(fx.i('PB')); end loop; o1 := extract(epoch from clock_timestamp() - t0) * 1000 / n;
  t0 := clock_timestamp(); for i in 1..n loop v := api.website_v2_provider_campuses(fx.i('PB')); end loop; n1 := extract(epoch from clock_timestamp() - t0) * 1000 / n;
  raise notice 'bench provider campuses (208 campuses, 3,000 courses, 9,000 links): live definition % ms, new % ms per call; items % -> %',
    round(o1, 2), round(n1, 2), jsonb_array_length(fx.old_provider_campuses(fx.i('PB'))), jsonb_array_length(v);
  ids := array(select id from scholarship.scholarships where stable_key like 'scholarship:fx:bench:%');
  t0 := clock_timestamp(); perform fx.old_scholarship_item(x) from unnest(ids) x; o2 := extract(epoch from clock_timestamp() - t0) * 1000 / cardinality(ids);
  t0 := clock_timestamp(); perform api.website_v2_scholarship_item(x) from unnest(ids) x; n2 := extract(epoch from clock_timestamp() - t0) * 1000 / cardinality(ids);
  raise notice 'bench scholarship item (1,200 scholarships): live definition % ms, new % ms per item', round(o2, 3), round(n2, 3);
  t0 := clock_timestamp(); for i in 1..n loop v := public.website_v2_scholarships('{}'::jsonb, 1, 50); end loop; l := extract(epoch from clock_timestamp() - t0) * 1000 / n;
  raise notice 'bench scholarships page of 50 (new): % ms per call', round(l, 2);
  t0 := clock_timestamp(); for i in 1..n loop v := public.website_v2_providers('{"provider_ids":["provider:fx:bench"]}'::jsonb, 1, 1, null); end loop; l := extract(epoch from clock_timestamp() - t0) * 1000 / n;
  raise notice 'bench provider detail list item for the 208-campus provider (new): % ms per call', round(l, 2);
end $b$;
