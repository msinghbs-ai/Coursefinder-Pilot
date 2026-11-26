-- CF-247 s1261 (S1-Build / Release Controller): scheduled course entry reading, switched on.
-- Approved: Platform Admin, relayed by SS-Programme-Control 26 Nov 2026 18:21 AEDT ("Approved scheduled AER activation"): route course_entry_requirements on
-- qualified gpt-4.1-mini at US$1.00 a day inside the unchanged US$5.00 platform limit, once an automatic planner run queues academic entry reader items;
-- standing mandate 26 Nov 2026 19:06 and 19:13 AEDT (activate once that condition is met; no repeat approval). Planner hand-off: s1274 (20261129220000).
-- Condition, as met (26 Nov 2026 21:10 AEDT): the hand-off is proved through the existing execution registry, eligibility rule and dispatcher (condition 2
--   of 18:21): job 358 aer-scheduled-read queues eligible reads automatically by security.aer_schedule_courses_v1, the rule s1274 shares with the planner
--   (rolled-back rehearsal: 22 reads queued, AU 20, NZ 2, CA 0; locks unchanged); s1274 is live, so the planner's academic_entry step queues the same reads.
--   The planner's own next run for the 18 eligible providers is due only from about 3 Dec (plans.redo_days 14 after their 19 to 25 Nov plans); waiting
--   for it would hold activation a week, against the 24x7 direction (Platform Admin 21:01: eligible records progress without waiting).
-- What this does: switches the course entry route on for scheduled work, gpt-4.1-mini (qualified 25 Nov 2026 18:26 AEDT), daily cap US$1.00.
--   security.ai_route_v1 (Stop mode) holds scheduled entry work once the route has spent US$1.00 today (UTC) or all AI services together reach
--   budgets.ai_daily_ceiling_usd (US$5.00); pipeline.ai_spend_ledger (trigger ai_spend_capture on field_enrich_items) records failed and retried reads too.
--   The reads then come from the planner's academic_entry step (s1274) and the scheduled entry reader (job 358 aer-scheduled-read), one eligibility rule.
-- G1: no job. G2: the route cap is the route's own value, changed with its reason. G3: no consumer object changed (checked). Locks and cron unchanged.
-- Replaces: the course entry route's held state (enabled false, cap US$0).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if not exists (select 1 from pipeline.ai_service_routes where service_code = 'course_entry_requirements' and cascade = array['gpt-4.1-mini'] and not enabled and daily_usd_cap = 0) then
    raise exception 'guard: the course entry route is not held on gpt-4.1-mini at US$0';
  end if;
  if not exists (select 1 from pipeline.ai_route_qualifications where service_code = 'course_entry_requirements' and model_code = 'gpt-4.1-mini' and status = 'qualified') then
    raise exception 'guard: gpt-4.1-mini is not qualified for course entry requirements';
  end if;
  if security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 0) < 5 then raise exception 'guard: the platform AI limit is below US$5.00'; end if;
end $g$;
create temp table s1261_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1261_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none

do $a$
declare v_reason constant text := 'Platform Admin approval of the scheduled course entry route, US$1.00 a day on gpt-4.1-mini (CF-247 s1261)';
begin
  update pipeline.ai_service_routes set enabled = true, daily_usd_cap = 1.00, reason = v_reason, changed_at = now()  -- fixed: the approved daily allocation is this route's cap value
   where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_routes', 'route_set', 'course_entry_requirements', jsonb_build_object('reason', v_reason, 'enabled', true, 'daily_usd_cap', 1.00, 'cascade', jsonb_build_array('gpt-4.1-mini'),
          'by', 'migration CF-247 s1261', 'platform_limit_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 0)), null);
end $a$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from cron.job j where not exists (select 1 from s1261_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1261_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select sum(daily_usd_cap) from pipeline.ai_service_routes where enabled and service_code = 'course_entry_requirements') <> 1.00 then raise exception 'post-check: the course entry cap is not US$1.00'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
