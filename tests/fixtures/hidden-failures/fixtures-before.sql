-- CF-247 Workstream F fixtures, BEFORE the 20261103140000 migration: the live definitions (md5-checked by run.sh) on fixture data. Seeds the
-- data both phases use, shows each defect, and keeps today's behaviour (focus, refill, NZ picker) in fx.before_* for fixtures.sql to compare.
-- Prints one NOTICE "ok: ..." per assertion; any failure raises and stops the run. Nothing here is live data.
set timezone = 'UTC';
create or replace function fx.ok(p boolean, p_msg text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok: %', p_msg; end $f$;

-- countries and providers: AU a1-a3, NZ n1 (accepted by the scholarship admission rule) and n2, CA c1
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-00000000c0a0', 'AU'), ('00000000-0000-0000-0000-00000000c0b0', 'NZ'), ('00000000-0000-0000-0000-00000000c0c0', 'CA');
insert into catalogue.providers(id, stable_key, canonical_name, country_id, website) values
  ('00000000-0000-0000-0000-0000000000a1', 'a1', 'AU One', '00000000-0000-0000-0000-00000000c0a0', 'https://a1.edu.au'),
  ('00000000-0000-0000-0000-0000000000a2', 'a2', 'AU Two', '00000000-0000-0000-0000-00000000c0a0', 'https://a2.edu.au'),
  ('00000000-0000-0000-0000-0000000000a3', 'a3', 'AU Three', '00000000-0000-0000-0000-00000000c0a0', 'https://a3.edu.au'),
  ('00000000-0000-0000-0000-0000000000b1', 'n1', 'NZ One', '00000000-0000-0000-0000-00000000c0b0', 'https://n1.ac.nz'),
  ('00000000-0000-0000-0000-0000000000b2', 'n2', 'NZ Two', '00000000-0000-0000-0000-00000000c0b0', 'https://n2.ac.nz'),
  ('00000000-0000-0000-0000-0000000000c1', 'c1', 'CA One', '00000000-0000-0000-0000-00000000c0c0', 'https://c1.ca');
insert into fx.country select id, (select iso_alpha2 from ref.countries k where k.id = p.country_id) from catalogue.providers p;
insert into fx.admission_ok values ('00000000-0000-0000-0000-0000000000b1');
-- courses: a1 3, a2 2, a3 1, n1 2, n2 1, c1 1; course documents with missing English and intakes (the focus ranking)
insert into catalogue.courses(id, stable_key, provider_id, canonical_title)
select gen_random_uuid(), p.stable_key || '-' || g, p.id, 'Course ' || g from catalogue.providers p
  cross join lateral generate_series(1, case p.stable_key when 'a1' then 3 when 'a2' then 2 when 'n1' then 2 else 1 end) g;
insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, country_code)
select c.id, c.provider_id, p.country_id, p.canonical_name, c.canonical_title, 'x', to_tsvector('x'), 'published', f.cc
  from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join fx.country f on f.provider_id = p.id;

-- (d) focus: today only Australia is limited to its focus providers (top 2 in the fixture)
select security.enrich_focus_refresh_v1();
create table fx.before_focus as
  select p.stable_key, security.enrich_focus_v1(p.id) searched, (select f.in_focus from pipeline.enrich_focus_providers f where f.provider_id = p.id) in_focus, (select f.rank from pipeline.enrich_focus_providers f where f.provider_id = p.id) rk
    from catalogue.providers p order by 1;
do $t$ begin
  perform fx.ok((select array_agg(stable_key order by stable_key) from fx.before_focus where searched) = array['a1', 'a2', 'c1', 'n1', 'n2'], 'before: AU limited to its top 2 (a3 not searched); NZ and CA always searched');
  perform fx.ok((select count(*) from fx.before_focus where in_focus is not null) = 3, 'before: the focus list is built for AU only');
end $t$;

-- (d) scholarship refill: AU first with priority 4; NZ only through the admission rule
select security.scholarship_discovery_refill_v1(30);
create table fx.before_refill as select p.stable_key, d.priority, d.reason, d.status from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id order by 1;
do $t$ begin
  perform fx.ok((select array_agg(stable_key || ':' || priority || ':' || reason order by stable_key) from fx.before_refill)
                = array['a1:4:largest_unsearched', 'a2:4:largest_unsearched', 'a3:4:largest_unsearched', 'n1:1:university_nz'], 'before: AU priority 4; NZ only through the admission rule (n1), CA not queued');
end $t$;
truncate pipeline.scholarship_discovery_providers;

-- (b) NZ Code of Practice picker: two NZQA batches; the newest batch's parts not yet read are returned
insert into pipeline.sources(id, url) values ('00000000-0000-0000-0000-0000000005a1', 'https://www.nzqa.govt.nz/providers/search'), ('00000000-0000-0000-0000-0000000005a2', 'https://example.org/other');
insert into pipeline.evidence_artifacts(source_id, storage_path, captured_at) values
  ('00000000-0000-0000-0000-0000000005a1', 'regulatory/NZ/nzqa/old-offset-0-batch-20.json', now() - interval '10 days'),
  ('00000000-0000-0000-0000-0000000005a1', 'regulatory/NZ/nzqa/old-offset-20-batch-20.json', now() - interval '10 days'),
  ('00000000-0000-0000-0000-0000000005a1', 'regulatory/NZ/nzqa/new-offset-0-batch-20.json', now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000005a1', 'regulatory/NZ/nzqa/new-offset-20-batch-20.json', now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000005a1', 'regulatory/NZ/nzqa/new-offset-40-batch-20.json', now() - interval '20 hours'),
  ('00000000-0000-0000-0000-0000000005a2', 'regulatory/NZ/nzqa/other-offset-60-batch-20.json', now());
insert into pipeline.nz_cop_reads(path, error, reader) values ('regulatory/NZ/nzqa/new-offset-0-batch-20.json', null, 'v2');
create table fx.before_nzcop as select public.svc_nz_cop_next(10) v;
do $t$ begin
  perform fx.ok((select array_agg(x->>'path' order by x->>'path') from fx.before_nzcop, jsonb_array_elements(v) x)
                = array['regulatory/NZ/nzqa/new-offset-20-batch-20.json', 'regulatory/NZ/nzqa/new-offset-40-batch-20.json'], 'before: the picker returns the newest unread parts');
end $t$;

-- (c) CRICOS contact: every provider checked recently; the job (its live command) still calls the worker
insert into catalogue.provider_registrations values ('00000000-0000-0000-0000-0000000000a1', 'CRICOS', '00001A'), ('00000000-0000-0000-0000-0000000000a2', 'CRICOS', '00002B');
insert into pipeline.provider_contact_checks values ('00000000-0000-0000-0000-0000000000a1', 'regulatory_peo', now() - interval '23 days', 'found'),
                                                   ('00000000-0000-0000-0000-0000000000a2', 'regulatory_peo', now() - interval '23 days', 'found');
insert into cron.job(jobname, schedule, command, active) values
  ('cricos-peo', '* * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'cricos_peo', 'limit', security.pipeline_num_v1('batch.cricos_peo', 2)::int))$c$, true),
  ('country-scope-gate', '38 * * * *', $c$select security.country_scope_gate_v1(true, 'CA')$c$, true),
  ('admin-jobs', '* * * * *', $c$select security.admin_jobs_tick_v1(security.pipeline_num_v1('batch.admin_jobs', 10)::int)$c$, true);
insert into pipeline.automation_catalogue(jobname, area, label, description) values ('cricos-peo', 'Course pages', 'Read CRICOS contact (internal)', 'Reads the Principal Executive Officer from the CRICOS website (Firecrawl). Held for internal use; never published.'),
  ('country-scope-gate', 'Enrichment', 'Country course scope', 'Hourly: hides active Canadian courses ...');
do $t$ begin
  perform fx.ok(public.svc_cricos_peo_next(4) = '[]'::jsonb, 'before: no provider is due');
  truncate pipeline.provider_contact_checks; insert into pipeline.provider_contact_checks values ('00000000-0000-0000-0000-0000000000a1', 'regulatory_peo', now() - interval '23 days', 'found'),
                                                   ('00000000-0000-0000-0000-0000000000a2', 'regulatory_peo', now() - interval '23 days', 'found');
  execute (select command from cron.job where jobname = 'cricos-peo');
  perform fx.ok((select count(*) from fx.fired where what = 'coverage-sweep' and body->>'mode' = 'cricos_peo') = 1, 'before: the job calls the worker with nothing due (the idle call)');
  execute (select command from cron.job where jobname = 'country-scope-gate');
  perform fx.ok((select array_agg(body->>'country') from fx.fired where what = 'country_scope_gate') = array['CA'], 'before: the country is written into the job command');
end $t$;
truncate fx.fired;

-- (f) yield checks: provider_description failed its 2 calls in the window (IQ-00055); link_search idle under its daily cap (IQ-00048)
insert into pipeline.integration_yield_buckets(kind, key, bucket, calls, failures, sample) values
  ('edge', 'coverage-sweep:provider_description', date_trunc('hour', now()), 2, 2, '500 {"ok":false,"error":"svc_provider_description_next: canceling statement due to statement timeout"}'),
  ('edge', 'coverage-sweep:read', date_trunc('hour', now()), 10, 2, '500 x');
insert into pipeline.integration_validate_state(check_key, last_run_at, watermark_id, watermark_at) values ('yield_edge', now(), 0, now()), ('yield_ledger', now(), 0, now());
insert into pipeline.integration_yield_buckets(kind, key, bucket, calls, failures, items, ok) values ('ledger', 'link_search', date_trunc('hour', now()), 12, 0, 0, 0);
insert into fx.waiting values ('link_search');
insert into pipeline.course_link_search(sent_at) select now() from generate_series(1, 200);  -- the day's cap (200) reached
select security.integration_yield_checks_v1();
do $t$ begin
  perform fx.ok(not exists (select 1 from pipeline.integration_issues where fingerprint = 'hidden_worker_error:coverage-sweep:provider_description'), 'before: 2 of 2 failed provider_description calls open no issue (below 3)');
  perform fx.ok(exists (select 1 from pipeline.integration_issues where fingerprint = 'zero_yield:link_search'), 'before: link_search held by its daily cap is reported as zero yield');
end $t$;

-- (f) Pipeline yield: four lanes, no Enrich fields lane
do $t$ begin
  perform fx.ok(jsonb_array_length(security.pipeline_yield_v1(24)->'lanes') = 4, 'before: four lanes, no Enrich fields lane');
end $t$;
