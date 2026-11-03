-- After the migration: every case of the change.
set client_min_messages = notice;

-- A1: the same gap set as the live single statement, found in slices (100 courses each), the checkpoint saved, the run recorded as done
update pipeline.platform_toolset_settings set value = '100' where toolset_key = 'pipeline' and key = 'gaps.scan_courses_per_slice';
do $$
declare v jsonb := security.field_gap_queue_run_v1(); n_new int; n_old int; n_diff int;
begin
  if v->>'outcome' <> 'done' or v->>'queue' <> 'started' then raise exception 'A1: %', v; end if;
  select count(*) into n_new from pipeline.field_enrich_items where job_id = (v->>'job_id')::uuid and field <> 'campus_list';
  select count(*) into n_old from public.fx_old_set;
  select count(*) into n_diff from ((select provider_id, course_id, field from pipeline.field_enrich_items where job_id = (v->>'job_id')::uuid except select * from public.fx_old_set)
                                    union all (select * from public.fx_old_set except select provider_id, course_id, field from pipeline.field_enrich_items where job_id = (v->>'job_id')::uuid)) d;
  if n_diff <> 0 or n_new <> n_old then raise exception 'A1: new % items, old %, % differ', n_new, n_old, n_diff; end if;
  if (v->'scan'->>'slices')::int < 3 or not (v->'scan'->>'cycle_complete')::boolean then raise exception 'A1 scan: %', v->'scan'; end if;
  if (select count(*) from pipeline.field_gap_queue_runs where outcome = 'done' and items = n_new) <> 1 then raise exception 'A1: run not recorded'; end if;
  raise notice 'A1 ok: % items, the same set as the live statement, % slices, pass complete, run recorded done', n_new, v->'scan'->>'slices';
end $$;

-- A2: while that standing task is open the next run is held (previous_run_open), never "succeeded with nothing"
do $$
declare v jsonb := security.field_gap_queue_run_v1();
begin
  if v->>'outcome' <> 'held' or v->>'hold_reason' <> 'previous_run_open' then raise exception 'A2: %', v; end if;
  raise notice 'A2 ok: previous task open -> held, previous_run_open';
end $$;

-- A3: task closed; everything is in progress, so a whole pass finds nothing -> idle, nothing_due
update pipeline.admin_jobs set state = 'done' where coalesce((args->>'standing')::boolean, false);
do $$
declare v jsonb := security.field_gap_queue_run_v1();
begin
  if v->>'outcome' <> 'idle' or v->>'hold_reason' <> 'nothing_due' or not (v->'scan'->>'cycle_complete')::boolean then raise exception 'A3: %', v; end if;
  raise notice 'A3 ok: a full pass found nothing -> idle, nothing_due (scanned %)', v->'scan'->>'scanned';
end $$;

-- A4: bounded by the item cap, resumed from the checkpoint; the runs together take the same set
update pipeline.field_enrich_items set state = 'filled', updated_at = now() - interval '1 day' where job_id in (select id from pipeline.admin_jobs where coalesce((args->>'standing')::boolean, false));
-- (filled items with no value since are gaps again: the same set comes back)
update pipeline.platform_toolset_settings set value = '40' where toolset_key = 'pipeline' and key = 'gaps.items_per_run';
create table public.fx_new_set (provider_id uuid, course_id uuid, field text);
do $$
declare v jsonb; i int := 0; n int;
begin
  loop
    i := i + 1;
    v := security.field_gap_queue_run_v1();
    exit when v->>'outcome' <> 'done';
    insert into public.fx_new_set select provider_id, course_id, field from pipeline.field_enrich_items where job_id = (v->>'job_id')::uuid and field <> 'campus_list';
    if (v->>'items')::int > 40 then raise exception 'A4: more than the cap: %', v->>'items'; end if;
    update pipeline.admin_jobs set state = 'done' where id = (v->>'job_id')::uuid;
    exit when i > 20;
  end loop;
  select count(*) into n from ((select * from public.fx_new_set except select * from public.fx_old_set) union all (select * from public.fx_old_set except select * from public.fx_new_set)) d;
  if n <> 0 or (select count(*) from public.fx_new_set) <> (select count(*) from public.fx_old_set) then raise exception 'A4: % differ, % taken', n, (select count(*) from public.fx_new_set); end if;
  if (select count(*) from pipeline.field_gap_queue_runs where items > 0 and items <= 40 and run_at > now() - interval '1 minute') < 3 then raise exception 'A4: not bounded'; end if;
  raise notice 'A4 ok: % capped runs of at most 40 items resumed from the checkpoint and took the same % items; then % %', i - 1, (select count(*) from public.fx_new_set), v->>'outcome', v->>'hold_reason';
end $$;

-- A5: a run stopped by its time limit mid-pass with nothing found is held (scan_continues), not "nothing due"; the next run resumes and finishes
update pipeline.field_gap_queue_checkpoint set cursor_course_id = (select id from catalogue.courses order by id offset 150 limit 1);
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'gaps.scan_seconds';
do $$
declare v jsonb := security.field_gap_queue_run_v1(); c uuid;
begin
  if v->>'outcome' <> 'held' or v->>'hold_reason' <> 'scan_continues' or (v->'scan'->>'stopped') <> 'time' then raise exception 'A5: %', v; end if;
  select cursor_course_id into c from pipeline.field_gap_queue_checkpoint;
  if c is null then raise exception 'A5: checkpoint lost'; end if;
  raise notice 'A5 ok: time limit mid-pass -> held, scan_continues; checkpoint kept';
end $$;
update pipeline.platform_toolset_settings set value = '20' where toolset_key = 'pipeline' and key = 'gaps.scan_seconds';

-- A6: wrap: the gaps lie before the checkpoint; the run reaches the end with nothing, wraps once and finds them
update pipeline.admin_jobs set state = 'done' where coalesce((args->>'standing')::boolean, false);
update pipeline.platform_toolset_settings set value = '30000' where toolset_key = 'pipeline' and key = 'gaps.items_per_run';
update pipeline.field_enrich_items set state = 'filled', updated_at = now() - interval '1 day'
 where course_id = (select id from catalogue.courses where lifecycle_status = 'active' and provider_id <> '00000000-0000-0000-0000-0000000000a3' and duration_value is null order by id limit 1) and field = 'duration';
update pipeline.field_gap_queue_checkpoint set cursor_course_id = (select id from catalogue.courses order by id offset 200 limit 1);
do $$
declare v jsonb := security.field_gap_queue_run_v1();
begin
  if v->>'outcome' <> 'done' or not (v->'scan'->>'wrapped')::boolean or (v->>'items')::int < 1 then raise exception 'A6: %', v; end if;
  raise notice 'A6 ok: wrapped once and found % item(s) before the checkpoint', v->>'items';
end $$;

-- A7: queue switched off -> switched_off, queue_off
update pipeline.admin_jobs set state = 'done' where coalesce((args->>'standing')::boolean, false);
update pipeline.field_gap_queue_control set enabled = false;
do $$
declare v jsonb := security.field_gap_queue_run_v1();
begin
  if v->>'outcome' <> 'switched_off' or v->>'hold_reason' <> 'queue_off' then raise exception 'A7: %', v; end if;
  raise notice 'A7 ok: queue off -> switched_off';
end $$;
update pipeline.field_gap_queue_control set enabled = true;

-- B: worker reports. The scholarship share is spent (seeded before), the reads share has room.
do $$
declare v_id bigint; r record;
begin
  -- B1 scholarship_read with "applied": [] is recorded now; idle on a held paid lane is budget_held
  v_id := public.svc_worker_report_v1('scholarship_read', 200, 3548, '{"ok":true,"mode":"scholarship_read","items":0,"tally":{},"applied":[],"readVia":"scraper"}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.outcome <> 'idle' or r.lane_outcome <> 'budget_held' or r.hold_reason not like 'budget_held: no room left in today''s Firecrawl share for scholarships' then raise exception 'B1: % % %', r.outcome, r.lane_outcome, r.hold_reason; end if;
  raise notice 'B1 ok: scholarship_read recorded; idle while its share is spent -> budget_held (%)', r.hold_reason;
  -- B2 every item waited for credits: outcome stays zero_work_error, lane says budget_held
  v_id := public.svc_worker_report_v1('scholarship_ai', 200, 900, '{"ok":true,"items":2,"tally":{"waiting_scraper":2}}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.outcome <> 'zero_work_error' or r.lane_outcome <> 'budget_held' then raise exception 'B2: % %', r.outcome, r.lane_outcome; end if;
  raise notice 'B2 ok: all items waiting_scraper -> outcome zero_work_error (unchanged), lane budget_held';
  -- B3 a real error is failed
  v_id := public.svc_worker_report_v1('enrich_ai', 500, 10, '{"ok":false,"error":"svc_enrich_ai_record: canceling statement due to statement timeout"}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.outcome <> 'failed' or r.lane_outcome <> 'failed' or r.hold_reason not like '%statement timeout%' then raise exception 'B3: % % %', r.outcome, r.lane_outcome, r.hold_reason; end if;
  -- B4 a refusal with an error in the answer is failed, not held
  v_id := public.svc_worker_report_v1('discover', 200, 10, '{"ok":true,"providers":[],"errors":"map:credits_reserve then HTTP 502"}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.lane_outcome <> 'failed' then raise exception 'B4: % %', r.outcome, r.lane_outcome; end if;
  -- B5 work done
  v_id := public.svc_worker_report_v1('read', 200, 10, '{"ok":true,"items":5,"tally":{"read":5}}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.outcome <> 'succeeded' or r.lane_outcome <> 'done' or r.hold_reason is not null then raise exception 'B5: % %', r.outcome, r.lane_outcome; end if;
  -- B6 an idle stored-evidence mode is idle (nothing due), not held
  v_id := public.svc_worker_report_v1('read', 200, 10, '{"ok":true,"items":0,"firecrawlRemainingAboveReserve":3590}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.lane_outcome <> 'idle' or r.hold_reason <> 'nothing due' then raise exception 'B6: % %', r.lane_outcome, r.hold_reason; end if;
  -- B7 link_search with room in its share but today's pick cap reached -> source_limit; under the cap -> idle
  insert into pipeline.course_link_search select md5('s' || g)::uuid, null, 'sent', now() from generate_series(1, 200) g;
  v_id := public.svc_worker_report_v1('link_search', 200, 10, '{"ok":true,"picked":0,"searched":0,"found":0,"failed":0}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.lane_outcome <> 'source_limit' then raise exception 'B7: % %', r.lane_outcome, r.hold_reason; end if;
  update pipeline.course_link_search set sent_at = now() - interval '2 days';
  v_id := public.svc_worker_report_v1('link_search', 200, 10, '{"ok":true,"picked":0,"searched":0,"found":0,"failed":0}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.lane_outcome <> 'idle' then raise exception 'B7b: % %', r.lane_outcome, r.hold_reason; end if;
  -- B8 the monthly plan reserve holds every paid lane, with its own words
  insert into pipeline.layer2_acquisition_providers(id, provider_key, billing_config) values ('00000000-0000-0000-0000-00000000fc01', 'firecrawl', '{"monthly_vendor_units_limit": 5000, "stop_at_vendor_units_remaining": 1400}');
  insert into pipeline.vendor_credit_observations values ('00000000-0000-0000-0000-00000000fc01', 1400, now());
  v_id := public.svc_worker_report_v1('central_find', 200, 10, '{"ok":true,"providers":[]}'::jsonb, 'w');
  select * into r from pipeline.mode_outcome_ledger where mode_outcome_ledger.id = v_id;
  if r.lane_outcome <> 'budget_held' or r.hold_reason not like 'budget_held: Firecrawl monthly limit%' then raise exception 'B8: % %', r.lane_outcome, r.hold_reason; end if;
  delete from pipeline.vendor_credit_observations;
  raise notice 'B3-B8 ok: failed, failed (error with refusal), done, idle, source_limit then idle, monthly reserve held (%)', r.hold_reason;
end $$;

-- C: stored copies first while the scholarship lane is held; the usual order when it is not (or the switch is off)
do $$
declare v jsonb; n_att int;
begin
  v := public.svc_scholarship_ai_next(2);
  if jsonb_array_length(v) <> 1 or v->0->>'url' <> 'https://a.example/3' then raise exception 'C1: %', v; end if;
  select sum(attempts) into n_att from pipeline.scholarship_ai_queue where storage_path is null;
  if n_att <> 0 then raise exception 'C1: the waiting items used a try'; end if;
  raise notice 'C1 ok: held -> only the stored item is taken; the two without a copy stay queued, no try used';
  update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = 0;
  update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'lanes.stored_first_on';
  v := public.svc_scholarship_ai_next(2);
  if (select array_agg((x->>'url') order by x->>'url') from jsonb_array_elements(v) x) <> array['https://a.example/1', 'https://a.example/2'] then raise exception 'C2: %', v; end if;
  raise notice 'C2 ok: switch off -> the usual order (as before)';
  update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'lanes.stored_first_on';
  update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = 0;
  update pipeline.coverage_vendor_usage set at = now() - interval '3 days' where purpose = 'sch_scrape';
  v := public.svc_scholarship_ai_next(2);
  if (select array_agg((x->>'url') order by x->>'url') from jsonb_array_elements(v) x) <> array['https://a.example/1', 'https://a.example/2'] then raise exception 'C3: %', v; end if;
  raise notice 'C3 ok: share has room -> the usual order';
  update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = 0;
  update pipeline.coverage_vendor_usage set at = now() where purpose = 'sch_scrape';
  v := public.svc_scholarship_recheck_next(2);
  if jsonb_array_length(v) <> 1 or v->0->>'url' <> 'https://a.example/r2' then raise exception 'C4: %', v; end if;
  raise notice 'C4 ok: re-check held -> only the review with a stored copy';
end $$;

-- D: switched-off lanes are not called; held paid lanes are called unless lanes.skip_held_paid_calls is on
do $$
declare n int;
begin
  if not security.worker_lane_call_v1('link_search') then raise exception 'D1'; end if;
  update pipeline.course_link_search_settings set enabled = false;
  if security.worker_lane_call_v1('link_search') then raise exception 'D2: switched-off lane called'; end if;
  update pipeline.course_link_search_settings set enabled = true;
  if not security.worker_lane_call_v1('scholarship_read') then raise exception 'D3: held lane skipped while the switch is off'; end if;
  update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'lanes.skip_held_paid_calls';
  if security.worker_lane_call_v1('scholarship_read') or security.worker_lane_call_v1('scholarship_read') then raise exception 'D4: held lane called'; end if;
  select count(*) into n from pipeline.mode_outcome_ledger where mode = 'scholarship_read' and worker = 'lane-guard' and lane_outcome = 'budget_held';
  if n <> 1 then raise exception 'D4: % hold rows', n; end if;
  if not security.worker_lane_call_v1('read') then raise exception 'D5: a stored-evidence lane was held'; end if;
  if not security.worker_lane_call_v1('central_find') then raise exception 'D6: central_find held while its share has room'; end if;
  update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'lanes.skip_held_paid_calls';
  if exists (select 1 from cron.job where jobname in ('course-link-search-worker', 'central-find', 'coverage-discover', 'coverage-discover-2', 'scholarship-listing', 'scholarship-read')
              and command not like '%where security.worker_lane_call_v1(''%'')') then raise exception 'D7: a job is not guarded'; end if;
  if (select active from cron.job where jobname = 'coverage-discover') or not (select active from cron.job where jobname = 'scholarship-read') then raise exception 'D8: active state changed'; end if;
  raise notice 'D ok: switched-off link search not called; held lanes called while the switch is off; with it on, one hold row and no call; stored lanes always called; jobs guarded, active states kept';
end $$;

-- E: lane status (read-only) and the Pipeline yield screen function
do $$
declare v jsonb := security.lane_status_v1(); y jsonb; l jsonb;
begin
  if (select array_agg(x->>'lane' order by x->>'lane') from jsonb_array_elements(v->'lanes') x) <> array['ai_extraction', 'gap_queue', 'layer4_admission', 'paid_acquisition', 'stored_evidence'] then raise exception 'E1: %', v; end if;
  for l in select x from jsonb_array_elements(v->'lanes') x loop
    if not (l ? 'eligible' and l ? 'processed' and l ? 'held' and l ? 'failed' and l ? 'cost') then raise exception 'E1: lane % lacks a measure: %', l->>'lane', l; end if;
  end loop;
  l := (select x from jsonb_array_elements(v->'lanes') x where x->>'lane' = 'paid_acquisition');
  if (l->'held'->>'budget_held')::int < 2 or l->'live_hold'->>'sch_scrape' not like 'budget_held%' or (l->'eligible'->>'scholarship_items_waiting_for_a_page')::int <> 2 then raise exception 'E2: %', l; end if;
  l := (select x from jsonb_array_elements(v->'lanes') x where x->>'lane' = 'stored_evidence');
  if (l->>'processed')::int <> 5 then raise exception 'E3: %', l; end if;
  l := (select x from jsonb_array_elements(v->'lanes') x where x->>'lane' = 'gap_queue');
  if l->'last_run'->>'outcome' is null or (l->'held'->>'previous_run_open')::int <> 1 then raise exception 'E4: %', l; end if;
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true); perform set_config('request.rank', '5', true);
  y := public.admin_pipeline_yield('{}'::jsonb);
  if not (y ? 'lanes' and y ? 'lane_status' and jsonb_array_length(y->'lane_status'->'lanes') = 5) then raise exception 'E5: %', y; end if;
  raise notice 'E ok: five lanes with eligible, processed, held, failed and cost; paid lane held by reason (% held calls, % items waiting for a page); Pipeline yield carries lane_status',
    (select x->'held'->>'budget_held' from jsonb_array_elements(v->'lanes') x where x->>'lane' = 'paid_acquisition'), (select x->'eligible'->>'scholarship_items_waiting_for_a_page' from jsonb_array_elements(v->'lanes') x where x->>'lane' = 'paid_acquisition');
end $$;
