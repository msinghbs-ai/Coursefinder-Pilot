-- run after the migration: every new setting is complete, in range, readable by the worker; behaviours ship off; neighbours untouched
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if not c then raise exception 'FAIL %', m; end if; raise notice 'PASS %', m; end $$;
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in
  ('enrich.course_entry_quote_chars','reading.course_quote_fragments_on','reading.course_entry_fragment_min_chars','reading.entry_country_aliases_on','reading.entry_country_aliases','reading.entry_value_null_on')) = 6, 'six settings added');
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in
  ('enrich.course_entry_quote_chars','reading.course_quote_fragments_on','reading.course_entry_fragment_min_chars','reading.entry_country_aliases_on','reading.entry_country_aliases','reading.entry_value_null_on')
  and coalesce(label, '') <> '' and coalesce(help, '') <> '' and coalesce(unit, '') <> '' and coalesce(used_by, '') <> '' and coalesce(reason, '') <> '' and section = 'Entry requirements') = 6,
  'every new setting has a label, help, unit, used_by line, reason and section');
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and kind = 'number' and key in
  ('enrich.course_entry_quote_chars','reading.course_quote_fragments_on','reading.course_entry_fragment_min_chars','reading.entry_country_aliases_on','reading.entry_value_null_on')
  and min_value is not null and max_value is not null and (value #>> '{}')::numeric between min_value and max_value) = 5, 'every number has a range and sits inside it');
select pg_temp.ok((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'enrich.course_entry_quote_chars') = 300
  and (select max_value from pipeline.platform_toolset_settings where key = 'enrich.course_entry_quote_chars') = 300, 'the quote limit is 300 (today) and cannot be raised above the 300-character column');
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where key in ('reading.course_quote_fragments_on','reading.entry_country_aliases_on','reading.entry_value_null_on') and (value #>> '{}')::numeric = 0) = 3,
  'the three behaviours ship off');
select pg_temp.ok((select value from pipeline.platform_toolset_settings where key = 'reading.entry_country_aliases') = '["UK=GB", "GB-SCT=GB", "GB-ENG=GB", "GB-WLS=GB", "GB-NIR=GB"]'::jsonb, 'the aliases list is the five unambiguous Great Britain names');
select pg_temp.ok(not exists (select 1 from jsonb_array_elements_text((select value from pipeline.platform_toolset_settings where key = 'reading.entry_country_aliases')) a
  where a ~* '^(global|int|ib|ww|gac|any|all|worldwide|general|international)') , 'no global or non-country token is an alias');
-- the worker sees every new key through svc_worker_settings_v1 (the one function it reads settings with)
select pg_temp.ok((select count(*) from jsonb_object_keys(public.svc_worker_settings_v1()) k where k in
  ('enrich.course_entry_quote_chars','reading.course_quote_fragments_on','reading.course_entry_fragment_min_chars','reading.entry_country_aliases_on','reading.entry_country_aliases','reading.entry_value_null_on')) = 6,
  'svc_worker_settings_v1 returns all six');
select pg_temp.ok((public.svc_worker_settings_v1()->'reading.entry_country_aliases') ? 'UK=GB', 'the worker reads the aliases as a list of TOKEN=ISO text');
-- neighbours are untouched
select pg_temp.ok((select value from pipeline.platform_toolset_settings where key = 'enrich.course_entry_slice_overlap_chars') = '600'::jsonb
  and (select count(*) from pipeline.platform_toolset_settings where key like 'reading.entry_global%') = 2 and (select count(*) from pipeline.platform_toolset_settings) = 12, 'existing settings unchanged; only six rows added');
