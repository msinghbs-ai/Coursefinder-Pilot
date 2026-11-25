-- CF-247 s1156 (S1-Build / Release Controller; Platform Admin 25 Nov 2026 14:36 AEDT guardrail: "daily spend well inside US$5.00").
-- Found live (25 Nov 2026 19:17 AEDT): Window 2 (s1155, the 267 waiting course entry reads on gpt-4.1-mini, whole page) made 447 calls for US$0.58 in its first
-- four minutes (1.13 million input tokens): the corrected-read pages are long and the whole page is read in many slices, so the window would cost about US$3,
-- not the US$0.48 estimated from the benchmark pages, and take platform AI spend for the day to the US$5.00 ceiling.
-- What this does: holds Window 2 now. The course entry route is switched off (its reads stop being handed out; reads already running finish) and Window 2's
-- on-demand request is closed, each logged with its reason. The waiting items stay waiting, nothing is lost or admitted, and the Platform Admin decides how the
-- rest is read.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: Window 2's open state (route on, request for its 22 providers).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

create temp table s1156_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1156_cron on commit drop as select count(*) n from cron.job where active;

do $act$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- fixed: the Platform Admin, who set the spend guardrail
  v_r constant text := 'Window 2 held: spend far above its estimate (US$0.58 in four minutes against US$0.48 for the window); the daily US$5.00 limit protected (Platform Admin guardrail 25 Nov 2026 14:36 AEDT)';
  r record; v_n int := 0;
begin
  update pipeline.ai_service_routes set enabled = false, reason = v_r, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements' and enabled;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', true), 'after', jsonb_build_object('enabled', false), 'reason', v_r, 'via', 'CF-247 s1156 migration'), v_pa);
  for r in select id from pipeline.on_demand_requests where state = 'open' and requested_via = 'claude_session' and reason like 'Platform Admin 25 Nov 2026 14:36 and 18:26 AEDT: Window 2,%' loop
    perform security.on_demand_close_v1(r.id); v_n := v_n + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_hold', 'course_entry_requirements', jsonb_build_object('reason', v_r, 'window', 2, 'requests_closed', v_n, 'by', 'migration CF-247 s1156'), v_pa);
end $act$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from pipeline.ai_service_routes where service_code = 'course_entry_requirements' and enabled) then raise exception 'post-check: the course entry route is still on'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1156_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1156_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
