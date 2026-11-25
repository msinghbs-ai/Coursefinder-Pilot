-- CF-247 s1190 (S1-Build / Release Controller; Platform Admin 25 Nov 2026 14:36 AEDT: the course entry route is switched off once each window is read).
-- Window 4 (s1159, 131 courses) finished at 06:11 AEDT: 93 to Layer 4 (711 proposed rows; the existing fast admission takes those that qualify), 36 held by
-- the read gate or the admission rules, 2 failed; US$0.7516. No course entry read is left waiting.
-- What this does: switches the course entry route off and closes Window 4's on-demand request, each logged. Nothing else changes.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: Window 4's open state.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

create temp table s1190_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1190_cron on commit drop as select count(*) n from cron.job where active;

do $act$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- fixed: the Platform Admin, who approved the course entry windows
  v_r constant text := 'Window 4 complete (93 to Layer 4, 36 held, 2 failed, US$0.75); route switched off, its request closed';
  r record; v_n int := 0;
begin
  if exists (select 1 from pipeline.field_enrich_items where field = 'entry_requirements' and state in ('queued', 'waiting', 'ai', 'leased')) then
    raise exception 'guard: a course entry read is still open; Window 4 is not finished';
  end if;
  update pipeline.ai_service_routes set enabled = false, reason = v_r, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements' and enabled;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', true), 'after', jsonb_build_object('enabled', false), 'reason', v_r, 'via', 'CF-247 s1190 migration'), v_pa);
  for r in select id from pipeline.on_demand_requests where state = 'open' and requested_via = 'claude_session' and reason like 'Platform Admin 26 Nov 2026 03:59 AEDT (closest to admission)%Window 4,%' loop
    perform security.on_demand_close_v1(r.id); v_n := v_n + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_close', 'course_entry_requirements', jsonb_build_object('reason', v_r, 'window', 4, 'requests_closed', v_n, 'by', 'migration CF-247 s1190'), v_pa);
end $act$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from pipeline.ai_service_routes where service_code = 'course_entry_requirements' and enabled) then raise exception 'post-check: the course entry route is still on'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1190_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1190_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
