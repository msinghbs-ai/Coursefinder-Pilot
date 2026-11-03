-- CF-247 Workstream C fixtures: every case of the course description and application deadline fields, on the migrated definitions.
-- Each check raises on failure (psql -v ON_ERROR_STOP=1) and prints "ok <case>" on success.
create function pg_temp.ok(p_case text, p_cond boolean, p_detail text default '') returns void language plpgsql as $$
begin
  if p_cond is distinct from true then raise exception 'FAILED %: %', p_case, p_detail; end if;
  raise notice 'ok %', p_case;
end $$;
-- a reading as the worker records it (course-text.ts courseTextResults)
create function pg_temp.desc_read(p_item bigint, p_sentences jsonb, p_about boolean default true) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('item_id', p_item, 'model', 'openai/gpt-4.1-mini', 'worker', 'coverage-sweep-worker-v0.59.4', 'prompt_version', 'course-text-v1', 'cost', 0.001,
    'value', jsonb_build_object('about_course', p_about, 'sentences', p_sentences), 'quote', p_sentences->0->>'quote',
    'reason', case when not p_about or jsonb_array_length(p_sentences) = 0 then 'the page does not state it' end)) $$;
create function pg_temp.dl_read(p_item bigint, p_deadlines jsonb) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('item_id', p_item, 'model', 'openai/gpt-4.1-mini', 'worker', 'coverage-sweep-worker-v0.59.4', 'prompt_version', 'course-text-v1', 'cost', 0.001,
    'value', jsonb_build_object('deadlines', p_deadlines), 'quote', p_deadlines->0->>'quote', 'reason', case when jsonb_array_length(p_deadlines) = 0 then 'the page does not state it' end)) $$;
create temp table fx_last(r jsonb);
create function pg_temp.rec(p jsonb) returns void language sql as $$ delete from fx_last; insert into fx_last values (p) $$;
create function pg_temp.last() returns jsonb language sql as $$ select r from fx_last $$;
create function pg_temp.s(p_text text, p_quote text, p_on boolean default true) returns jsonb language sql as $$ select jsonb_build_object('text', p_text, 'quote', p_quote, 'on_page', p_on) $$;

-- providers: an Australian university (P1), a New Zealand provider (P2), an Australian provider that is not published (P3)
insert into catalogue.providers(id, country_id, canonical_name, lifecycle_status) values
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 'Southern University', 'active'),
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a2', 'Harbour Polytechnic', 'active'),
 ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000a1', 'Hidden College', 'hidden');
-- twelve P1 courses (C01-C12), two P2 courses (C21, C22), one P3 course (C31), one P1 course with no stored page (C13), one archived (C14)
insert into catalogue.courses(id, provider_id, canonical_title, lifecycle_status, description)
select ('20000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, '10000000-0000-0000-0000-000000000001', 'Course ' || n, 'active', null from generate_series(1, 13) n;
insert into catalogue.courses(id, provider_id, canonical_title, lifecycle_status) values
 ('20000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-000000000001', 'Course 14', 'archived'),
 ('20000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000002', 'Course 21', 'active'),
 ('20000000-0000-0000-0000-000000000022', '10000000-0000-0000-0000-000000000002', 'Course 22', 'active'),
 ('20000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000003', 'Course 31', 'active');
update catalogue.courses set description = 'Held already.' where id = '20000000-0000-0000-0000-000000000012';
-- stored pages: bound with a proof for every course but C13; C22 is NZ with a CRICOS proof (not admitted in NZ); C11's binding has no proof
insert into pipeline.evidence_artifacts(id, source_url, captured_at)
select ('30000000-0000-0000-0000-0000000000' || right(c.id::text, 2))::uuid, 'https://southern.example/course/' || right(c.id::text, 2), now() - interval '2 days'
  from catalogue.courses c where c.id <> '20000000-0000-0000-0000-000000000013';
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis, evidence_id, read_at)
select c.id, c.provider_id, 'https://southern.example/course/' || right(c.id::text, 2), 'bound', 'read',
       case when c.id = '20000000-0000-0000-0000-000000000022' then 'cricos_code' when c.id = '20000000-0000-0000-0000-000000000011' then null else 'exact_title' end,
       ('30000000-0000-0000-0000-0000000000' || right(c.id::text, 2))::uuid, now() - interval '2 days'
  from catalogue.courses c where c.id <> '20000000-0000-0000-0000-000000000013';
-- intakes: C01 February 2027 (starts 1 Mar 2027) and July 2027 (starts 20 Jul 2027); C02 one intake; C03 two intakes; C04 a deadline held already;
-- C05 Semester 1 2027; C21 one NZ intake
insert into catalogue.course_intakes(id, course_id, intake_year, intake_label, start_date, application_deadline) values
 ('40000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000001', 2027, 'February', '2027-03-01', null),
 ('40000000-0000-0000-0000-000000000012', '20000000-0000-0000-0000-000000000001', 2027, 'July', '2027-07-20', null),
 ('40000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000002', 2027, 'February', '2027-02-22', null),
 ('40000000-0000-0000-0000-000000000031', '20000000-0000-0000-0000-000000000003', 2027, 'February', null, null),
 ('40000000-0000-0000-0000-000000000032', '20000000-0000-0000-0000-000000000003', 2027, 'July', null, null),
 ('40000000-0000-0000-0000-000000000041', '20000000-0000-0000-0000-000000000004', 2027, 'February', null, '2026-12-01'),
 ('40000000-0000-0000-0000-000000000051', '20000000-0000-0000-0000-000000000005', 2027, 'Semester 1', null, null),
 ('40000000-0000-0000-0000-000000000211', '20000000-0000-0000-0000-000000000021', 2027, 'February', null, null);

-- 1 the field list --------------------------------------------------------------------------------------------------------------------
select pg_temp.ok('1a fields: description and deadline are Enrich fields fields (course level, stored page; scraper allowed by a rule only)',
  (select count(*) = 2 and bool_and(level = 'course' and sources = array['ai_stored', 'scraper']) from security.enrich_fields_v1() where field in ('description', 'deadline')));
select pg_temp.ok('1b the earlier ten fields are unchanged', (select count(*) = 10 from security.enrich_fields_v1() where sort <= 10));
select pg_temp.ok('1c register: reader enrich for both; source rule ALL is the stored page only',
  (select count(*) = 2 from pipeline.field_register where field in ('description', 'deadline') and reader = 'enrich')
  and (select count(*) = 2 from pipeline.field_source_rules where country_code = 'ALL' and field in ('description', 'deadline') and sources = array['ai_stored']));
select pg_temp.ok('1d page proofs: description and deadline take each country''s intakes proofs',
  (select bool_and(identities->'description' = identities->'intakes' and identities->'deadline' = identities->'intakes') from pipeline.coverage_admission_countries));
select pg_temp.ok('1e settings: every new setting has a label, range, unit and used_by',
  (select count(*) = 10 and bool_and(label <> '' and min_value is not null and max_value is not null and unit is not null and used_by is not null and (value #>> '{}')::numeric between min_value and max_value)
     from pipeline.platform_toolset_settings where key like 'enrich.course_description_%' or key in ('enrich.course_text_items_per_day', 'reading.answer_tokens.course_text')));

-- 2 Enrich fields: preview and start (Pipeline Operator) --------------------------------------------------------------------------------
select set_config('fx.uid', '90000000-0000-0000-0000-000000000001', false), set_config('fx.rank', '4', false);
select pg_temp.ok('2a preview: description missing in P1 = 12 active courses without one (C12 holds one, C14 archived)',
  (select (f->>'missing')::int = 12 from jsonb_array_elements(public.admin_enrich_fields('preview', '{"provider_ids":["10000000-0000-0000-0000-000000000001"],"fields":["description","deadline"]}')->'fields') f where f->>'field' = 'description'));
select pg_temp.ok('2b preview: deadline missing in P1 = courses with active intakes and none dated (C01, C02, C03, C05)',
  (select (f->>'missing')::int = 4 from jsonb_array_elements(public.admin_enrich_fields('preview', '{"provider_ids":["10000000-0000-0000-0000-000000000001"],"fields":["description","deadline"]}')->'fields') f where f->>'field' = 'deadline'));
do $$ declare r jsonb := public.admin_enrich_fields('start', '{"provider_ids":["10000000-0000-0000-0000-000000000001"],"fields":["description","deadline"],"reason":"fixture manual run"}'); begin
  perform pg_temp.ok('2c start: one item per course and missing field (12 + 4)', (r->>'items')::int = 16, r::text);
  perform pg_temp.ok('2d start: the task is an ordinary Enrich fields task with both fields, scraper off', exists (select 1 from pipeline.admin_jobs j where j.id = (r->>'job_id')::uuid and j.kind = 'enrich_fields'
     and j.args->'fields' @> '["description","deadline"]'::jsonb and jsonb_array_length(j.args->'fields') = 2 and (j.args->>'scraper')::boolean = false));
  delete from pipeline.field_enrich_items where job_id = (r->>'job_id')::uuid;  -- fixture tidy-up (local only)
  update pipeline.admin_jobs set state = 'done' where id = (r->>'job_id')::uuid;
end $$;

-- 3 the standing gap queue: stored page only, the daily cap per field ---------------------------------------------------------------------
select set_config('fx.uid', '', false), set_config('fx.rank', '', false);
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by)
values ('pipeline', 'gaps.items_per_run', 'g', 'h', 'number', '30000', 1000, 200000, 'items', 105, 's', 'u') on conflict do nothing;
update pipeline.platform_toolset_settings set value = '5' where key = 'enrich.course_text_items_per_day';
do $$ declare r jsonb := security.field_gap_queue_tick_v1(); v_job uuid := (r->>'job_id')::uuid; begin
  perform pg_temp.ok('3a gap queue: started', r->>'queue' = 'started', r::text);
  perform pg_temp.ok('3b gap queue: at most the day''s cap of description items (5), none for C13 (no stored page), C14 (archived), C31 (unpublished), C11 (no proof), C12 (held)',
    (select count(*) = 5 from pipeline.field_enrich_items where job_id = v_job and field = 'description')
    and not exists (select 1 from pipeline.field_enrich_items where job_id = v_job and field in ('description', 'deadline') and course_id in ('20000000-0000-0000-0000-000000000013', '20000000-0000-0000-0000-000000000014',
                    '20000000-0000-0000-0000-000000000031', '20000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000012')),
    (select string_agg(course_id::text, ',') from pipeline.field_enrich_items where job_id = v_job and field = 'description'));
  perform pg_temp.ok('3c gap queue: deadline items for courses with undated active intakes and a stored page (C01, C02, C03, C05, C21; not C04)',
    (select count(*) = 5 from pipeline.field_enrich_items where job_id = v_job and field = 'deadline')
    and not exists (select 1 from pipeline.field_enrich_items where job_id = v_job and field = 'deadline' and course_id = '20000000-0000-0000-0000-000000000004'));
  update pipeline.admin_jobs set state = 'done' where id = v_job;
end $$;
do $$ declare r jsonb := security.field_gap_queue_tick_v1(); begin
  perform pg_temp.ok('3d gap queue: the next run the same day adds no description or deadline item (the cap is used)',
    not exists (select 1 from pipeline.field_enrich_items e where e.job_id = (r->>'job_id')::uuid and e.field in ('description', 'deadline')), r::text);
  update pipeline.admin_jobs set state = 'done' where id = (r->>'job_id')::uuid;
end $$;
update pipeline.field_enrich_items set state = 'skipped', reason = 'fixture: settled' where state = 'queued';

-- items for the record tests (one task, as the slice leaves them: state ai, the bound page's copy)
insert into pipeline.admin_jobs(id, kind, state, args) values ('50000000-0000-0000-0000-000000000001', 'enrich_fields', 'running', '{"fields":["description","deadline"]}');
create function pg_temp.item(p_course text, p_field text) returns bigint language plpgsql as $$
declare v bigint;
begin
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, evidence_id)
  select '50000000-0000-0000-0000-000000000001', c.provider_id, c.id, p_field, 'ai', 'ai_stored', g.evidence_id
    from catalogue.courses c join pipeline.coverage_course_pages g on g.course_id = c.id where c.id = ('20000000-0000-0000-0000-0000000000' || p_course)::uuid
  on conflict (job_id, provider_id, course_id, field) do update set state = 'ai', value = null, reason = null
  returning id into v;
  return v;
end $$;

-- 4 course description: checks ---------------------------------------------------------------------------------------------------------
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('01', 'description'), '[]', false)));
select pg_temp.ok('4a not about the course: skipped as not stated (and the usual no-value flag)',
  pg_temp.last() = '{"not_stated": 1}'
  and (select state = 'skipped' and reason = 'the page does not state it' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000001' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001')
  and exists (select 1 from pipeline.fx_flags where course_id = '20000000-0000-0000-0000-000000000001' and field = 'description'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('02', 'description'), jsonb_build_array(pg_temp.s(repeat('The course covers accounting practice in depth. ', 16), repeat('The course covers accounting practice in depth. ', 16))))));
select pg_temp.ok('4b too long: held whole, never cut (length)',
  pg_temp.last() = '{"held": 1}'
  and (select reason like 'held: length:%' and length(value->'sentences'->0->>'text') > 700 from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000002' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('03', 'description'), jsonb_build_array(pg_temp.s('This world-class course teaches nursing practice across hospital and community settings for registered nurses.',
     'This course teaches nursing practice across hospital and community settings for registered nurses.')))));
select pg_temp.ok('4c a marketing word that is not in the quote: held',
  pg_temp.last() = '{"held": 1}'
  and (select reason like 'held: unsupported_marketing:%' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000003' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('04', 'description'), jsonb_build_array(pg_temp.s('The course teaches civil engineering design, construction methods and project management across',
     'The course teaches civil engineering design, construction methods and project management across')))));
select pg_temp.ok('4d a fragment: held (incomplete_sentence)',
  pg_temp.last() = '{"held": 1}'
  and (select reason like 'held: incomplete_sentence:%' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000004' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('05', 'description'), jsonb_build_array(pg_temp.s('The course teaches data science methods and statistical computing for analysts.',
     'The course teaches data science methods and statistical computing for analysts.', false)))));
select pg_temp.ok('4e a quote that is not on the page: held',
  pg_temp.last() = '{"held": 1}'
  and (select reason like 'held: quote_not_on_page:%' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000005' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('12', 'description'), jsonb_build_array(pg_temp.s('The course teaches marine biology through field work and laboratory study of coastal ecosystems.',
     'The course teaches marine biology through field work and laboratory study of coastal ecosystems.')))));
select pg_temp.ok('4f a course already holding a description is never overwritten',
  pg_temp.last() = '{"already": 1}'
  and (select description = 'Held already.' from catalogue.courses where id = '20000000-0000-0000-0000-000000000012'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('22', 'description'), jsonb_build_array(pg_temp.s('The course teaches hospitality management through work placements and practical classes.',
     'The course teaches hospitality management through work placements and practical classes.')))));
select pg_temp.ok('4g the page proof decides by country: a CRICOS proof is not admitted in NZ',
  pg_temp.last() = '{"not_admitted": 1}');
do $$ declare v bigint := pg_temp.item('06', 'description'); begin
  update pipeline.coverage_course_pages set evidence_id = '30000000-0000-0000-0000-000000000007' where course_id = '20000000-0000-0000-0000-000000000006';
  perform pg_temp.ok('4h only the course''s own bound page: a reading of a copy no longer bound is not admitted',
    public.svc_enrich_ai_record(pg_temp.desc_read(v, jsonb_build_array(pg_temp.s('The course teaches architecture and design studio practice for future architects.',
      'The course teaches architecture and design studio practice for future architects.')))) = '{"not_admitted": 1}');
  update pipeline.coverage_course_pages set evidence_id = '30000000-0000-0000-0000-000000000006' where course_id = '20000000-0000-0000-0000-000000000006';
end $$;
insert into pipeline.manual_locks values ('course', '20000000-0000-0000-0000-000000000010', 'description');
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('10', 'description'), jsonb_build_array(pg_temp.s('The course teaches law through case study and moot court practice for future lawyers.',
     'The course teaches law through case study and moot court practice for future lawyers.')))));
select pg_temp.ok('4i locked by hand: skipped',
  pg_temp.last() = '{"locked": 1}');

-- 5 Layer 4 on first admission ----------------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set value = '2' where key = 'enrich.course_description_review_first';
update pipeline.platform_toolset_settings set value = '2' where key = 'enrich.course_description_pending_max';
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('06', 'description'), jsonb_build_array(
     pg_temp.s('The Bachelor of Architecture teaches design studio practice, building technology and architectural history.', 'The Bachelor of Architecture teaches design studio practice, building technology and architectural history.'),
     pg_temp.s('It prepares graduates for registration pathways as architects.', 'prepares graduates for registration pathways as architects')))));
select pg_temp.ok('5a a passing description of an untrusted provider goes to Layer 4 with a plain reason; the item waits in review',
  pg_temp.last() = '{"review": 1}'
  and exists (select 1 from pipeline.layer4_review_items r where r.entity_id = '20000000-0000-0000-0000-000000000006' and r.field_code = 'course_description_first_read' and r.status = 'pending'
              and r.escalation_reason like 'Course description read from the course''s own page.%' and jsonb_array_length(r.proposed_value->'sentences') = 2
              and r.evidence_id = '30000000-0000-0000-0000-000000000006')
  and (select description is null from catalogue.courses where id = '20000000-0000-0000-0000-000000000006'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('07', 'description'), jsonb_build_array(
     pg_temp.s('The Bachelor of Music teaches performance, composition and music theory through ensemble work.', 'The Bachelor of Music teaches performance, composition and music theory through ensemble work.')))));
select pg_temp.ok('5b a second one goes to Layer 4',
  pg_temp.last() = '{"review": 1}');
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('08', 'description'), jsonb_build_array(
     pg_temp.s('The Bachelor of Pharmacy teaches pharmaceutical science, dispensing practice and patient care.', 'The Bachelor of Pharmacy teaches pharmaceutical science, dispensing practice and patient care.')))));
select pg_temp.ok('5c over the waiting limit: held with its reading kept (no AI spent again)',
  pg_temp.last() = '{"held_first_admission": 1}'
  and (select value->>'text' like 'The Bachelor of Pharmacy%' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000008' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('09', 'description'), jsonb_build_array(
     pg_temp.s('The Bachelor of Music teaches performance, composition and music theory through ensemble work.', 'The Bachelor of Music teaches performance, composition and music theory through ensemble work.')))));
select pg_temp.ok('5d boilerplate: the same words as another course''s waiting description are held',
  pg_temp.last() = '{"held": 1}'
  and (select reason like 'held: duplicate_other_course:%' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000009' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.ok('5e the inbox lists it with the description review, under the course''s title',
  exists (select 1 from security.layer4_inbox_items_v1() i where i.kind = 'provider_description' and i.subject = 'Course 6' and i.detail->>'field_code' = 'course_description_first_read'
          and i.provider_id = '10000000-0000-0000-0000-000000000001'));
select set_config('fx.uid', '90000000-0000-0000-0000-000000000002', false), set_config('fx.rank', '3', false);
do $$ begin
  perform security.layer4_review_decide_impl((select id from pipeline.layer4_review_items where entity_id = '20000000-0000-0000-0000-000000000006'), 'edit_and_approve', 'changing words', '{"description":"Changed."}');
  perform pg_temp.ok('5f an edited description is refused (approved as read only)', false);
exception when others then perform pg_temp.ok('5f an edited description is refused (approved as read only)', sqlerrm like 'a description is approved as read%', sqlerrm);
end $$;
select pg_temp.rec(security.layer4_review_decide_impl((select id from pipeline.layer4_review_items where entity_id = '20000000-0000-0000-0000-000000000006'), 'approve', 'read against the page'));
select pg_temp.ok('5g approve: the description is written to catalogue.courses.description, the item is filled, a search refresh is asked',
  (pg_temp.last() ->> 'status') = 'approved'
  and (select description like 'The Bachelor of Architecture teaches%It prepares graduates%' from catalogue.courses where id = '20000000-0000-0000-0000-000000000006')
  and (select state = 'filled' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000006' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001')
  and exists (select 1 from search.refresh_requests where requested_by = 'AI reader (course description, deadline)' and processed_at is null)
  and not security.course_description_trusted_v1('10000000-0000-0000-0000-000000000001'));
select pg_temp.rec(security.layer4_review_decide_impl((select id from pipeline.layer4_review_items where entity_id = '20000000-0000-0000-0000-000000000007'), 'approve', 'read against the page'));
select pg_temp.ok('5h the second approval makes the provider trusted and admits the held reading (C08)',
  (pg_temp.last() ->> 'status') = 'approved'
  and security.course_description_trusted_v1('10000000-0000-0000-0000-000000000001')
  and (select description like 'The Bachelor of Pharmacy%' from catalogue.courses where id = '20000000-0000-0000-0000-000000000008')
  and (select state = 'filled' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000008' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001'));
select set_config('fx.uid', '', false), set_config('fx.rank', '', false);
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('03', 'description'), jsonb_build_array(
     pg_temp.s('This course teaches nursing practice across hospital and community settings for registered nurses.', 'This course teaches nursing practice across hospital and community settings for registered nurses.')))));
select pg_temp.ok('5i a trusted provider''s passing description is admitted without a person',
  pg_temp.last() = '{"filled": 1}'
  and (select description like 'This course teaches nursing%' from catalogue.courses where id = '20000000-0000-0000-0000-000000000003'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('02', 'description'), jsonb_build_array(pg_temp.s('The best accounting course teaches financial reporting and audit practice to students.',
     'The accounting course teaches financial reporting and audit practice to students.')))));
select pg_temp.ok('5j a trusted provider''s description that fails a check is still held',
  pg_temp.last() = '{"held": 1}');
-- a rejection: the provider goes back to Layer 4 (C21 is NZ: its own provider, untrusted; first reading waits, then is rejected)
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.desc_read(pg_temp.item('21', 'description'), jsonb_build_array(
     pg_temp.s('The Diploma in Cookery teaches professional kitchen skills, menu planning and food safety.', 'The Diploma in Cookery teaches professional kitchen skills, menu planning and food safety.')))));
select pg_temp.ok('5k NZ: a passing description of an untrusted provider goes to Layer 4',
  pg_temp.last() = '{"review": 1}');
select set_config('fx.uid', '90000000-0000-0000-0000-000000000002', false), set_config('fx.rank', '3', false);
select pg_temp.rec(security.layer4_review_decide_impl((select id from pipeline.layer4_review_items where entity_id = '20000000-0000-0000-0000-000000000021'), 'reject', 'not about this course'));
select pg_temp.ok('5l reject: nothing is written; the item is skipped with the decision (asked again only after the recheck days)',
  (pg_temp.last() ->> 'status') = 'rejected'
  and (select description is null from catalogue.courses where id = '20000000-0000-0000-0000-000000000021')
  and (select state = 'skipped' and reason = 'not admitted in Layer 4 (rejected)' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000021' and field = 'description' and job_id = '50000000-0000-0000-0000-000000000001')
  and not exists (select 1 from pipeline.fx_flags where course_id = '20000000-0000-0000-0000-000000000021'));
select set_config('fx.uid', '', false), set_config('fx.rank', '', false);
-- a rejection among the latest decisions makes a trusted provider untrusted again
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, decided_at, proposed_value)
values ('course', '20000000-0000-0000-0000-000000000005', 'course_description_first_read', 'rejected', now() + interval '1 minute', '{}');
select pg_temp.ok('5m a rejection among the provider''s latest decisions sends its descriptions back to Layer 4', not security.course_description_trusted_v1('10000000-0000-0000-0000-000000000001'));
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value) values ('60000000-0000-0000-0000-000000000001', 'course', '20000000-0000-0000-0000-000000000001', 'delivery_mode', '"online"');
select set_config('fx.uid', '90000000-0000-0000-0000-000000000002', false), set_config('fx.rank', '3', false);
select pg_temp.rec(security.layer4_review_decide_impl('60000000-0000-0000-0000-000000000001', 'approve', 'fixture scalar', null));
select pg_temp.ok('5n other Layer 4 items take their own paths (a course scalar item still goes to the scalar resolver)', pg_temp.last()->>'status' = 'approved'
  and (select final_value = '"online"' from pipeline.layer4_decisions where review_item_id = '60000000-0000-0000-0000-000000000001'));
select set_config('fx.uid', '', false), set_config('fx.rank', '', false);

-- 6 application deadline -------------------------------------------------------------------------------------------------------------
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('01', 'deadline'), '[{"intake":"February 2027 intake","kind":"date","date":"2026-11-30","quote":"Applications for the February 2027 intake close 30 November 2026","on_page":true},
                                                                              {"intake":"July","kind":"rolling","date":null,"quote":"July applications are assessed as they are received","on_page":true}]')));
select pg_temp.ok('6a a date tied to the February 2027 intake is admitted to that intake only; July rolling is kept on the item, not written',
  pg_temp.last() = '{"filled": 1}'
  and (select application_deadline = '2026-11-30' from catalogue.course_intakes where id = '40000000-0000-0000-0000-000000000011')
  and (select application_deadline is null from catalogue.course_intakes where id = '40000000-0000-0000-0000-000000000012')
  and (select value->>'applied' = '1' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000001' and field = 'deadline' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('02', 'deadline'), '[{"intake":null,"kind":"date","date":"2026-12-15","quote":"Closing date: 15/12/2026","on_page":true}]')));
select pg_temp.ok('6b one deadline for the course and one active intake: admitted (numeric date in the quote)',
  pg_temp.last() = '{"filled": 1}'
  and (select application_deadline = '2026-12-15' from catalogue.course_intakes where id = '40000000-0000-0000-0000-000000000021'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('03', 'deadline'), '[{"intake":null,"kind":"date","date":"2026-11-30","quote":"Applications close 30 November 2026","on_page":true}]')));
select pg_temp.ok('6c one deadline for the course and two intakes: held (not tied to one intake)',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select reason = 'held: not_tied_to_one_intake' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000003' and field = 'deadline' and job_id = '50000000-0000-0000-0000-000000000001')
  and not exists (select 1 from catalogue.course_intakes where course_id = '20000000-0000-0000-0000-000000000003' and application_deadline is not null));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('05', 'deadline'), '[{"intake":"Semester 1","kind":"date","date":"2026-11-30","quote":"Semester 1 applications close 30 November","on_page":true}]')));
select pg_temp.ok('6d a year not printed in the quote is never assumed (date_not_in_quote)',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select reason = 'held: date_not_in_quote' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000005' and field = 'deadline' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('05', 'deadline'), '[{"intake":"Semester One 2027","kind":"date","date":"2026-11-30","quote":"Semester One 2027 applications close on 30 November 2026","on_page":true}]')));
select pg_temp.ok('6e Semester one wording matches the Semester 1 intake',
  pg_temp.last() = '{"filled": 1}'
  and (select application_deadline = '2026-11-30' from catalogue.course_intakes where id = '40000000-0000-0000-0000-000000000051'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('01', 'deadline'), '[{"intake":"July 2027","kind":"date","date":"2027-08-01","quote":"July 2027 intake: applications close 1 August 2027","on_page":true}]')));
select pg_temp.ok('6f a deadline after the intake starts is held (outside_intake_window)',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select application_deadline is null from catalogue.course_intakes where id = '40000000-0000-0000-0000-000000000012'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('04', 'deadline'), '[{"intake":"February","kind":"date","date":"2026-11-01","quote":"February 2027: applications close 1 November 2026","on_page":true}]')));
select pg_temp.ok('6g a deadline held already is never overwritten',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select application_deadline = '2026-12-01' from catalogue.course_intakes where id = '40000000-0000-0000-0000-000000000041'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('03', 'deadline'), '[{"intake":null,"kind":"rolling","date":null,"quote":"Applications are open all year","on_page":true}]')));
select pg_temp.ok('6h rolling only: kept on the item with a plain reason, nothing written',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select reason = 'the page says applications are rolling (no date to hold)' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000003' and field = 'deadline' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('03', 'deadline'), '[{"intake":"Summer school","kind":"date","date":"2026-10-01","quote":"Summer school applications close 1 October 2026","on_page":true}]')));
select pg_temp.ok('6i an intake the page names that the course does not have: held (intake_not_matched)',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select reason = 'held: intake_not_matched' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000003' and field = 'deadline' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('03', 'deadline'), '[]')));
select pg_temp.ok('6j not stated: skipped as not stated',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select reason = 'the page does not state it' from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000003' and field = 'deadline' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('21', 'deadline'), '[{"intake":"February 2027","kind":"date","date":"2026-11-30","quote":"February 2027: close 30 November 2026","on_page":true},
                                                                               {"intake":"February 2027","kind":"date","date":"2026-12-07","quote":"February 2027 late applications: 7 December 2026","on_page":true}]')));
select pg_temp.ok('6k two different dates for one intake: held (conflicting_dates)',
  pg_temp.last() = '{"not_admitted": 1}'
  and (select application_deadline is null from catalogue.course_intakes where id = '40000000-0000-0000-0000-000000000211'));
insert into pipeline.manual_locks values ('course', '20000000-0000-0000-0000-000000000003', 'intake');
select pg_temp.rec(public.svc_enrich_ai_record(pg_temp.dl_read(pg_temp.item('03', 'deadline'), '[{"intake":"February","kind":"date","date":"2026-11-30","quote":"February 2027 intake closes 30 November 2026","on_page":true}]')));
select pg_temp.ok('6l an intake locked by hand: skipped',
  pg_temp.last() = '{"locked": 1}');
select pg_temp.ok('6m the intake match: month, period words, year', security.course_deadline_intake_match_v1('February', 2027, 'February 2027 intake')
  and not security.course_deadline_intake_match_v1('February', 2027, 'February 2028 intake') and security.course_deadline_intake_match_v1('Semester 1', 2027, 'semester one')
  and not security.course_deadline_intake_match_v1('Semester 1', 2027, 'Semester 2') and not security.course_deadline_intake_match_v1('July', null, 'February'));
select pg_temp.ok('6n the date in the quote: name, numeric and ISO forms; a missing year or day is refused', security.course_deadline_in_quote_v1('2026-11-30', 'closes 30th November 2026')
  and security.course_deadline_in_quote_v1('2026-11-30', 'by 30/11/2026') and security.course_deadline_in_quote_v1('2026-11-30', '2026-11-30')
  and not security.course_deadline_in_quote_v1('2026-11-30', 'closes 30 November') and not security.course_deadline_in_quote_v1('2026-11-30', 'closes November 2026'));

-- 7 errors and retries are the existing paths ------------------------------------------------------------------------------------------
select pg_temp.rec(public.svc_enrich_ai_record(jsonb_build_array(jsonb_build_object('item_id', pg_temp.item('09', 'deadline'), 'error', 'held_partial: output_truncated: course_text reached reading.answer_tokens.course_text (1500)', 'cost', 0.002))));
select pg_temp.ok('7a a worker error leaves the item for another try (the existing error path)',
  pg_temp.last() = '{"error": 1}'
  and (select state = 'ai' and cost_usd = 0.002 from pipeline.field_enrich_items where course_id = '20000000-0000-0000-0000-000000000009' and field = 'deadline' and job_id = '50000000-0000-0000-0000-000000000001'));
select pg_temp.rec(public.svc_enrich_ai_record(jsonb_build_array(jsonb_build_object('item_id', pg_temp.item('09', 'entry_requirements'), 'value', '{}'))));
select pg_temp.ok('7b other fields still take their own paths (entry requirements)',
  pg_temp.last() = '{"entry_stub": 1}');

-- 8 coverage and Stalled fields -------------------------------------------------------------------------------------------------------
select pg_temp.rec(to_jsonb(security.enrich_coverage_snapshot_v1()));
select pg_temp.ok('8a the Enrich fields coverage snapshot counts held descriptions and deadlines',
  pg_temp.last()::int > 0
  and (select filled = 5 from pipeline.enrich_coverage_snapshots where country_code = 'AU' and field = 'description')
  and (select filled = 4 from pipeline.enrich_coverage_snapshots where country_code = 'AU' and field = 'deadline'),
  (select string_agg(country_code || ' ' || field || ' ' || filled, '; ') from pipeline.enrich_coverage_snapshots where field in ('description', 'deadline')));
insert into pipeline.field_coverage_daily values (current_date, 'AU', 'description', 100, 1, now()), (current_date, 'AU', 'deadline', 100, 0, now());
select pg_temp.ok('8b Stalled fields: no longer "no reader"; Fill now offered for both',
  (select count(*) = 2 and bool_and((x->>'can_fill')::boolean and x->>'reason' is distinct from 'no_reader') from jsonb_array_elements(security.field_stalled_v1()) x where x->>'field' in ('description', 'deadline')));
