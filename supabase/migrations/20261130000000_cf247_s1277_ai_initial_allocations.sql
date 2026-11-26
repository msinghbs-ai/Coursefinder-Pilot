-- CF-247 s1277 (S1-Build; Platform Admin via SS-Programme-Control 26 Nov 2026 21:43 AEDT, "Autonomous PIM operational verification": apply the initial
-- AI allocations, academic entry requirements US$5 a day and the overall platform AI ceiling US$10 a day; Firecrawl scheduled ceiling unchanged at 1,500
-- credits a day. Confirmed in this session by the Platform Admin, 26 Nov 2026 about 21:50 AEDT: "Raise both now").
-- What this does: the course entry route's daily cap goes US$1.00 -> US$5.00, and budgets.ai_daily_ceiling_usd (every AI lane, Stop mode, UTC day,
--   failed and retried calls counted) goes US$5 -> US$10, each with its reason and an audit event. Model (gpt-4.1-mini, qualified), qualification,
--   admission, account reserve and credit floor, country eligibility and every other route cap are unchanged.
-- G1: no job. G2: an existing setting and the route's own cap, changed with their reasons. G3: no consumer object touched (checked). Locks untouched.
-- Replaces: the US$1.00 entry route cap (s1261) and the US$5 platform AI ceiling. Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the route and setting updates

create temp table s1277_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if not exists (select 1 from pipeline.ai_service_routes where service_code = 'course_entry_requirements' and enabled and daily_usd_cap = 1.00 and cascade = array['gpt-4.1-mini']) then
    raise exception 'guard: the course entry route is not on gpt-4.1-mini at US$1.00';
  end if;
  if security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', -1) <> 5 then raise exception 'guard: the platform AI ceiling is not US$5'; end if;
end $g$;

do $a$
declare v_reason constant text := 'Platform Admin 26 Nov 2026 21:43 AEDT (SS-Programme-Control), confirmed in session: initial AI allocations, academic entry US$5 a day, platform AI ceiling US$10 a day (CF-247 s1277)';
begin
  update pipeline.ai_service_routes set daily_usd_cap = 5.00, reason = v_reason, changed_at = now()  -- fixed: the approved allocation is this route's cap value
   where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_routes', 'route_set', 'course_entry_requirements', jsonb_build_object('reason', v_reason, 'daily_usd_cap_before', 1.00, 'daily_usd_cap', 5.00, 'by', 'migration CF-247 s1277'), null);
  update pipeline.platform_toolset_settings set value = to_jsonb(10), reason = v_reason, updated_at = now()
   where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline.budgets.ai_daily_ceiling_usd', jsonb_build_object('before', 5, 'after', 10, 'reason', v_reason, 'via', 'CF-247 s1277 migration'), null);
end $a$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1277_guard) then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1277_guard) then raise exception 'post-check: manual locks changed'; end if;
  if security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', -1) <> 10 then raise exception 'post-check: the platform AI ceiling is not US$10'; end if;
  if (select daily_usd_cap from pipeline.ai_service_routes where service_code = 'course_entry_requirements') <> 5.00 then raise exception 'post-check: the course entry cap is not US$5.00'; end if;
  if (security.ai_route_v1('course_entry_requirements')->'cap'->>'usd')::numeric <> 5.00 then raise exception 'post-check: the route read does not show the new cap'; end if;
end $c$;
