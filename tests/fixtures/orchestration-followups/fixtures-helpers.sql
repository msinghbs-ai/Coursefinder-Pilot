-- Fixture helpers (orchestration follow-ups): providers with the IQ-00066 shape, a scholarship scan task of a plan step, an onboarding row,
-- course descriptions. Fixture data only.
create or replace function fx.reset2() returns void language plpgsql as $$
begin
  truncate pipeline.admin_job_events, pipeline.admin_jobs cascade;
  truncate pipeline.enrich_plan_runs, pipeline.scholarship_discovery_providers, pipeline.scholarship_page_candidates, pipeline.scholarship_listing_pages,
           pipeline.scholarship_pages, scholarship.scholarships, catalogue.providers, catalogue.courses, fx.ineligible, pipeline.provider_scholarship_search,
           pipeline.provider_onboarding, fx.stepped, pipeline.coverage_vendor_usage, pipeline.layer4_review_items, pipeline.provider_central_search;
end $$;

-- a provider (active courses, website, contacts, central pages searched) and its scholarship discovery row as on 3 Nov: mapped on 3 Oct,
-- next mapping p_next from now (null: no row); p_eligible false puts it below scholarship_min_courses
create or replace function fx.provider(p_eligible boolean, p_next interval, p_website text default 'https://www.example-college.edu.au') returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into catalogue.providers(id, website, phone, email, display_name) values (v, p_website, '03 9000 0000', 'info@example-college.edu.au', 'Example College ' || left(v::text, 4));
  insert into catalogue.courses(provider_id, duration_value, study_level_id, delivery_mode, primary_field_id, open_to_international)
    select v, 1, gen_random_uuid(), 'on_campus', gen_random_uuid(), true from generate_series(1, 3);
  insert into catalogue.course_campuses(course_id) select id from catalogue.courses where provider_id = v;
  insert into pipeline.provider_central_search(provider_id, state, searched_at) values (v, 'done', now() - interval '1 day');
  insert into pipeline.uni_adapters(provider_id, enabled, admit) values (v, true, true);
  if not p_eligible then insert into fx.ineligible values (v); end if;
  if p_next is not null then
    insert into pipeline.scholarship_discovery_providers(provider_id, status, attempts, next_discover_at, discovered_at, kept_count, website)
      values (v, 'mapped', 0, now() + p_next, now() - interval '31 days', 0, p_website);
  end if;
  return v;
end $$;

-- a running scholarship_provider_scan task started by an automatic plan, as scholarship_task_prepare_v1 leaves it (the discovery row pending,
-- attempts 0), nothing moved for p_stall; its plan run with the running step
create or replace function fx.scan(p_provider uuid, p_stall interval) returns uuid language plpgsql as $$
declare v_job uuid := gen_random_uuid(); v_run uuid := gen_random_uuid();
begin
  update pipeline.scholarship_discovery_providers set status = 'pending', attempts = 0, reason = 'on_demand', priority = 0 where provider_id = p_provider;
  insert into pipeline.admin_jobs(id, kind, lane, state, scope, args, cursor, created_at, started_at)
    values (v_job, 'scholarship_provider_scan', 'scholarships:scholarship_provider_scan:' || p_provider, 'running', p_provider::text,
            jsonb_build_object('providers', jsonb_build_array(p_provider), 'scholarship_ids', '[]'::jsonb, 'pages', 0, 'candidates', 0, 'plan_run', v_run, 'plan_mode', 'auto'),
            jsonb_build_object('last_done', 0, 'last_change_at', now() - p_stall), now() - p_stall - interval '1 minute', now() - p_stall);
  insert into pipeline.enrich_plan_runs(id, provider_id, mode, state, started_at, created_at, steps) values (v_run, p_provider, 'auto', 'running', now() - p_stall, now() - p_stall,
    jsonb_build_array(jsonb_build_object('step', 'scholarships', 'group', 'scholarships', 'status', 'running', 'ref', jsonb_build_object('kind', 'job', 'id', v_job),
                                         'started_at', now() - p_stall, 'est_credits', 20)));
  return v_job;
end $$;

-- a queued automatic plan with one pending scholarships step
create or replace function fx.plan_pending(p_provider uuid) returns uuid language plpgsql as $$
declare v_run uuid := gen_random_uuid();
begin
  insert into pipeline.enrich_plan_runs(id, provider_id, mode, state, steps) values (v_run, p_provider, 'auto', 'queued',
    jsonb_build_array(jsonb_build_object('step', 'scholarships', 'group', 'scholarships', 'status', 'pending', 'est_credits', 0)));
  return v_run;
end $$;
create or replace function fx.run(p uuid) returns pipeline.enrich_plan_runs language sql as $$ select * from pipeline.enrich_plan_runs where id = p $$;
create or replace function fx.steps_of(p uuid) returns text[] language sql as $$ select array(select x->>'step' from jsonb_array_elements((security.enrich_plan_v1(p))->'steps') x) $$;

-- an onboarding row of a provider
create or replace function fx.onb(p_website text, p_status text, p_stop text default null) returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid(); p uuid := gen_random_uuid();
begin
  insert into catalogue.providers(id, website) values (p, p_website);
  insert into catalogue.courses(provider_id) values (p);
  insert into pipeline.provider_onboarding(id, provider_id, status, stop_reason, note, result, updated_at, step_started_at)
    values (v, p, p_status, p_stop, 'Website known; finding course pages.', jsonb_build_object('website', p_website), now() - interval '1 minute', now() - interval '1 minute');
  return v;
end $$;
create or replace function fx.onb_row(p uuid) returns pipeline.provider_onboarding language sql as $$ select * from pipeline.provider_onboarding where id = p $$;
create or replace function fx.stepped_n(p uuid) returns bigint language sql as $$ select count(*) from fx.stepped where id = p $$;

-- course descriptions of one provider, and the answers the description check gives for a set of new texts (recorded before the migration)
create table if not exists fx.desc_answers (k int primary key, answer jsonb);
create or replace function fx.desc_cases() returns table(k int, course uuid, result jsonb) language plpgsql as $$
declare v_p uuid := '11111111-1111-1111-1111-111111111111'; v_c uuid := '22222222-2222-2222-2222-222222222222'; t text;
begin
  if not exists (select 1 from catalogue.providers where id = v_p) then
    insert into catalogue.providers(id, website) values (v_p, 'https://desc.example.edu.au');
    insert into catalogue.courses(id, provider_id) values (v_c, v_p);
    -- fixed ids, so the answers recorded before the migration name the same courses after a reset
    insert into catalogue.courses(id, provider_id, description, updated_at) select md5('desc' || z.n)::uuid, v_p, z.d, now() - make_interval(days => z.n) from (values
      (1, 'The Bachelor of Nursing prepares graduates for registered nursing practice in hospitals and community health settings.'),
      (2, 'Students study anatomy, physiology and clinical practice across three years with placements in partner hospitals.'),
      (3, 'Our Diploma of Business covers marketing, finance and leadership skills for small business owners.'),
      (4, '  '), (5, null), (6, 'A an of to be it.')) z(n, d);
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value)
      select 'course', id, 'course_description_first_read', 'pending', jsonb_build_object('description', 'Graduates of this Master of Teaching become qualified secondary teachers in two subject areas.')
        from catalogue.courses where provider_id = v_p and description is null;
  end if;
  foreach t in array array[
    'The Bachelor of Nursing prepares graduates for registered nursing practice in hospitals and community health settings.',
    'The Bachelor of Nursing prepares graduates for registered nursing practice in hospitals and in community health settings.',
    'Students study anatomy, physiology and clinical practice across three years with placements in our partner hospitals.',
    'Graduates of this Master of Teaching become qualified secondary teachers in two subject areas.',
    'This course teaches computer science, software engineering and data analysis through practical projects.',
    'An Ok to Be It of A an. Is is it so.'] loop
    k := coalesce(k, 0) + 1; course := v_c;
    result := jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(jsonb_build_object('text', t, 'quote', t, 'on_page', true)));
    return next;
  end loop;
end $$;
