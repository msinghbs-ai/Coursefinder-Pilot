-- CF-247 Scholarship Coverage Recovery: the defects reproduced on the LIVE definitions (loaded from live-defs.json), before the migration.
-- Each line prints "before <case>: <what the live code does>"; run.sh checks these lines.
create function fx_before(p_case text, p_what text) returns void language plpgsql as $f$ begin raise notice 'before %: %', p_case, p_what; end $f$;
insert into ref.countries(id, iso_alpha2, scholarship_ingestion_enabled) values ('00000000-0000-0000-0000-0000000000a1', 'AU', true);
insert into catalogue.providers(id, canonical_name, country_id, website)
select ('00000000-0000-0000-0001-' || lpad(to_hex(g), 12, '0'))::uuid, 'Fixture provider ' || g, '00000000-0000-0000-0000-0000000000a1', 'https://www.p' || g || '.edu.au'
  from generate_series(1, 1500) g;
insert into catalogue.courses(provider_id, course_code) select p.id, lpad(g::text, 6, '0') || 'A' from catalogue.providers p, generate_series(1, 3) g;
insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
select id, website, 4, 'largest_unsearched', 'pending' from catalogue.providers;

-- RC1: the live picker orders every pending row by the per-row tier; with the daily budget on and the 30-course minimum, every one of these
-- small providers is held, so the picker returns nothing at all (the 00:50-05:40 UTC answers "discover: []")
do $$
declare t0 timestamptz := clock_timestamp(); v jsonb;
begin
  v := public.svc_scholarship_discover_next(6);
  perform fx_before('RC1 picker', 'returned ' || jsonb_array_length(v) || ' of 1500 pending (all held), ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms, every row evaluated');
end $$;

-- RC2: a refused map is written as a final "empty" with its count overwritten to 0, and the picker never takes "empty" again
do $$
declare p uuid := '00000000-0000-0000-0001-000000000001';
begin
  update pipeline.scholarship_discovery_providers set url_count = 322, status = 'mapped' where provider_id = p;
  perform public.svc_scholarship_discover_record(p, 'empty', 'https://www.p1.edu.au', 'map:budget', 0, '[]'::jsonb, '[]'::jsonb, null);
  perform fx_before('RC2 refused map', 'status ' || (select status from pipeline.scholarship_discovery_providers where provider_id = p)
    || ', url_count ' || (select url_count from pipeline.scholarship_discovery_providers where provider_id = p));
end $$;

-- RC7/F8: the all-time cap: the worker's ceiling is 60,000 whatever the daily share
do $$ begin perform fx_before('RC7 all-time cap', 'cap ' || (public.svc_scholarship_fc_budget()->>'cap')); end $$;

-- RC11/F10: the task sizes are literals
do $$
begin
  perform security.scholarship_task_fire_v1(array['discover']);
  perform fx_before('RC11 task sizes', (select body::text from fx_sent order by at desc limit 1));
  truncate fx_sent; truncate pipeline.edge_request_log;
end $$;

-- the fixture rows are removed again so the migration applies to the same state as live
truncate pipeline.scholarship_discovery_providers, catalogue.courses;
delete from catalogue.providers;
delete from ref.countries;
drop function fx_before(text, text);
