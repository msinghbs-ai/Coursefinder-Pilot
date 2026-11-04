-- Run now cases (CF-247, Platform Admin 4 Nov 2026 20:05 §1-§5): a fixed cohort picked by the job's own plan, the governed start, refusals,
-- one run at a time, the record, the website read-back and the scheduled job unchanged. run.sh puts the intake-dates fixture's helpers
-- (pg_temp.course, intake, row, u, y, ok) in front of this file. Each case raises "PASS ..." or stops with an error. No live data.
\set ON_ERROR_STOP 1
insert into security.roles values ('platform_admin', 6, 'active'), ('viewer', 2, 'active');
insert into security.user_roles values (pg_temp.u('admin'), 'platform_admin', null), (pg_temp.u('viewer'), 'viewer', null);
update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';
update pipeline.platform_toolset_settings set value = to_jsonb(4) where toolset_key = 'pipeline' and key = 'run_now.pilot_cap';
update cron.job set active = true where jobname = 'intake-dates-apply';
-- six new courses on two providers; five eligible (one only gains year and start: rolling deadline), one locked by hand
select pg_temp.course('rn h1', 'harbour', 'harbour.edu.au', 'RN101', 'Master of Robotics', 'Semester 1'),
       pg_temp.course('rn h2', 'harbour', 'harbour.edu.au', 'RN102', 'Master of Geology', 'Commencing Semester 1'),
       pg_temp.course('rn h3', 'harbour', 'harbour.edu.au', 'RN103', 'Master of Music', 'Semester Two intake (July)'),
       pg_temp.course('rn b1', 'bay', 'bay.edu.au', 'RN201', 'Master of Law', 'Semester 1'),
       pg_temp.course('rn b2', 'bay', 'bay.edu.au', 'RN202', 'Master of Arts', 'Semester 1 start'),
       pg_temp.course('rn lock', 'harbour', 'harbour.edu.au', 'RN109', 'Master of Dance', 'Semester 1');
select pg_temp.intake('rn h1', 'March'), pg_temp.intake('rn h2', 'March'), pg_temp.intake('rn h3', 'July'), pg_temp.intake('rn b1', 'March'),
       pg_temp.intake('rn b2', 'March'), pg_temp.intake('rn lock', 'March');
insert into pipeline.manual_locks values ('course', pg_temp.u('rn lock'), 'intakes');
create table public.fixture_run_now(k text primary key, v jsonb);
-- institution types (ref.provider_types, Decision 258): Harbour, Bay and Inland are Australian universities
insert into ref.provider_types(code, name) values ('university', 'University'), ('other', 'Other');
update catalogue.providers set provider_type_id = (select id from ref.provider_types where code = 'university'), lifecycle_status = 'active';

-- 0 the scope (Platform Admin 4 Nov 2026 20:53): top Australian universities by active courses only; never widened ---------------------------
do $$
declare v jsonb;
begin
  update catalogue.providers set provider_type_id = (select id from ref.provider_types where code = 'other') where id = pg_temp.u('bay');
  v := security.run_now_cohort_create_v1('intake-dates-apply', pg_temp.u('admin'), 'scope: not a university');
  perform pg_temp.ok((v->>'members')::int = 3 and (v->>'courses_eligible')::int = 3 and not exists (select 1 from pipeline.run_now_cohort_members where cohort_id = (v->>'cohort_id')::uuid and provider_id = pg_temp.u('bay')),
                     'a provider whose institution type is not university is outside the scope; the cohort is smaller, not widened: ' || v::text);
  update catalogue.providers set provider_type_id = (select id from ref.provider_types where code = 'university') where id = pg_temp.u('bay');
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'run_now.cohort_top_au_universities';
  v := security.run_now_cohort_create_v1('intake-dates-apply', pg_temp.u('admin'), 'scope: top 1');
  perform pg_temp.ok(jsonb_array_length(v->'universities') = 1 and v->'universities'->0->>'provider_id' = pg_temp.u('harbour')::text
                     and (v->'universities'->0->>'active_courses')::int = (select count(*) from catalogue.courses where provider_id = pg_temp.u('harbour') and lifecycle_status = 'active')
                     and (v->'universities'->0->>'eligible_courses')::int = 3 and (v->>'members')::int = 3, 'top 1: the university with the most active courses, with its counts: ' || v::text);
  update pipeline.platform_toolset_settings set value = to_jsonb(10) where toolset_key = 'pipeline' and key = 'run_now.cohort_top_au_universities';
  raise notice 'PASS scope: top Australian universities by active courses only; recorded with counts; a short scope gives a smaller cohort';
end $$;

-- 1 the cohort is picked by the job's own plan, never by hand ------------------------------------------------------------------------------
do $$
declare v jsonb; c uuid;
begin
  v := security.run_now_cohort_create_v1('intake-dates-apply', pg_temp.u('admin'), 'fixture pilot');
  c := (v->>'cohort_id')::uuid;
  insert into public.fixture_run_now values ('cohort', to_jsonb(c));
  perform pg_temp.ok((v->>'members')::int = 4 and (v->>'cap')::int = 4, 'cohort holds the cap: ' || v::text);
  perform pg_temp.ok((v->>'courses_eligible')::int = 5, 'denominator: five eligible courses (the locked one is not): ' || v::text);
  perform pg_temp.ok((v->>'providers_in_cohort')::int = 2, 'spread across providers');
  perform pg_temp.ok(not exists (select 1 from pipeline.run_now_cohort_members where cohort_id = c and course_id in (pg_temp.u('rn lock'), pg_temp.u('rn h3'))),
                     'the locked course is never picked; the course gaining fewest fields is left for the scheduler');
  perform pg_temp.ok((select bool_and(e->>'page_quote' <> '' and e->>'calendar_url' like 'https://%' and e->'planned'->>'start_date' is not null and e->>'start_quote' is not null)
                        from pipeline.run_now_cohort_members m, jsonb_array_elements(m.evidence) e where m.cohort_id = c), 'each member keeps its evidence at selection');
  perform pg_temp.ok((select selection->'skipped_by_reason' ? 'intakes locked by hand' from pipeline.run_now_cohorts where id = c), 'the selection records what was not eligible and why');
  perform pg_temp.ok((select count(*) from catalogue.course_intakes where course_id::text like '%' and start_date is not null and course_id in (select course_id from pipeline.run_now_cohort_members where cohort_id = c)) = 0,
                     'picking writes nothing to the catalogue');
  raise notice 'PASS cohort: picked by the plan, capped, spread, evidence recorded, nothing written';
end $$;

-- 2 refusals: allowlist, rank, reason, pause, switch, cap ---------------------------------------------------------------------------------
do $$
declare c jsonb := jsonb_build_object('cohort_id', (select v from public.fixture_run_now where k = 'cohort')); v jsonb; n int;
begin
  v := security.job_run_now_v1('coverage-admit-intakes', 'x', c, pg_temp.u('admin'));
  perform pg_temp.ok(v->>'refused' = 'job is not on the Run now list', 'not on the list: ' || v::text);
  v := security.job_run_now_v1('intake-dates-apply', 'x', c, pg_temp.u('viewer'));
  perform pg_temp.ok(v->>'refused' like 'requester rank 2 is below%', 'rank: ' || v::text);
  begin perform security.job_run_now_v1('intake-dates-apply', ' ', c, pg_temp.u('admin')); raise exception 'FAIL no reason accepted';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  update cron.job set active = false where jobname = 'intake-dates-apply';
  v := security.job_run_now_v1('intake-dates-apply', 'x', c, pg_temp.u('admin'));
  perform pg_temp.ok(v->>'refused' = 'job is paused', 'paused: ' || v::text);
  update cron.job set active = true where jobname = 'intake-dates-apply';
  update pipeline.platform_toolset_settings set value = to_jsonb(false) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';
  v := security.job_run_now_v1('intake-dates-apply', 'x', c, pg_temp.u('admin'));
  perform pg_temp.ok(v->>'refused' like 'job switch is off%', 'switch: ' || v::text);
  update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';
  update pipeline.platform_toolset_settings set value = to_jsonb(3) where toolset_key = 'pipeline' and key = 'run_now.pilot_cap';
  v := security.job_run_now_v1('intake-dates-apply', 'x', c, pg_temp.u('admin'));
  perform pg_temp.ok(v->>'refused' like 'cohort has 4 courses, over the cap of 3', 'cap: ' || v::text);
  update pipeline.platform_toolset_settings set value = to_jsonb(4) where toolset_key = 'pipeline' and key = 'run_now.pilot_cap';
  v := security.job_run_now_v1('intake-dates-apply', 'x', '{}', pg_temp.u('admin'));
  perform pg_temp.ok(v->>'refused' = 'a cohort_id is required', 'no cohort');
  select count(*) into n from pipeline.admin_jobs where kind = 'job_run_now' and state = 'cancelled' and outcome = 'refused' and requested_by is not null and reason <> '';
  perform pg_temp.ok(n = 6, 'each refusal is a recorded task: ' || n);
  perform pg_temp.ok((select count(*) from catalogue.course_intakes where start_date is not null and course_id in (pg_temp.u('rn h1'), pg_temp.u('rn b1'))) = 0, 'a refusal changes nothing');
  -- the signed-in entry: no session, refused
  begin perform public.admin_job_run_now_v1('intake-dates-apply', 'x', c); raise exception 'FAIL anonymous accepted';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  raise notice 'PASS refusals: list, rank, reason, pause, switch, cap, cohort, signed-in entry; each recorded, nothing changed';
end $$;
