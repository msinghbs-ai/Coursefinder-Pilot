-- Plan continuity fixtures (after the migration). Each case raises on a wrong result and says ok on a right one.
set client_min_messages = notice;
\set ON_ERROR_STOP 1
-- people: a Platform Admin (owner of automatic plans), an operator (rank 4), a curator (rank 3)
insert into security.fx_ranks values ('00000000-0000-0000-0000-00000000a006', 6), ('00000000-0000-0000-0000-00000000a004', 4), ('00000000-0000-0000-0000-00000000a003', 3);
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000a1', 'AU');
insert into pipeline.enrich_plan_control values (1, true, '00000000-0000-0000-0000-00000000a006', 'on', now());
insert into pipeline.field_register values ('duration', 'enrich');

-- A. automatic plans: re-plan when the gaps grew ------------------------------------------------------------------------------------------
-- p0 never planned; p1, p2 planned 5 days ago with 10 missing, now 30; p3 planned 5 days ago with 10, now 12 (rise under 5);
-- p4 planned 1 day ago with 10, now 30 (too soon); p5 planned 20 days ago (due anyway)
do $$
declare i int; p uuid;
begin
  for i in 0 .. 5 loop
    p := ('00000000-0000-0000-0000-0000000000' || lpad((i + 10)::text, 2, '0'))::uuid;
    insert into catalogue.providers(id, country_id, canonical_name) values (p, '00000000-0000-0000-0000-0000000000a1', 'Uni ' || i);
    insert into security.fx_plan_steps values (p, '[{"step":"fields","label":"Fill missing fields","group":"none","est_credits":0,"est_usd":0.01}]');
    insert into pipeline.course_attribute_coverage(provider_id, course_id, country_code, attribute, state)
    select p, gen_random_uuid(), 'AU', 'duration', 'missing' from generate_series(1, case i when 3 then 12 else 30 end);
  end loop;
  insert into pipeline.enrich_plan_runs(provider_id, mode, state, steps, estimate, created_at) values
   ('00000000-0000-0000-0000-000000000011', 'auto', 'done', '[]', '{"missing": 10}', now() - interval '5 days'),
   ('00000000-0000-0000-0000-000000000012', 'auto', 'done', '[]', '{"missing": 10}', now() - interval '5 days'),
   ('00000000-0000-0000-0000-000000000013', 'auto', 'done', '[]', '{"missing": 10}', now() - interval '5 days'),
   ('00000000-0000-0000-0000-000000000014', 'auto', 'done', '[]', '{"missing": 10}', now() - interval '1 day'),
   ('00000000-0000-0000-0000-000000000015', 'auto', 'done', '[]', '{"missing": 30}', now() - interval '20 days');
end $$;
do $$
declare r jsonb; v text;
begin
  -- as shipped (plans.replan_per_hour 0): the due and never-planned universities only, as before
  r := security.enrich_plan_auto_v1();
  select string_agg(right(provider_id::text, 2), ',' order by provider_id) into v from pipeline.enrich_plan_runs where state = 'queued';
  if v is distinct from '10,15' or (r->>'replanned')::int <> 0 then raise exception 'A1: shipped off should plan 10 and 15 only, got % (%)', v, r; end if;
  if exists (select 1 from pipeline.enrich_plan_runs where estimate ? 'replan_of') then raise exception 'A1: a re-plan while off'; end if;
  raise notice 'ok A1 shipped off: never-planned (10) and due (15) planned; nothing re-planned (%)', r;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  -- switched on at 1 an hour: one of 11 and 12 (gaps 10 -> 30); not 13 (rise 2 < 5), not 14 (planned yesterday < 2 days), not 10 or 15 (planned now)
  update pipeline.platform_toolset_settings set value = '1' where key = 'plans.replan_per_hour';
  r := security.enrich_plan_auto_v1();
  select string_agg(right(provider_id::text, 2), ',') into v from pipeline.enrich_plan_runs where state = 'queued';
  if v not in ('11', '12') or (r->>'replanned')::int <> 1 then raise exception 'A2: one re-plan of 11 or 12 expected, got % (%)', v, r; end if;
  if not exists (select 1 from pipeline.enrich_plan_runs where state = 'queued' and estimate->>'missing_then' = '10' and estimate->>'missing' = '30'
                   and estimate ? 'replan_of' and reason like 'Automatic enrichment plan (missing values grew from 10 to 30 since the last plan)%') then
    raise exception 'A2: the re-plan does not record what it re-plans'; end if;
  raise notice 'ok A2 on at 1 an hour: % re-planned (10 -> 30 missing); 13 (rise 2) and 14 (planned yesterday) held', v;
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  r := security.enrich_plan_auto_v1();
  if (r->>'started')::int <> 0 then raise exception 'A3: the hourly cap was not kept (%)', r; end if;
  raise notice 'ok A3 the second run in the same hour re-plans nothing (cap 1 an hour used)';
  update pipeline.enrich_plan_runs set created_at = created_at - interval '2 hours' where estimate ? 'replan_of';
  r := security.enrich_plan_auto_v1();
  if (r->>'replanned')::int <> 1 then raise exception 'A4: the next hour should re-plan the other one (%)', r; end if;
  raise notice 'ok A4 the next hour re-plans the other one';
  update pipeline.enrich_plan_runs set state = 'done' where state = 'queued';
  -- an open run holds a university whatever its gaps; switching automatic off stops everything
  update pipeline.enrich_plan_control set auto_enabled = false;
  if security.enrich_plan_auto_v1()->>'auto' <> 'off' then raise exception 'A5: automatic off not kept'; end if;
  update pipeline.enrich_plan_control set auto_enabled = true;
  update pipeline.platform_toolset_settings set value = '0' where key = 'plans.replan_per_hour';
  raise notice 'ok A5 the automatic switch still rules';
end $$;

-- B. cancelling a plan run cancels the tasks its steps started ------------------------------------------------------------------------------
do $$
declare r jsonb; v_run uuid; o uuid := '00000000-0000-0000-0000-00000000a006';
begin
  insert into pipeline.admin_jobs(id, kind, state, requested_by) values ('00000000-0000-0000-0000-0000000000b1', 'provider_fill', 'queued', o),
    ('00000000-0000-0000-0000-0000000000b2', 'course_page_find', 'done', o), ('00000000-0000-0000-0000-0000000000b3', 'enrich_fields', 'running', o);
  insert into pipeline.provider_onboarding(id, provider_id, status) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000010', 'course_pages');
  insert into pipeline.enrich_plan_runs(provider_id, mode, state, requested_by, reason, steps) values ('00000000-0000-0000-0000-000000000013', 'auto', 'running', o, 'Automatic',
   '[{"step":"site","status":"running","ref":{"kind":"job","id":"00000000-0000-0000-0000-0000000000b1"}},
     {"step":"pages","status":"running","ref":{"kind":"job","id":"00000000-0000-0000-0000-0000000000b2"}},
     {"step":"fields","status":"running","ref":{"kind":"job","id":"00000000-0000-0000-0000-0000000000b3"}},
     {"step":"adapter","status":"running","ref":{"kind":"onboarding","id":"00000000-0000-0000-0000-0000000000c1"}},
     {"step":"scholarships","status":"pending"},{"step":"x","status":"done"}]') returning id into v_run;
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a004', false);   -- an operator who did not start the run
  r := public.admin_enrich_plan('cancel', jsonb_build_object('run_id', v_run, 'reason', 'stop this'));
  if not (r->>'cancelled')::boolean or (r->>'steps_cancelled')::int <> 5 then raise exception 'B1: %', r; end if;
  if (select state from pipeline.admin_jobs where id = '00000000-0000-0000-0000-0000000000b1') <> 'cancelled' then raise exception 'B1: queued task not cancelled'; end if;
  if not (select cancel_requested from pipeline.admin_jobs where id = '00000000-0000-0000-0000-0000000000b3') then raise exception 'B1: running task not asked to cancel'; end if;
  if (select state from pipeline.admin_jobs where id = '00000000-0000-0000-0000-0000000000b2') <> 'done' then raise exception 'B1: a finished task changed'; end if;
  if (select status from pipeline.provider_onboarding where id = '00000000-0000-0000-0000-0000000000c1') <> 'cancelled' then raise exception 'B1: onboarding not stopped'; end if;
  if (select count(*) from pipeline.enrich_plan_runs r2, jsonb_array_elements(r2.steps) s where r2.id = v_run and s->>'status' = 'cancelled') <> 5
     or (select s->>'status' from pipeline.enrich_plan_runs r2, jsonb_array_elements(r2.steps) s where r2.id = v_run and s->>'step' = 'x') <> 'done' then raise exception 'B1: step states'; end if;
  if (select s->>'note' from pipeline.enrich_plan_runs r2, jsonb_array_elements(r2.steps) s where r2.id = v_run and s->>'step' = 'pages') not like 'the task could not be cancelled (the job has already finished)%' then
    raise exception 'B1: the finished task''s step should say why'; end if;
  if auth.uid() <> '00000000-0000-0000-0000-00000000a004' then raise exception 'B1: the caller was not restored (%)', auth.uid(); end if;
  if not exists (select 1 from pipeline.admin_control_events where action = 'cancel' and area = 'enrich_plan' and actor = '00000000-0000-0000-0000-00000000a004' and (detail->>'steps_cancelled')::int = 5) then
    raise exception 'B1: no log row by the person who cancelled'; end if;
  if (select state from pipeline.enrich_plan_runs where id = v_run) <> 'cancelled' then raise exception 'B1: run state'; end if;
  raise notice 'ok B1 cancel: queued task cancelled, running task asked to stop, onboarding stopped, pending step cancelled, finished task noted, done step kept, caller restored, logged (%)', r->'tasks';
  r := public.admin_enrich_plan('cancel', jsonb_build_object('run_id', v_run, 'reason', 'again'));
  if (r->>'cancelled')::boolean then raise exception 'B2: a closed run cancelled twice'; end if;
  raise notice 'ok B2 a run already closed is not cancelled again';
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a003', false);
  begin perform public.admin_enrich_plan('cancel', jsonb_build_object('run_id', v_run)); raise exception 'B3: a curator cancelled';
  exception when insufficient_privilege then raise notice 'ok B3 a curator cannot cancel (rank 4, as before)'; end;
end $$;

-- C. Enrich fields Start: the standing queue's in-flight rule and the published rule; D. the estimate ------------------------------------------
do $$
declare r jsonb; v_std uuid; pa uuid := '00000000-0000-0000-0000-0000000000d1'; ph uuid := '00000000-0000-0000-0000-0000000000d2';
begin
  insert into catalogue.providers(id, country_id, canonical_name) values (pa, '00000000-0000-0000-0000-0000000000a1', 'Published');
  insert into catalogue.providers(id, country_id, canonical_name, publication_status) values (ph, '00000000-0000-0000-0000-0000000000a1', 'Hidden', 'draft');
  insert into catalogue.courses(id, provider_id, canonical_title) values ('00000000-0000-0000-0000-0000000000e1', pa, 'C1 held by the standing queue'),
    ('00000000-0000-0000-0000-0000000000e2', pa, 'C2 free'), ('00000000-0000-0000-0000-0000000000e3', ph, 'C3 unpublished'),
    ('00000000-0000-0000-0000-0000000000e4', pa, 'C4 last item failed');
  insert into catalogue.campuses values (pa, 'active', null, 'Geelong');
  insert into pipeline.admin_jobs(id, kind, lane, state, args, requested_by) values ('00000000-0000-0000-0000-0000000000f1', 'enrich_fields', 'enrich-standing', 'running', '{"standing":true}', '00000000-0000-0000-0000-00000000a006')
   returning id into v_std;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values (v_std, pa, '00000000-0000-0000-0000-0000000000e1', 'duration', 'ai'),
    (v_std, pa, null, 'campus_region', 'queued'), (v_std, pa, '00000000-0000-0000-0000-0000000000e4', 'duration', 'failed');
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, cost_usd, updated_at)
  select gen_random_uuid(), pa, gen_random_uuid(), 'level', 'filled', 0.002, now() from generate_series(1, 4);   -- AI spent on settled items in 30 days
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a003', false);
  r := public.admin_enrich_fields('preview', '{"countries":["AU"],"fields":["duration"],"ai":true,"scraper":true}');
  if (r->'estimate'->>'items')::int <> 2 or (r->'estimate'->>'in_task')::int <> 1 or (r->'estimate'->>'unpublished')::int <> 1
     or (r->'estimate'->>'usd')::numeric <> round(2 * (security.enrich_unit_costs_v1()->>'enrich_usd_per_item')::numeric, 4) or (r->'estimate'->>'usd')::numeric <= 0 or (r->'estimate'->>'credits_max')::int <> 2 then raise exception 'D1: %', r->'estimate'; end if;
  if r->'fields' is null then raise exception 'D1: the preview lost its fields'; end if;
  raise notice 'ok D1 preview estimate: 2 to queue (C2, C4), 1 already in a task, 1 unpublished, AI = 2 x the 30-day average cost of an item, at most 2 scraper credits (%)', r->'estimate';
  r := public.admin_enrich_fields('preview', '{"countries":["AU"],"fields":["duration"],"ai":false,"scraper":false}');
  if (r->'estimate'->>'usd')::numeric <> 0 or (r->'estimate'->>'credits_max')::int <> 0 then raise exception 'D2: %', r->'estimate'; end if;
  raise notice 'ok D2 no AI and no scraper ticked: no spend';
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a004', false);
  r := public.admin_enrich_fields('start', '{"countries":["AU"],"fields":["duration","campus_region"],"reason":"fill durations"}');
  if (select string_agg(coalesce(right(course_id::text, 2), 'P:' || field), ',' order by course_id nulls first) from pipeline.field_enrich_items where job_id = (r->>'job_id')::uuid) is distinct from 'e2,e4' then
    raise exception 'C1: Start queued %', (select string_agg(coalesce(course_id::text, field), ',') from pipeline.field_enrich_items where job_id = (r->>'job_id')::uuid); end if;
  raise notice 'ok C1 Start skips C1 (in the standing task), C3 (unpublished) and the university campus region (in the standing task); queues C2 and C4';
  update pipeline.field_enrich_items set state = 'failed' where job_id = (r->>'job_id')::uuid;
  r := public.admin_enrich_fields('start', '{"provider_ids":["00000000-0000-0000-0000-0000000000d2"],"fields":["duration"],"reason":"hidden only"}');
  if (r->>'items')::int <> 0 then raise exception 'C2: an unpublished university was queued'; end if;
  raise notice 'ok C2 a chosen unpublished university gets no item';
end $$;

-- E. Retry failed items; F. export -------------------------------------------------------------------------------------------------------
do $$
declare r jsonb; v_src uuid; v_new uuid; n int;
begin
  select id into v_src from pipeline.admin_jobs where kind = 'enrich_fields' and reason = 'fill durations';
  begin perform public.admin_enrich_fields('retry', jsonb_build_object('job_id', v_src, 'reason', 'try again')); raise exception 'E1: an open task retried';
  exception when others then if sqlerrm not like 'the task is still open%' then raise; end if; end;
  update pipeline.admin_jobs set state = 'done' where id = v_src;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values (v_src, '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000e3', 'duration', 'failed');
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a003', false);
  begin perform public.admin_enrich_fields('retry', jsonb_build_object('job_id', v_src, 'reason', 'try again')); raise exception 'E2: a curator retried';
  exception when insufficient_privilege then null; end;
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a004', false);
  -- C4's latest item is the failed one of this task: retried; C2 too; C3 (unpublished) is left out
  r := public.admin_enrich_fields('retry', jsonb_build_object('job_id', v_src, 'reason', 'try again'));
  v_new := (r->>'job_id')::uuid;
  if (r->>'items')::int <> 2 or (select string_agg(right(course_id::text, 2), ',' order by course_id) from pipeline.field_enrich_items where job_id = v_new) <> 'e2,e4'
     or (select state from pipeline.admin_jobs where id = v_new) <> 'queued' or (select args->>'retry_of' from pipeline.admin_jobs where id = v_new) <> v_src::text
     or (select title from pipeline.admin_jobs where id = v_new) not like 'Retry failed · %' then raise exception 'E3: %', r; end if;
  if not exists (select 1 from pipeline.admin_control_events where action = 'retry_failed' and target = v_src::text and (detail->>'items')::int = 2) then raise exception 'E3: not logged'; end if;
  raise notice 'ok E1-E3 retry: refused while the task is open and for a curator; then C2 and C4 go into a new queued task (retry_of kept, logged); the unpublished item is left out';
  begin perform public.admin_enrich_fields('retry', jsonb_build_object('job_id', v_src, 'reason', 'again')); raise exception 'E4: retried twice';
  exception when others then if sqlerrm not like 'no failed item to retry%' then raise; end if; end;
  raise notice 'ok E4 a second retry finds each failed item already in the open retry task';
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a003', false);
  update pipeline.platform_toolset_settings set value = '2' where key = 'enrich.export_page_rows';
  r := public.admin_enrich_fields('export', jsonb_build_object('job_id', v_src));
  n := jsonb_array_length(r->'rows');
  if n <> 2 or (r->>'page_rows')::int <> 2 then raise exception 'F1: page %', r; end if;
  r := public.admin_enrich_fields('export', jsonb_build_object('job_id', v_src, 'after', r->'rows'->1->>'id'));
  if jsonb_array_length(r->'rows') <> 1 or r->'rows'->0->>'university' <> 'Hidden' or not (r->'rows'->0 ? 'quote') or not (r->'rows'->0 ? 'evidence_id') then raise exception 'F1: next page %', r; end if;
  update pipeline.platform_toolset_settings set value = '2000' where key = 'enrich.export_page_rows';
  raise notice 'ok F1 export (curator): pages of enrich.export_page_rows by id, with university, course, source, quote and evidence';
end $$;

-- G. Enrichment plan retry, export, unit costs ----------------------------------------------------------------------------------------------
do $$
declare r jsonb; v_run uuid; p uuid := '00000000-0000-0000-0000-000000000014'; v_ctl record;
begin
  select auto_enabled, owner, reason into v_ctl from pipeline.enrich_plan_control;
  update security.fx_plan_steps set steps = '[{"step":"site","label":"Website","est_credits":5,"est_usd":0},{"step":"pages","label":"Course pages","est_credits":7,"est_usd":0}]' where provider_id = p;
  insert into pipeline.enrich_plan_runs(provider_id, mode, state, requested_by, reason, steps) values (p, 'auto', 'done', '00000000-0000-0000-0000-00000000a006', 'Automatic',
    '[{"step":"site","label":"Website","status":"done"},{"step":"pages","label":"Course pages","status":"timed_out","est_credits":7}]') returning id into v_run;
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a003', false);
  begin perform public.admin_enrich_plan('retry', jsonb_build_object('run_id', v_run, 'reason', 'again')); raise exception 'G1: a curator retried';
  exception when insufficient_privilege then null; end;
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a004', false);
  r := public.admin_enrich_plan('retry', jsonb_build_object('run_id', v_run, 'reason', 'pages again'));
  if r->'steps' <> '["pages"]'::jsonb or not exists (select 1 from pipeline.enrich_plan_runs where id = (r->>'run_id')::uuid and mode = 'manual'
       and steps @> '[{"step":"pages"}]' and not steps @> '[{"step":"site"}]' and reason like 'Retry of the failed steps of run %: pages again' and (estimate->>'credits')::numeric = 7) then
    raise exception 'G1: %', r; end if;
  if (select row(auto_enabled, owner, reason) from pipeline.enrich_plan_control) is distinct from v_ctl then raise exception 'G1: a Run now changed the automatic plans'; end if;
  raise notice 'ok G1 plan retry: only the timed-out step runs again as a Run now (manual run, estimate 7 credits from the plan, reason kept); refused for a curator; the automatic plans'' switch and schedule unchanged';
  begin perform public.admin_enrich_plan('retry', jsonb_build_object('run_id', (r->>'run_id'), 'reason', 'again')); raise exception 'G2: an open run retried';
  exception when others then if sqlerrm not like 'nothing to retry%' then raise; end if; end;
  raise notice 'ok G2 an open run cannot be retried';
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000a003', false);
  r := public.admin_enrich_plan('export', jsonb_build_object('provider', p));
  if jsonb_array_length(r->'rows') <> 3 or (r->>'runs')::int <> 3 or (r->'rows'->0->>'university') <> 'Uni 4' or not (r->'rows'->0 ? 'task_id') then raise exception 'G3: %', r; end if;
  r := public.admin_enrich_plan('export', '{}');
  if jsonb_array_length(r->'rows') < 10 then raise exception 'G3: all runs %', jsonb_array_length(r->'rows'); end if;
  raise notice 'ok G3 plan export (curator): one row per step for a university or for all runs';
  r := public.admin_enrich_plan('unit_costs', '{}');
  if (r->'unit_costs'->>'enrich_usd_per_item')::numeric <> (security.enrich_unit_costs_v1()->>'enrich_usd_per_item')::numeric or r->'on_demand'->>'credits_left' is null then raise exception 'G4: %', r; end if;
  r := public.admin_enrich_plan('overview', '{}');
  if (r->'limits'->>'replan_per_hour')::int <> 0 or (r->'limits'->>'replan_min_new_gaps')::int <> 5 then raise exception 'G5: %', r->'limits'; end if;
  raise notice 'ok G4-G5 unit costs for confirmations; overview shows the re-plan settings (off)';
end $$;

-- H. the cross-check: the same findings as the live definition found before the edit ------------------------------------------------------
do $$
declare r jsonb; v text;
begin
  r := security.field_crosscheck_v1();
  select string_agg(field || '=' || page_value::text, ';' order by field) into v from pipeline.field_crosscheck_findings;
  if (r->>'new')::int <> 3 or v is distinct from (select val from security.fx_before where what = 'crosscheck') then raise exception 'H1: % (%), before %', v, r, (select val from security.fx_before); end if;
  raise notice 'ok H1 the edited cross-check finds exactly what the live one found: %', v;
end $$;
