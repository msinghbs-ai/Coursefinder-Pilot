-- Plan lifecycle fixtures (after the migration). Each case raises on a wrong result and says ok on a right one.
set client_min_messages = notice;
\set ON_ERROR_STOP 1
insert into security.fx_ranks values ('00000000-0000-0000-0000-00000000a006', 6), ('00000000-0000-0000-0000-00000000a004', 4), ('00000000-0000-0000-0000-00000000a003', 3);
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000a1', 'AU');
insert into pipeline.enrich_plan_control values (1, true, '00000000-0000-0000-0000-00000000a006', 'on', now());
insert into pipeline.field_register values ('duration', 'enrich');
create function pg_temp.pid(n int) returns uuid language sql immutable as $$ select ('00000000-0000-0000-0000-000000000' || lpad(n::text, 3, '0'))::uuid $$;
-- a university with n missing values and its plan's steps (site: other share; pages: course_search share; fields; scholarships: scholarships share)
create function pg_temp.uni(n int, missing int, steps text) returns void language sql as $$
  insert into catalogue.providers(id, country_id, canonical_name, website) values (pg_temp.pid(n), '00000000-0000-0000-0000-0000000000a1', 'Uni ' || n, 'https://u' || n || '.example');
  insert into security.fx_plan_steps values (pg_temp.pid(n), (select jsonb_agg(case x
      when 'site' then '{"step":"site","label":"Website","group":"other","est_credits":1,"est_usd":0}'::jsonb
      when 'pages' then '{"step":"pages","label":"Find course pages","group":"course_search","est_credits":5,"est_usd":0}'::jsonb
      when 'fields' then '{"step":"fields","label":"Fill missing fields","group":"reads","est_credits":0,"est_usd":0.01}'::jsonb
      when 'scholarships' then '{"step":"scholarships","label":"Scholarships","group":"scholarships","est_credits":3,"est_usd":0}'::jsonb end)
    from unnest(string_to_array(steps, ',')) x));
  insert into pipeline.course_attribute_coverage(provider_id, course_id, country_code, attribute, state)
  select pg_temp.pid(n), gen_random_uuid(), 'AU', 'duration', 'missing' from generate_series(1, missing);
$$;
-- a finished run of a university: mode, days ago, missing then, steps as "step~status[~note[~hours ago]]" separated by |
create function pg_temp.ran(n int, mode text, days numeric, missing int, steps text, state text default 'done') returns uuid language sql as $$
  insert into pipeline.enrich_plan_runs(provider_id, mode, state, steps, estimate, created_at, finished_at, reason, requested_by)
  values (pg_temp.pid(n), mode, state, (select jsonb_agg(jsonb_build_object('step', split_part(x, '~', 1), 'status', split_part(x, '~', 2),
            'note', nullif(split_part(x, '~', 3), ''),
            'group', case split_part(x, '~', 1) when 'pages' then 'course_search' when 'scholarships' then 'scholarships' when 'site' then 'other' else 'reads' end,
            'est_credits', 5,
            'finished_at', now() - make_interval(hours => coalesce(nullif(split_part(x, '~', 4), '')::int, (days * 24)::int))))
          from unnest(string_to_array(steps, '|')) x),
          jsonb_build_object('missing', missing), now() - make_interval(secs => days * 86400), now() - make_interval(secs => days * 86400) + interval '1 hour',
          'r', '00000000-0000-0000-0000-00000000a006')
  returning id $$;
create function pg_temp.queued() returns text language sql as $$
  select coalesce(string_agg(right(provider_id::text, 3), ',' order by provider_id), '') from pipeline.enrich_plan_runs where state = 'queued' $$;
create function pg_temp.setv(k text, v text) returns void language sql as $$ update pipeline.platform_toolset_settings set value = v::jsonb where key = k $$;

-- F. fair order (plans.fair_order): never-planned first, then due longest-waiting first; off keeps most-missing first ---------------------------
select pg_temp.uni(118, 1, 'site'), pg_temp.uni(119, 100, 'site'), pg_temp.uni(120, 200, 'site');
select pg_temp.ran(119, 'auto', 30, 100, 'site~done'), pg_temp.ran(120, 'auto', 16, 200, 'site~done');
do $$
declare r jsonb;
begin
  perform pg_temp.setv('plans.auto_per_run', '1');
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '120' then raise exception 'F1: off should take the most missing (120), got %', pg_temp.queued(); end if;
  update pipeline.enrich_plan_runs set state = 'cancelled' where state = 'queued';
  delete from pipeline.enrich_plan_runs where state = 'cancelled' and provider_id = pg_temp.pid(120);
  perform pg_temp.setv('plans.fair_order', '1');
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '118' then raise exception 'F2: fair should take the never-planned (118) first, got %', pg_temp.queued(); end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '119' then raise exception 'F3: fair should take the longest-waiting due (119, 30 days) before 120 (16 days, more missing), got %', pg_temp.queued(); end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  perform pg_temp.setv('plans.fair_order', '0'); perform pg_temp.setv('plans.auto_per_run', '20');
  update catalogue.providers set publication_status = 'draft' where id in (pg_temp.pid(118), pg_temp.pid(119), pg_temp.pid(120));
  raise notice 'ok F1-F3 fair order off: most missing first (120); on: never-planned (118), then the longest-waiting due (119) before a larger, newer one (120)';
end $$;

-- A. re-planning triggers -------------------------------------------------------------------------------------------------------------------
select pg_temp.uni(101, 30, 'site,pages,fields'), pg_temp.uni(102, 30, 'site,pages,fields'), pg_temp.uni(103, 30, 'site,pages,fields'),
       pg_temp.uni(104, 30, 'site,scholarships'), pg_temp.uni(105, 30, 'site,pages'), pg_temp.uni(106, 30, 'site,pages'), pg_temp.uni(107, 30, 'site,pages'),
       pg_temp.uni(108, 30, 'site,pages'), pg_temp.uni(109, 30, 'site,pages'), pg_temp.uni(110, 30, 'site,pages'), pg_temp.uni(111, 30, 'site,pages'),
       pg_temp.uni(112, 30, 'site'), pg_temp.uni(113, 30, 'site'), pg_temp.uni(114, 30, 'site'), pg_temp.uni(115, 30, 'site');
insert into pipeline.admin_jobs(id, kind, state, requested_by) values
  ('00000000-0000-0000-0000-00000000b108', 'course_page_find', 'queued', '00000000-0000-0000-0000-00000000a006'),
  ('00000000-0000-0000-0000-00000000b109', 'course_page_find', 'failed', '00000000-0000-0000-0000-00000000a006');
select pg_temp.ran(101, 'auto', 5, 30, 'site~done|pages~done|fields~done'),                                   -- E1 new evidence (below)
       pg_temp.ran(102, 'auto', 5, 30, 'site~done|pages~done|fields~done'),                                   -- E2 evidence older than the run
       pg_temp.ran(103, 'auto', 5, 30, 'site~done|pages~skipped~no room in the course_search share for 48 hours|fields~done'),  -- R1 share has room again
       pg_temp.ran(104, 'auto', 5, 30, 'site~done|scholarships~skipped~no room in the scholarships share for 48 hours'),          -- R2 share still empty
       pg_temp.ran(105, 'auto', 5, 30, 'site~done|pages~failed~this task is already running; see Task manager~7'),             -- R3 transient, 7 h ago
       pg_temp.ran(106, 'auto', 5, 30, 'site~done|pages~failed~Not started: this university is not a search target~7'),        -- R4 waits for a change
       pg_temp.ran(107, 'auto', 5, 30, 'site~done|pages~failed~this task is already running~1'),                                -- R5 transient, 1 h ago
       pg_temp.ran(108, 'auto', 5, 30, 'site~done|pages~timed_out'),                                                            -- R6 task still open
       pg_temp.ran(109, 'auto', 5, 30, 'site~done|pages~timed_out'),                                                            -- R7 task failed
       pg_temp.ran(110, 'auto', 9, 30, 'pages~failed~already running~200'), pg_temp.ran(110, 'auto', 7, 30, 'pages~failed~already running~150'),
       pg_temp.ran(110, 'auto', 5, 30, 'site~done|pages~failed~already running~7'),                                             -- R8 third unfinished end
       pg_temp.ran(111, 'auto', 5, 30, 'site~done|pages~failed~already running~7', 'cancelled'),                               -- R9 a person cancelled
       pg_temp.ran(112, 'auto', 20, 30, 'site~done'),                                                                           -- due
       pg_temp.ran(114, 'auto', 20, 30, 'site~done'), pg_temp.ran(114, 'manual', 1, 30, 'site~done'),                          -- due, but a Run now yesterday
       pg_temp.ran(115, 'auto', 5, 30, 'site~done');                                                                            -- evidence, nothing to do
update pipeline.enrich_plan_runs set steps = jsonb_set(steps, '{1,ref}', '{"kind":"job","id":"00000000-0000-0000-0000-00000000b108"}') where provider_id = pg_temp.pid(108);
update pipeline.enrich_plan_runs set steps = jsonb_set(steps, '{1,ref}', '{"kind":"job","id":"00000000-0000-0000-0000-00000000b109"}') where provider_id = pg_temp.pid(109);
insert into security.fx_budget values ('sch_scrape', 0);
insert into pipeline.coverage_course_pages(course_id, provider_id, evidence_id, read_status, read_at) values
  (gen_random_uuid(), pg_temp.pid(101), gen_random_uuid(), 'read', now() - interval '1 day'),
  (gen_random_uuid(), pg_temp.pid(102), gen_random_uuid(), 'read', now() - interval '6 days'),
  (gen_random_uuid(), pg_temp.pid(102), null, 'read', now() - interval '1 day'),            -- read, but no stored evidence: not verified
  (gen_random_uuid(), pg_temp.pid(115), gen_random_uuid(), 'read', now() - interval '1 day');
do $$
declare r jsonb; v text;
begin
  -- A1 as shipped: only the never-planned (113) and due (112) universities; 114 waits for its Run now of yesterday; nothing early
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '112,113' or (r->>'replanned')::int <> 0 then raise exception 'A1: shipped should plan 112 and 113 only, got % (%)', pg_temp.queued(), r; end if;
  if (select estimate ? 'fingerprint' and estimate ? 'inputs' from pipeline.enrich_plan_runs where state = 'queued' and provider_id = pg_temp.pid(112)) is not true then
    raise exception 'A1: the run does not keep its input fingerprint'; end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  raise notice 'ok A1 as shipped: never-planned 113 and due 112 planned (with their input fingerprint); 114 (Run now yesterday) waits; nothing re-planned early';
  -- A2 evidence on (re-planning at 20 an hour): 101 (page read with evidence after its plan) only; its done steps are not redone except Fill missing fields
  perform pg_temp.setv('plans.replan_per_hour', '20'); perform pg_temp.setv('plans.replan_on_evidence', '1');
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '101' then raise exception 'A2: evidence should re-plan 101 only, got % (%)', pg_temp.queued(), r; end if;
  select string_agg(s->>'step', ',') into v from pipeline.enrich_plan_runs, jsonb_array_elements(steps) s where state = 'queued';
  if v <> 'fields' then raise exception 'A2: only Fill missing fields should run again, got %', v; end if;
  if not exists (select 1 from pipeline.enrich_plan_runs where state = 'queued' and estimate->'replan_why' = '["evidence"]' and estimate ? 'replan_of'
                   and reason like 'Automatic enrichment plan (new verified evidence since the last plan): %') then raise exception 'A2: the re-plan does not say why'; end if;
  if (r->>'nothing_to_do')::int <> 1 or not exists (select 1 from pipeline.enrich_plan_noop where provider_id = pg_temp.pid(115)) then
    raise exception 'A2: 115 (new evidence, but its only step is done) should be recorded as nothing to do (%)', r; end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  r := security.enrich_plan_auto_v1();
  if (r->>'nothing_to_do')::int <> 0 or (r->>'started')::int <> 0 then raise exception 'A3: 115 should not be evaluated again with unchanged inputs (%)', r; end if;
  raise notice 'ok A2-A3 evidence: 101 re-planned for Fill missing fields only (site and course pages done, unchanged); 102 (evidence before its plan, or not stored) held; 115 nothing to do, recorded and not looked at again';
  -- A4 retry on: 103 (share has room), 105 (transient, 7 h), 109 (timed-out task failed); not 104 (share empty), 106 (waits for a change),
  -- 107 (1 h ago), 108 (task still open), 110 (third unfinished end), 111 (a person cancelled)
  perform pg_temp.setv('plans.replan_on_retry', '1');
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '103,105,109' or (r->>'replanned')::int <> 3 then raise exception 'A4: retry should re-plan 103, 105, 109, got % (%)', pg_temp.queued(), r; end if;
  select string_agg(right(provider_id::text, 3) || ':' || (select string_agg(s->>'step', '+') from jsonb_array_elements(steps) s), ',' order by provider_id) into v
    from pipeline.enrich_plan_runs where state = 'queued';
  if v <> '103:pages,105:pages,109:pages' then raise exception 'A4: only the retryable step should run, got %', v; end if;
  if not exists (select 1 from pipeline.enrich_plan_runs where provider_id = pg_temp.pid(103) and state = 'queued' and reason like '%steps that can run again: pages%') then
    raise exception 'A4: the reason does not name the step'; end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  raise notice 'ok A4 retry: 103 (share has room again), 105 (transient error 7 h ago), 109 (timed-out task failed) re-planned for the step only; 104, 106, 107, 108, 110, 111 held';
  -- A5 the input fingerprint: 105's new run fails the same way; three days on, the same inputs are not planned again; a change in the gaps is
  update pipeline.enrich_plan_runs set created_at = now() - interval '3 days', finished_at = now() - interval '3 days',
         steps = '[{"step":"pages","status":"failed","note":"this task is already running","group":"course_search","finished_at":"2026-01-01T00:00:00Z"}]'
   where provider_id = pg_temp.pid(105) and estimate ? 'replan_of';
  -- the run's inputs were taken before its step failed again; make its recorded fingerprint the one these inputs give now
  update pipeline.enrich_plan_runs r set estimate = r.estimate || jsonb_build_object('fingerprint', md5(jsonb_build_object('missing', 30, 'evidence_at', i->'evidence_at',
           'central_at', i->'central_at', 'retry', i->'retry_steps')::text))
    from (select security.enrich_plan_inputs_v1(pg_temp.pid(105)) i) z where r.provider_id = pg_temp.pid(105) and r.estimate ? 'replan_of';
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '' then raise exception 'A5: unchanged inputs were planned again: %', pg_temp.queued(); end if;
  insert into pipeline.course_attribute_coverage(provider_id, course_id, country_code, attribute, state) values (pg_temp.pid(105), gen_random_uuid(), 'AU', 'duration', 'missing');
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '105' then raise exception 'A5: changed inputs should be planned (%)', r; end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  raise notice 'ok A5 input fingerprint: the same inputs as the latest run are not planned again; one more missing value changes them and 105 is planned';
  -- A6 the per-hour cap is shared by every early re-plan
  perform pg_temp.uni(116, 30, 'site,fields'), pg_temp.uni(117, 30, 'site,fields');
  perform pg_temp.ran(116, 'auto', 5, 30, 'site~done|fields~done'), pg_temp.ran(117, 'auto', 5, 30, 'site~done|fields~done');
  insert into pipeline.coverage_course_pages(course_id, provider_id, evidence_id, read_status, read_at) values
    (gen_random_uuid(), pg_temp.pid(116), gen_random_uuid(), 'read', now()), (gen_random_uuid(), pg_temp.pid(117), gen_random_uuid(), 'read', now());
  update pipeline.enrich_plan_runs set created_at = created_at - interval '2 hours' where estimate ? 'replan_of';
  perform pg_temp.setv('plans.replan_per_hour', '1');
  r := security.enrich_plan_auto_v1();
  if (r->>'replanned')::int <> 1 or pg_temp.queued() not in ('116', '117') then raise exception 'A6: cap 1 an hour, got % (%)', pg_temp.queued(), r; end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  r := security.enrich_plan_auto_v1();
  if (r->>'started')::int <> 0 then raise exception 'A6: the cap was not kept (%)', r; end if;
  raise notice 'ok A6 evidence and retry re-plans share plans.replan_per_hour (1: one of 116 and 117 this hour)';
  -- A7 a Run now in the last plans.replan_min_days holds the automatic plan only while plans.run_now_supersedes_auto is on
  perform pg_temp.setv('plans.run_now_supersedes_auto', '0');
  r := security.enrich_plan_auto_v1();
  if pg_temp.queued() <> '114' then raise exception 'A7: with the switch off 114 is due as before, got %', pg_temp.queued(); end if;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  perform pg_temp.setv('plans.run_now_supersedes_auto', '1');
  perform pg_temp.setv('plans.replan_on_evidence', '0'); perform pg_temp.setv('plans.replan_on_retry', '0'); perform pg_temp.setv('plans.replan_per_hour', '0');
  raise notice 'ok A7 the Run now hold follows plans.run_now_supersedes_auto (off: 114 is due as before)';
end $$;
-- the inputs, read-only
do $$
declare v jsonb := security.enrich_plan_inputs_v1(pg_temp.pid(106));
begin
  if v->'retry_steps' <> '[]'::jsonb or v->>'last_state' <> 'done' then raise exception 'A8: %', v; end if;
  perform pg_temp.setv('plans.retry_waits_for_change', '[]');
  if security.enrich_plan_inputs_v1(pg_temp.pid(106))->'retry_steps' <> '["pages"]'::jsonb then raise exception 'A8: the cause list is not read from the setting'; end if;
  perform pg_temp.setv('plans.retry_waits_for_change', '["too_few_pages", "nothing_ready", "no_website", "not a search target", "no website is recorded", "already has a read page", "Needs a website first"]');
  raise notice 'ok A8 a cause in plans.retry_waits_for_change is not retried by time (the list is the setting)';
end $$;

-- B. Run now and an open automatic plan -----------------------------------------------------------------------------------------------------------
select pg_temp.uni(130, 30, 'site,pages,fields');
insert into pipeline.admin_jobs(id, kind, state, requested_by, args) values ('00000000-0000-0000-0000-00000000b130', 'provider_fill', 'queued', '00000000-0000-0000-0000-00000000a006', '{"plan_run":"00000000-0000-0000-0000-00000000c130"}');
insert into pipeline.enrich_plan_runs(id, provider_id, mode, state, steps, estimate, requested_by, reason, created_at) values
  ('00000000-0000-0000-0000-00000000c130', pg_temp.pid(130), 'auto', 'running',
   '[{"step":"site","status":"running","group":"other","est_credits":1,"ref":{"kind":"job","id":"00000000-0000-0000-0000-00000000b130"}},
     {"step":"pages","status":"waiting","group":"course_search","est_credits":5}, {"step":"fields","status":"pending","group":"reads","est_credits":0}]',
   '{"missing":30}', '00000000-0000-0000-0000-00000000a006', 'Automatic enrichment plan', now() - interval '1 hour');
do $$
declare r jsonb; v_m uuid; v text;
begin
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a004', false);
  perform pg_temp.setv('plans.run_now_supersedes_auto', '0');
  begin perform public.admin_enrich_plan('run', jsonb_build_object('provider', pg_temp.pid(130), 'steps', '["site","pages"]'::jsonb, 'reason', 'operator test'));
        raise exception 'B1: Run now went ahead with the switch off';
  exception when others then if sqlerrm not like 'a plan is already running for this university' then raise; end if; end;
  perform pg_temp.setv('plans.run_now_supersedes_auto', '1');
  r := public.admin_enrich_plan('run', jsonb_build_object('provider', pg_temp.pid(130), 'steps', '["site","pages"]'::jsonb, 'reason', 'operator test'));
  v_m := (r->>'run_id')::uuid;
  if (select state from pipeline.enrich_plan_runs where id = '00000000-0000-0000-0000-00000000c130') <> 'cancelled' then raise exception 'B2: the automatic plan is still open'; end if;
  select string_agg(s->>'step' || ':' || (s->>'status'), ',') into v from pipeline.enrich_plan_runs, jsonb_array_elements(steps) s where id = '00000000-0000-0000-0000-00000000c130';
  if v <> 'site:handed_over,pages:cancelled,fields:cancelled' then raise exception 'B2: superseded steps %', v; end if;
  select string_agg(s->>'step' || ':' || (s->>'status') || ':' || coalesce(s->'ref'->>'id', ''), ',') into v from pipeline.enrich_plan_runs, jsonb_array_elements(steps) s where id = v_m;
  if v not like 'pages:running:%,site:running:00000000-0000-0000-0000-00000000b130' then raise exception 'B3: Run now steps %', v; end if;
  if (select count(*) from pipeline.admin_jobs where kind = 'provider_fill') <> 1 then raise exception 'B3: the running site task was started twice'; end if;
  if (select args->>'plan_run' from pipeline.admin_jobs where id = '00000000-0000-0000-0000-00000000b130') <> v_m::text then raise exception 'B3: the carried task does not name its plan'; end if;
  if (select count(*) from pipeline.enrich_plan_runs where provider_id = pg_temp.pid(130) and state in ('queued', 'running')) <> 1 then raise exception 'B4: two open plans'; end if;
  if (r->'estimate'->>'credits')::numeric <> 5 then raise exception 'B4: the estimate should count the new step only (5), got %', r->'estimate'; end if;
  if not exists (select 1 from pipeline.admin_control_events where action = 'supersede' and detail->>'superseded' = '00000000-0000-0000-0000-00000000c130') then raise exception 'B4: no log'; end if;
  if (security.enrich_plan_orphans_v1()->>'orphans')::int <> 0 then raise exception 'B4: the carried task counts as orphaned: %', security.enrich_plan_orphans_v1(); end if;
  raise notice 'ok B1-B4 Run now on an open automatic plan: refused with the switch off; on, the automatic plan ends (site handed over, the rest superseded), the Run now plan carries the running site task (not started twice, names its plan) and starts Find course pages; one open plan; estimate for the new step only; logged; nothing orphaned';
  begin perform public.admin_enrich_plan('run', jsonb_build_object('provider', pg_temp.pid(130), 'steps', '["fields"]'::jsonb, 'reason', 'second operator'));
        raise exception 'B5: a second Run now went ahead';
  exception when others then if sqlerrm not like 'a plan is already running for this university (a Run now started %); wait for it to finish or cancel it first' then raise; end if; end;
  raise notice 'ok B5 an open Run now plan is never taken over (the refusal says when it started)';

  -- C. cancel: the tasks are cancelled (v2.15.419) and the run starts nothing more
  r := public.admin_enrich_plan('cancel', jsonb_build_object('run_id', v_m, 'reason', 'operator stop'));
  if not (r->>'cancelled')::boolean then raise exception 'C1: %', r; end if;
  if exists (select 1 from pipeline.admin_jobs where args->>'plan_run' = v_m::text and state not in ('cancelled', 'done', 'failed') and not cancel_requested) then
    raise exception 'C1: a task of the cancelled run carries on'; end if;
  begin perform security.enrich_plan_start_step_v1(v_m, 'fields'); raise exception 'C2: a step started on a cancelled run';
  exception when others then if sqlerrm <> 'the plan run is cancelled; no further step starts' then raise; end if; end;
  if (security.enrich_plan_tick_v1(v_m)->>'started')::int <> 0 then raise exception 'C2: the tick started a step of a cancelled run'; end if;
  perform set_config('fx.uid', '', false);
  raise notice 'ok C1-C2 cancel: the run''s tasks are cancelled; security.enrich_plan_start_step_v1 refuses a cancelled run and the tick starts nothing';
end $$;
-- C3 the tick's own guard: a run's state read fresh before each start
do $$
declare v_id uuid;
begin
  perform pg_temp.uni(131, 30, 'site');
  insert into pipeline.enrich_plan_runs(provider_id, mode, state, steps, requested_by, reason)
  values (pg_temp.pid(131), 'manual', 'running', '[{"step":"site","status":"pending","group":"other","est_credits":0}]', '00000000-0000-0000-0000-00000000a004', 'r') returning id into v_id;
  perform security.enrich_plan_tick_v1(v_id);
  if (select steps->0->>'status' from pipeline.enrich_plan_runs where id = v_id) <> 'running' then raise exception 'C3: an open run did not start its step'; end if;
  raise notice 'ok C3 an open run still starts its step through the tick';
end $$;

-- D. orphaned plan work: the check and its integration issue ------------------------------------------------------------------------------------------
do $$
declare v jsonb; r jsonb;
begin
  v := security.enrich_plan_orphans_v1();
  if (v->>'orphans')::int <> 0 then raise exception 'D0: %', v; end if;
  r := security.enrich_plan_orphans_issue_v1();
  if exists (select 1 from pipeline.integration_issues where fingerprint = 'enrich_plan_orphans') then raise exception 'D0: an issue with nothing orphaned'; end if;
  -- a task of a cancelled run still queued; a task of a finished run whose step timed out; onboarding of a finished run
  insert into pipeline.enrich_plan_runs(id, provider_id, mode, state, steps, requested_by, reason) values
   ('00000000-0000-0000-0000-00000000c140', pg_temp.pid(101), 'auto', 'cancelled', '[{"step":"site","status":"cancelled","ref":{"kind":"job","id":"00000000-0000-0000-0000-00000000b140"}}]', null, 'r'),
   ('00000000-0000-0000-0000-00000000c141', pg_temp.pid(102), 'auto', 'done', '[{"step":"pages","status":"timed_out","ref":{"kind":"job","id":"00000000-0000-0000-0000-00000000b141"}},
                                                                               {"step":"adapter","status":"timed_out","ref":{"kind":"onboarding","id":"00000000-0000-0000-0000-00000000d141"}}]', null, 'r');
  insert into pipeline.admin_jobs(id, kind, state, args) values
   ('00000000-0000-0000-0000-00000000b140', 'provider_fill', 'queued', '{"plan_run":"00000000-0000-0000-0000-00000000c140"}'),
   ('00000000-0000-0000-0000-00000000b141', 'course_page_find', 'running', '{"plan_run":"00000000-0000-0000-0000-00000000c141"}');
  insert into pipeline.provider_onboarding(id, provider_id, status) values ('00000000-0000-0000-0000-00000000d141', pg_temp.pid(102), 'course_pages');
  v := security.enrich_plan_orphans_v1();
  if (v->>'orphans')::int <> 3 or v->'by_cause' <> '{"plan cancelled": 1, "step timed out, task carries on": 2}'::jsonb then raise exception 'D1: %', v; end if;
  r := security.enrich_plan_orphans_issue_v1();
  if not exists (select 1 from pipeline.integration_issues where fingerprint = 'enrich_plan_orphans' and severity = 'P1' and workstream = 'A7' and condition_cleared_at is null)
     or not exists (select 1 from security.fx_alerts where observed) then raise exception 'D2: the issue was not raised'; end if;
  perform security.enrich_plan_orphans_issue_v1();
  if (select count(*) from pipeline.integration_issues where fingerprint = 'enrich_plan_orphans') <> 1 then raise exception 'D2: issue duplicated'; end if;
  update pipeline.admin_jobs set state = 'cancelled' where id in ('00000000-0000-0000-0000-00000000b140', '00000000-0000-0000-0000-00000000b141');
  update pipeline.provider_onboarding set status = 'cancelled' where id = '00000000-0000-0000-0000-00000000d141';
  perform security.enrich_plan_orphans_issue_v1();
  if not exists (select 1 from pipeline.integration_issues where fingerprint = 'enrich_plan_orphans' and condition_cleared_at is not null)
     or not exists (select 1 from pipeline.integration_issue_events where kind = 'not_observed') or not exists (select 1 from security.fx_alerts where not observed) then
    raise exception 'D3: the issue was not marked cleared'; end if;
  raise notice 'ok D1-D3 orphans: a task of a cancelled run and the task and onboarding of a timed-out step are found by cause; the issue is raised once (P1, A7) with its alert, and marked cleared when they end';
end $$;

-- E. the overview shows the settings ---------------------------------------------------------------------------------------------------------------
do $$
declare r jsonb;
begin
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a003', false);
  r := public.admin_enrich_plan('overview', '{}');
  if (r->'limits'->>'replan_on_evidence')::int <> 0 or (r->'limits'->>'replan_on_retry')::int <> 0 or (r->'limits'->>'fair_order')::int <> 0
     or (r->'limits'->>'run_now_supersedes_auto')::int <> 1 or (r->'limits'->>'retry_after_hours')::int <> 6 or (r->'limits'->>'step_retry_max')::int <> 3 then
    raise exception 'E1: %', r->'limits'; end if;
  perform set_config('fx.uid', '', false);
  raise notice 'ok E1 the Enrichment plan overview shows the lifecycle settings';
end $$;
