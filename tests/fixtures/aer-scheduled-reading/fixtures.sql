-- Guards: Platform Admin direction 3 Nov 2026 09:32 (platform-led enrichment): academic entry requirements read on a schedule by eligibility
-- rules, on isolated fixtures. Runs after the D-R2/D-R3 database, stubs.sql, the live definitions and the 20261103130000 migration (see run.sh).
-- Every block raises on a failed check; each passing block prints "PASS <name>". No live data is copied: names and quotes are made up.
\set ON_ERROR_STOP 1
set client_min_messages = notice;

create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create function pg_temp.r(p_kind text, p_quote text, p_score numeric default null, p_basis text default null) returns jsonb language sql as $f$
  select jsonb_build_object('kind', p_kind, 'audience', 'all', 'description', p_quote, 'min_entry_score', p_score, 'min_entry_score_basis', p_basis,
                            'benchmark_band', null, 'min_grade', null, 'confidence', 0.95, 'quote', p_quote) $f$;
-- a finished reader result for a course (the reader's own path, security.enrich_entry_record_v1): returns the waiting Layer 4 item
create function pg_temp.read(p_course uuid, p_rows jsonb, p_dropped jsonb default '[]') returns uuid language plpgsql as $f$
declare v_id bigint;
begin
  insert into pipeline.field_enrich_items(provider_id, course_id, state, updated_at) select c.provider_id, c.id, 'ai', now() - interval '60 days' from catalogue.courses c where c.id = p_course returning id into v_id;
  perform security.enrich_entry_record_v1(v_id, jsonb_build_object('value', jsonb_build_object('rows', p_rows, 'dropped', p_dropped), 'model', 'fixture'));
  return (select (value->>'review_item_id')::uuid from pipeline.field_enrich_items where id = v_id);
end $f$;
create function pg_temp.set(p_key text, p_value jsonb) returns void language sql as $f$
  insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('pipeline', p_key, 'number', p_value)
  on conflict (toolset_key, key) do update set value = excluded.value $f$;
create function pg_temp.c(n text) returns uuid language sql as $f$ select ('c' || n || '-0000-4000-8000-000000000000')::uuid $f$;
create function pg_temp.p(n text) returns uuid language sql as $f$ select ('d2000000-0000-4000-8000-0000000000' || n)::uuid $f$;
create function pg_temp.writes() returns text language sql as $f$
  select (select count(*) from pipeline.admin_jobs) || '/' || (select count(*) from pipeline.field_enrich_items) || '/' || (select count(*) from pipeline.aer_schedule_runs)
      || '/' || (select count(*) from pipeline.aer_schedule_checks) || '/' || (select count(*) from pipeline.aer_read_supersessions)
      || '/' || (select count(*) from pipeline.layer4_review_items) || '/' || coalesce((select string_agg(status || coalesce(read_at::text, ''), ',' order by id) from pipeline.entry_matrix_sources), '-') $f$;

-- ------------------------------------------------------------------ the catalogue
insert into catalogue.providers(id, canonical_name, country_id, provider_type_id, publication_status, enrols_international)
select pg_temp.p(n), name, (select id from ref.countries where iso_alpha2 = cc), (select id from ref.provider_types where code = pt), pub, intl
  from (values ('01', 'Alpha University', 'AU', 'university', 'published', true), ('02', 'Kiwi Institute', 'NZ', 'private_vet', 'published', true),
               ('03', 'Listed College', 'AU', 'university', 'published', false), ('04', 'Maple College', 'CA', 'university', 'published', true),
               ('05', 'Draft College', 'AU', 'university', 'unpublished', true), ('06', 'Hidden College', 'AU', 'university', 'published', true),
               ('07', 'Gamma University', 'AU', 'university', 'published', true)) v(n, name, cc, pt, pub, intl);
insert into security.provider_hidden_v1 values (pg_temp.p('06'));
-- courses: c1xxxxxx Alpha, c2 Kiwi, c4 Maple, c5 Draft, c6 Hidden, c7 Gamma (reads waiting in Layer 4)
insert into catalogue.courses(id, provider_id, canonical_title, lifecycle_status)
select pg_temp.c(n), pg_temp.p(p), t, coalesce(l, 'active')
  from (values ('1000001', '01', 'Bachelor of Arts', null), ('1000002', '01', 'Bachelor of Old Things', 'archived'), ('1000003', '01', 'Bachelor of No Page', null),
               ('1000004', '01', 'Bachelor of Unstored', null), ('1000005', '01', 'Bachelor of Weak Identity', null), ('1000006', '01', 'Bachelor of Admitted', null),
               ('1000008', '01', 'Bachelor of In Progress', null), ('1000009', '01', 'Bachelor of Tried Lately', null),
               ('1000010', '01', 'Bachelor of Tried Long Ago', null), ('1000011', '01', 'Bachelor of No Value', null), ('1000012', '01', 'Bachelor of Locked', null),
               ('1000013', '01', 'Bachelor of Link Locked', null), ('1000014', '01', 'Bachelor of All Locked', null),
               ('1000015', '01', 'Master of A', null), ('1000016', '01', 'Master of B', null), ('1000017', '01', 'Master of C', null), ('1000018', '01', 'Master of D', null),
               ('1000019', '01', 'Master of E', null), ('1000020', '01', 'Master of F', null),
               ('2000001', '02', 'Certificate in Kiwi A', null), ('2000002', '02', 'Certificate in Kiwi B', null),
               ('3000001', '03', 'Listed Course', null), ('4000001', '04', 'Maple Course', null), ('5000001', '05', 'Draft Course', null), ('6000001', '06', 'Hidden Course', null),
               ('7000001', '07', 'Gamma Held Drops', null), ('7000002', '07', 'Gamma Held Rows', null), ('7000003', '07', 'Gamma Complete', null),
               ('7000005', '07', 'Gamma Tried Once', null), ('7000006', '07', 'Gamma Tried Twice', null),
               ('7000007', '07', 'Gamma Tried Lately', null)) v(n, p, t, l);
insert into pipeline.evidence_artifacts(id, storage_path) select c.id, case when c.id = pg_temp.c('1000004') then null else 'stored/' || c.id end from catalogue.courses c;
insert into pipeline.coverage_course_pages(course_id, provider_id, url, evidence_id, identity_basis)
select c.id, c.provider_id, 'https://example.edu/' || c.id, c.id, case when c.id = pg_temp.c('1000005') then 'weak' else 'cricos_code' end
  from catalogue.courses c where c.id <> pg_temp.c('1000003');
insert into catalogue.course_entry_requirements(course_id, kind, audience, quote, status) values (pg_temp.c('1000006'), 'prior_qualification', 'all', 'A degree', 'active');
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, updated_at) values
  (gen_random_uuid(), pg_temp.p('01'), pg_temp.c('1000008'), 'entry_requirements', 'queued', now()),
  (gen_random_uuid(), pg_temp.p('01'), pg_temp.c('1000009'), 'entry_requirements', 'skipped', now() - interval '5 days'),
  (gen_random_uuid(), pg_temp.p('01'), pg_temp.c('1000010'), 'entry_requirements', 'failed', now() - interval '40 days');
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, state) values ('course', pg_temp.c('1000011')::text, pg_temp.p('01'), 'entry_requirements', 'enrich_no_value', 'counting');
insert into pipeline.manual_locks values ('course', pg_temp.c('1000012'), 'entry_requirements'), ('course', pg_temp.c('1000013'), 'course_url'), ('course', pg_temp.c('1000014'), 'all');

-- waiting reads at Gamma (the reader's own path): one dropped a printed minimum no row covers; one holds only for a row a person leaves out;
-- one is whole; three more with drops for the retry rules
do $t$ begin
  perform pg_temp.read(pg_temp.c('7000001'), jsonb_build_array(pg_temp.r('prior_qualification', 'A relevant bachelors degree'),
            pg_temp.r('minimum_grade', 'with a B average or higher', 5, 'grade point average')));
  perform pg_temp.read(pg_temp.c('7000002'), jsonb_build_array(pg_temp.r('prior_qualification', 'A relevant bachelors degree'),
            pg_temp.r('general_note', 'Candidates must also pass the National Literacy and Numeracy Test')));
  perform pg_temp.read(pg_temp.c('7000003'), jsonb_build_array(pg_temp.r('prior_qualification', 'A relevant bachelors degree with honours')));
  perform pg_temp.read(pg_temp.c(n), jsonb_build_array(pg_temp.r('prior_qualification', 'A relevant bachelors degree'),
            pg_temp.r('minimum_grade', 'with a B average or higher', 5, 'grade point average')))
    from unnest(array['7000005', '7000006', '7000007']) n;
end $t$;
-- earlier corrected reads asked for three of them (history rows as D-R2 writes them, all refused)
insert into pipeline.aer_read_supersessions(old_item_id, course_id, source_url, enrich_item_id, reason, state, outcome, requested_at, closed_at)
select i.id, i.entity_id, i.proposed_value->>'url', 900000 + row_number() over (), 'earlier try', 'refused', 'still incomplete', now() - make_interval(days => d), now() - make_interval(days => d)
  from pipeline.layer4_review_items i join (values ('7000005', 20), ('7000006', 20), ('7000006', 30), ('7000007', 3)) v(n, d) on i.entity_id = pg_temp.c(v.n)
 where i.status = 'pending';

-- ------------------------------------------------------------------ governance: settings, countries, job paused, Canada issue
do $t$ begin
  perform pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and (key like 'aer.schedule%' or key like 'batch.aer_schedule%')
            and label is not null and unit is not null and used_by is not null and section = 'Entry requirements' and min_value is not distinct from min_value) = 14, 'fourteen settings');
  perform pg_temp.ok(security.aer_schedule_country_v1('CA') = '{"on": false, "reason": "no AER configuration", "country": "CA"}'::jsonb, 'CA off with its reason');
  perform pg_temp.ok((security.aer_schedule_country_v1('au')->>'on')::boolean and (security.aer_schedule_country_v1('NZ')->>'on')::boolean, 'AU and NZ on');
  perform pg_temp.ok(security.aer_schedule_country_v1('GB')->>'reason' = 'not in the countries switched on', 'an unlisted country is off, named');
  perform pg_temp.ok((select not active and command = 'select security.aer_schedule_tick_v1()' and schedule = '13 * * * *' from cron.job where jobname = 'aer-scheduled-read'), 'job paused');
  perform pg_temp.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'aer-scheduled-read' and control_rank = 6), 'job catalogued');
  perform pg_temp.ok((select payload->>'severity' = 'P2' and payload->>'workstream' = 'A3' and payload->'country_codes' = '["CA"]' and payload->>'impact' like '% active Canadian courses have no academic entry requirement%'
                        from pipeline.integration_issues where fingerprint = 'aer:country_not_configured:CA'), 'Canada issue raised (P2, A3)');
  perform pg_temp.ok(not security.aer_schedule_active_v1(), 'nothing switched on');
  raise notice 'PASS governance: 14 settings, AU/NZ on, CA off with the reason and one integration issue, job catalogued and paused';
end $t$;

-- ------------------------------------------------------------------ eligibility rules
do $t$ declare v_all uuid[]; v_run uuid[]; begin
  select array_agg(course_id order by course_id) into v_all from security.aer_schedule_courses_v1(null, true);
  perform pg_temp.ok(v_all = (select array_agg(pg_temp.c(n) order by pg_temp.c(n)) from unnest(array['1000001', '1000010', '1000013', '1000015', '1000016', '1000017', '1000018',
                                '1000019', '1000020', '2000001', '2000002']) n), 'eligible set: ' || v_all::text);
  -- refused for: archived course, no page, unstored page, weak identity, active requirement, read in progress, tried 5 days ago, open no-value hold,
  -- lock on entry requirements or all; providers not enrolling international students, in Canada, unpublished or hidden; reads waiting in Layer 4
  select array_agg(course_id order by turn, tier) into v_run from security.aer_schedule_courses_v1(100);
  perform pg_temp.ok(cardinality(v_run) = 7 and (select count(*) from security.aer_schedule_courses_v1(100) where provider_id = pg_temp.p('01')) = 5, 'five a provider a run');
  perform pg_temp.ok(v_run[1] = pg_temp.c('1000001') and v_run[2] = pg_temp.c('2000001'), 'providers take turns, universities first: ' || v_run::text);
  perform pg_temp.set('aer.schedule_retry_days', '3');
  perform pg_temp.ok(exists (select 1 from security.aer_schedule_courses_v1(null, true) where course_id = pg_temp.c('1000009')), 'tried 5 days ago is due after a 3-day retry');
  perform pg_temp.set('aer.schedule_retry_days', '30');
  perform pg_temp.set('aer.schedule_countries_off', '["NZ=paused for the test"]');
  perform pg_temp.ok(not exists (select 1 from security.aer_schedule_courses_v1(null, true) where country = 'NZ'), 'a country switched off reads nothing');
  perform pg_temp.set('aer.schedule_countries_off', '["CA=no AER configuration"]');
  raise notice 'PASS eligibility rules instead of a fixed list (11 eligible; 7 a run, 5 at most per provider)';
end $t$;

-- ------------------------------------------------------------------ held reads: which are read again
do $t$ declare r record; m jsonb; begin
  select jsonb_object_agg(c.canonical_title, h.outcome || case when h.eligible then ' *' else '' end) into m
    from security.aer_schedule_held_v1(10) h join catalogue.courses c on c.id = h.course_id;
  perform pg_temp.ok(m->>'Gamma Held Drops' = 'held: read again (D-R2) *', 'dropped minimums: read again ' || m::text);
  perform pg_temp.ok(m->>'Gamma Held Rows' = 'held only for rows a person leaves out', 'rows a person leaves out: not read again');
  perform pg_temp.ok(m->>'Gamma Complete' = 'complete', 'a whole read: not read again');
  perform pg_temp.ok(m->>'Gamma Tried Once' = 'held: read again (D-R2) *', 'one refused try 20 days ago: due again');
  perform pg_temp.ok(not m ? 'Gamma Tried Twice' and not m ? 'Gamma Tried Lately', 'two tries, or a try 3 days ago: not looked at');
  perform pg_temp.ok((select count(*) from security.aer_schedule_held_v1(1) where eligible) = 1, 'bounded by the run');
  raise notice 'PASS held reads: only those a corrected read can fix, within the tries and retry days';
end $t$;

-- ------------------------------------------------------------------ the preview writes nothing
do $t$ declare w text := pg_temp.writes(); p jsonb; begin
  p := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(pg_temp.writes() = w, 'nothing written by the preview: ' || w || ' -> ' || pg_temp.writes());
  perform pg_temp.ok((p->>'corrections')::int = 2 and (p->>'course_reads')::int = 7 and (p->>'estimate_usd')::numeric = round(9 * 0.005, 4) and p->>'refusal' is null,
                     'preview: 2 held, 7 new, US$0.045: ' || (p - 'checked' - 'held' - 'new')::text);
  raise notice 'PASS preview: what the next run would ask, with its estimate, nothing written';
end $t$;

-- ------------------------------------------------------------------ a run
do $t$ declare r jsonb; v_pend int := (select count(*) from pipeline.layer4_review_items where status = 'pending'); begin
  r := security.aer_schedule_tick_v1();
  perform pg_temp.ok((r->>'corrections')::int = 2 and (r->>'course_reads')::int = 7, 'asked 2 corrected and 7 new reads: ' || (r - 'checked')::text);
  perform pg_temp.ok((select count(*) from pipeline.aer_read_supersessions where state = 'requested' and requested_by = '63ba56cb-0000-4000-8000-000000000000') = 2, 'D-R2 requests in the owner''s name');
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items where status = 'pending') = v_pend, 'no second waiting item');
  perform pg_temp.ok((select count(*) from pipeline.admin_jobs where requested_by = '63ba56cb-0000-4000-8000-000000000000' and reason like '%Scheduled entry reading (job aer-scheduled-read)%'
                        and args->>'scraper' = 'false') = 9, 'nine one-course stored-page reads (the existing enqueue)');
  perform pg_temp.ok((select count(*) from pipeline.field_enrich_items where state = 'queued' and field = 'entry_requirements') = 10, 'nine queued items plus the one already in progress');
  perform pg_temp.ok((select state from pipeline.enrichment_flags where entity_key = pg_temp.c('1000011')::text) = 'counting', 'a no-value hold is not released');
  perform pg_temp.ok((select count(*) from pipeline.aer_schedule_checks) = 4 and (select course_reads + corrections from pipeline.aer_schedule_runs) = 9, 'run and checks recorded');
  r := security.aer_schedule_tick_v1();
  perform pg_temp.ok((r->>'corrections')::int = 0 and (r->>'course_reads')::int = 4, 'second run: the rest of Alpha, no duplicate: ' || (r - 'checked')::text);
  perform pg_temp.ok((select count(*) from (select course_id from pipeline.field_enrich_items where state = 'queued' group by 1 having count(*) > 1) z) = 0, 'no course asked twice');
  r := security.aer_schedule_tick_v1();
  perform pg_temp.ok((r->>'course_reads')::int = 0 and (r->>'corrections')::int = 0 and r->>'refusal' is null, 'third run: nothing left');
  raise notice 'PASS a run asks bounded reads through the existing enqueue and D-R2, never twice';
end $t$;

-- ------------------------------------------------------------------ daily cap, back-pressure, AI and balance, item gate
do $t$ declare r jsonb; w text; begin
  insert into catalogue.courses(id, provider_id, canonical_title) values (pg_temp.c('1000021'), pg_temp.p('01'), 'Master of G'), (pg_temp.c('1000022'), pg_temp.p('01'), 'Master of H'),
    (pg_temp.c('7000004'), pg_temp.p('07'), 'Gamma Held Under Pressure');
  insert into pipeline.evidence_artifacts(id, storage_path) values (pg_temp.c('1000021'), 'stored/x'), (pg_temp.c('1000022'), 'stored/x'), (pg_temp.c('7000004'), 'stored/x');
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, evidence_id) values (pg_temp.c('1000021'), pg_temp.p('01'), 'https://example.edu/21', pg_temp.c('1000021')),
    (pg_temp.c('1000022'), pg_temp.p('01'), 'https://example.edu/22', pg_temp.c('1000022')), (pg_temp.c('7000004'), pg_temp.p('07'), 'https://example.edu/74', pg_temp.c('7000004'));
  perform pg_temp.read(pg_temp.c('7000004'), jsonb_build_array(pg_temp.r('prior_qualification', 'A relevant bachelors degree'),
            pg_temp.r('minimum_grade', 'with a B average or higher', 5, 'grade point average')));
  -- the daily cap: 13 asked in the last 24 hours
  perform pg_temp.set('aer.schedule_daily_max', '13'); w := pg_temp.writes();
  r := security.aer_schedule_tick_v1();
  perform pg_temp.ok(r->>'refusal' = 'the daily cap is reached' and (r->>'course_reads')::int = 0 and (r->>'corrections')::int = 0, 'daily cap: ' || (r->>'refusal'));
  perform pg_temp.set('aer.schedule_daily_max', '14');
  r := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((r->>'room')::int = 1 and (r->>'corrections')::int + (r->>'course_reads')::int = 1, 'one left under the cap');
  perform pg_temp.set('aer.schedule_daily_max', '200');
  -- AI stopped, balance at the floor
  perform pg_temp.set('fixture.ai_stopped', '"lane guard reached"');
  r := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(r->>'refusal' like 'AI reading is stopped%' and (r->>'course_reads')::int = 0 and (r->>'matrix_pages')::int = 0, 'AI stopped');
  perform pg_temp.set('fixture.ai_stopped', '""');
  insert into pipeline.layer3_openrouter_observations values ('credits', 5.01, now() + interval '1 minute');
  r := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(r->>'refusal' like 'the estimate would take the OpenRouter balance below its floor%', 'balance floor');
  delete from pipeline.layer3_openrouter_observations where remaining_usd = 5.01;
  -- the item gate
  perform pg_temp.set('fixture.item_held', jsonb_build_array(pg_temp.c('1000021')));
  r := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(r->'skipped' @> jsonb_build_array(jsonb_build_object('course_id', pg_temp.c('1000021'), 'why', 'held by the item gate'))
                     and (r->>'course_reads')::int = 1, 'item gate respected');
  perform pg_temp.set('fixture.item_held', '[]');
  -- back-pressure: no new reads; the held read is still read again (it replaces a waiting item)
  perform pg_temp.set('aer.schedule_layer4_max', '3');
  r := security.aer_schedule_tick_v1();
  perform pg_temp.ok((r->>'back_pressure')::boolean and (r->>'course_reads')::int = 0 and (r->>'corrections')::int = 1, 'back-pressure: ' || (r - 'checked')::text);
  perform pg_temp.set('aer.schedule_layer4_max', '600');
  raise notice 'PASS daily cap, AI lane and floor, item gate, and Layer 4 back-pressure (held reads still corrected)';
end $t$;

-- ------------------------------------------------------------------ matrix re-reads: fixed list while paused, rules and bounded refresh while on
do $t$ declare r jsonb; f jsonb; begin
  insert into pipeline.entry_matrix_sources(id, provider_id, url, status, read_via, read_at) values
    ('e0000000-0000-4000-8000-000000000001', pg_temp.p('03'), 'https://listed.example/entry', 'read', 'direct', now() - interval '40 days'),
    ('e0000000-0000-4000-8000-000000000002', pg_temp.p('07'), 'https://gamma.example/entry', 'read', 'firecrawl', now() - interval '40 days'),
    ('e0000000-0000-4000-8000-000000000003', pg_temp.p('07'), 'https://gamma.example/entry2', 'read', 'direct', now() - interval '35 days'),
    ('e0000000-0000-4000-8000-000000000004', pg_temp.p('01'), 'https://alpha.example/entry', 'read', 'direct', now() - interval '5 days');
  -- paused: as before (the fixed list decides; the fire refreshes every due page in scope)
  perform pg_temp.ok(security.entry_matrix_enabled_v1(pg_temp.p('03')) and not security.entry_matrix_enabled_v1(pg_temp.p('07')), 'paused: the fixed list');
  r := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((r->>'matrix_pages')::int = 1 and r->'matrix'->0->>'source_id' = 'e0000000-0000-4000-8000-000000000001', 'paused preview: the listed page');
  f := security.entry_matrix_fire_v1();
  perform pg_temp.ok((f->>'refetch')::int = 1 and (select status from pipeline.entry_matrix_sources where id = 'e0000000-0000-4000-8000-000000000001') = 'found', 'paused: the fire refreshes as before');
  update pipeline.entry_matrix_sources set status = 'read' where id = 'e0000000-0000-4000-8000-000000000001';
  -- switched on: rules replace the list; the fire leaves the refresh to the job, which bounds it
  update cron.job set active = true where jobname = 'aer-scheduled-read';
  perform pg_temp.ok(not security.entry_matrix_enabled_v1(pg_temp.p('03')) and security.entry_matrix_enabled_v1(pg_temp.p('07'))
                     and not security.entry_matrix_enabled_v1(pg_temp.p('04')) and not security.entry_matrix_enabled_v1(pg_temp.p('02')), 'on: eligibility rules (entry page recorded)');
  f := security.entry_matrix_fire_v1();
  perform pg_temp.ok((f->>'refetch')::int = 0, 'on: the fire does not refresh');
  perform pg_temp.set('batch.aer_schedule_matrix', '1');
  r := security.aer_schedule_tick_v1();
  perform pg_temp.ok((r->>'matrix_pages')::int = 1 and (r->>'firecrawl_credits_estimate')::int = 1
                     and (select status from pipeline.entry_matrix_sources where id = 'e0000000-0000-4000-8000-000000000002') = 'found'
                     and (select status from pipeline.entry_matrix_sources where id = 'e0000000-0000-4000-8000-000000000003') = 'read', 'on: one due page a run, oldest first');
  perform pg_temp.set('aer.schedule_layer4_max', '1');
  r := security.aer_schedule_tick_v1();
  perform pg_temp.ok((r->>'matrix_pages')::int = 0, 'back-pressure stops matrix re-reads');
  perform pg_temp.set('aer.schedule_layer4_max', '600');
  update cron.job set active = false where jobname = 'aer-scheduled-read';
  perform pg_temp.ok(security.entry_matrix_enabled_v1(pg_temp.p('03')), 'paused again: the fixed list is back');
  raise notice 'PASS matrix: paused exactly as before; on, eligibility rules and a bounded refresh owned by the job';
end $t$;

-- ------------------------------------------------------------------ the operator read
do $t$ declare r jsonb; w text := pg_temp.writes(); m text; begin
  insert into auth.session values ('99999999-0000-4000-8000-000000000003', 3);
  begin perform public.admin_aer_schedule('{}'); m := null; exception when sqlstate '42501' then m := sqlerrm; end;
  perform pg_temp.ok(m = 'Pipeline Operator or above required', 'rank 3 refused');
  update auth.session set rank = 4;
  r := public.admin_aer_schedule('{}');
  perform pg_temp.ok(r->'job'->>'active' = 'false' and r->'countries'->1 @> '{"country": "CA", "on": false, "reason": "no AER configuration", "eligible_courses": 0}'
                     and (r->'countries'->0->>'eligible_courses')::int = (select count(*) from security.aer_schedule_courses_v1(null, true) where country = 'AU') and r->'next_run' ? 'by_provider' and jsonb_array_length(r->'last_runs') = 5
                     and (r->'daily'->>'ai_usd_at_most')::numeric = 1.00, 'operator read: ' || (r->'countries')::text || jsonb_array_length(r->'last_runs'));
  perform pg_temp.ok(pg_temp.writes() = w, 'the operator read writes nothing');
  delete from auth.session;
  raise notice 'PASS operator read (rank 4): job state, next run by provider, countries with CA off and its reason, daily figures, last runs';
end $t$;
