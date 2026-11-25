-- CF-247 s1155 (S1-Build / Release Controller; Platform Admin 25 Nov 2026 14:36 AEDT Decisions 2 and 3, and 18:26 AEDT: gpt-4.1-mini on the whole page).
-- Window 1 (s1154, the 172 courses) finished cleanly at 18:49 AEDT: every item resolved, none failed or left queued (91 held by the course-page identity
-- gate E16 before any AI call; 81 read: 7 filled, 3 to Layer 4, 60 "the page does not state it", 6 no quoted requirement, 5 no row met the admission rules).
-- This migration, through the audited writers' checks and logs (public.admin_ai_route_set_v1; their sign-in needs a person's session):
--   1. closes Window 1: the route is switched off and Window 1's on-demand request is closed;
--   2. opens Window 2 for the 267 course entry items already waiting for the AI read (state ai: 252 corrected reads D-R2 and 15 S2-AER s1115 re-reads,
--      22 providers, one item per course, reconciled live at 19:00 AEDT): the route is switched on again with its US$0 daily cap (the scheduled reader stays
--      held) and one on-demand request (OpenRouter only, Firecrawl 0) is opened for the 22 providers. Nothing is queued: the items are already waiting.
-- Post-checks: only the 267 can be handed out; the scheduler is held; G3 75/48; locks and cron unchanged. Estimate US$0.48 (US$0.0018 a page).
-- G1: no job. G2: the route's own audited cap. Nothing admitted by this migration; reads go through the existing gates and Layer 4.
-- Replaces: Window 1's open state (route on, request for its 20 providers).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1155_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1155_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1155_w1 on commit drop as
  select f.id, f.state from pipeline.field_enrich_items f join pipeline.admin_jobs j on j.id = f.job_id
   where f.field = 'entry_requirements' and j.reason like 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT): Window 1,%';
create temp table s1155_w2 on commit drop as
  select f.id, f.course_id, f.provider_id from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('ai', 'leased');

do $act$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- fixed: the Platform Admin, who approved the windows
  v_r1 constant text := 'Platform Admin 25 Nov 2026 14:36 and 18:26 AEDT: Window 1 (the 172 courses) complete; route switched off, its request closed';
  v_r2 constant text := 'Platform Admin 25 Nov 2026 14:36 and 18:26 AEDT: Window 2, the 267 waiting course entry reads (22 providers) on gpt-4.1-mini, whole page, under one scoped on-demand request; US$0 daily cap keeps the scheduled reader held';
  rt pipeline.ai_service_routes%rowtype; v_od jsonb; v_prov uuid[]; r record; v_closed int := 0;
begin
  -- Window 1 finished: 172 items, none open
  if (select count(*) from s1155_w1) <> 172 then raise exception 'guard: Window 1 has % items, not 172', (select count(*) from s1155_w1); end if;  -- fixed: the approved window's size
  if exists (select 1 from s1155_w1 where state in ('queued', 'waiting', 'ai', 'leased')) then raise exception 'guard: Window 1 is not finished'; end if;
  -- Window 2 is the reconciled queue
  if (select count(*) from s1155_w2) <> 267 or (select count(distinct course_id) from s1155_w2) <> 267 or (select count(distinct provider_id) from s1155_w2) <> 22 then  -- fixed: the reconciled backlog
    raise exception 'guard: the waiting queue is not the reconciled 267 items at 22 providers (% items)', (select count(*) from s1155_w2);
  end if;
  if exists (select 1 from s1155_w2 w join s1155_w1 x on x.id = w.id) then raise exception 'guard: a Window 1 item is in the Window 2 queue'; end if;
  -- 1. Window 1 closes: route off, its request closed
  select * into rt from pipeline.ai_service_routes where service_code = 'course_entry_requirements' for update;
  if not rt.enabled or rt.cascade <> array['gpt-4.1-mini'] or rt.daily_usd_cap <> 0 then raise exception 'guard: the route is not Window 1''s (on, gpt-4.1-mini, cap 0)'; end if;
  update pipeline.ai_service_routes set enabled = false, reason = v_r1, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', true), 'after', jsonb_build_object('enabled', false),
          'reason', v_r1, 'approved_by', 'Platform Admin (chat, 25 Nov 2026 14:36 and 18:26 AEDT)', 'via', 'CF-247 s1155 migration'), v_pa);
  for r in select id from pipeline.on_demand_requests where state = 'open' and requested_via = 'claude_session' and reason like 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT): Window 1,%' loop
    perform security.on_demand_close_v1(r.id); v_closed := v_closed + 1;
  end loop;
  if v_closed <> 1 then raise exception 'guard: % Window 1 requests closed, not 1', v_closed; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_close', 'course_entry_requirements', jsonb_build_object('reason', v_r1, 'window', 1, 'items', 172,
          'outcomes', (select jsonb_object_agg(state, n) from (select state, count(*) n from s1155_w1 group by 1) z), 'by', 'migration CF-247 s1155'), v_pa);
  -- 2. Window 2 opens: route on again (cap 0), one request for the 22 providers
  update pipeline.ai_service_routes set enabled = true, reason = v_r2, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', false), 'after', jsonb_build_object('enabled', true, 'cascade', to_jsonb(array['gpt-4.1-mini']), 'daily_usd_cap', 0),
          'reason', v_r2, 'approved_by', 'Platform Admin (chat, 25 Nov 2026 14:36 and 18:26 AEDT)', 'via', 'CF-247 s1155 migration'), v_pa);
  select array_agg(distinct provider_id) into v_prov from s1155_w2;
  v_od := security.on_demand_open_v1('claude_session', v_r2, v_prov,
          jsonb_build_object('openrouter_usd', 0.48, 'calls', 300, 'firecrawl_credits', 0, 'items', 267, 'model', 'gpt-4.1-mini', 'input', 'whole page'), null, array['openrouter']);  -- fixed: the approved window's estimate
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_open', 'course_entry_requirements', jsonb_build_object('reason', v_r2, 'window', 2, 'items', 267, 'providers', cardinality(v_prov), 'on_demand', v_od->'id',
          'approved_by', 'Platform Admin (chat, 25 Nov 2026 14:36 and 18:26 AEDT)', 'by', 'migration CF-247 s1155'), v_pa);
  raise notice 's1155: window 1 closed, window 2 opened (request %)', v_od->'id';
end $act$;

do $c$
declare v_api jsonb; v_r jsonb; v_od uuid[]; v_out int;
begin
  if (select count(*) from cron.job where active) <> (select n from s1155_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1155_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_r := security.ai_enrich_routes_v1();
  if not coalesce(v_r->'limit_fields' ? 'entry_requirements', false) then raise exception 'post-check: the entry field is not held by the US$0 cap: %', v_r; end if;
  v_od := array(select jsonb_array_elements_text(v_r->'on_demand_providers'))::uuid[];
  select count(*) into v_out from pipeline.field_enrich_items f
   where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased') and f.provider_id = any(v_od)
     and not exists (select 1 from s1155_w2 w where w.id = f.id);
  if v_out > 0 then raise exception 'post-check: % entry items outside the 267 could be read under an open request', v_out; end if;
  if security.ai_route_v1('course_entry_requirements')->>'held' is distinct from 'true' then raise exception 'post-check: the scheduled reader is not held by the cap'; end if;
  if security.pipeline_num_v1('reading.course_entry_sections_on', 1) <> 0 then raise exception 'post-check: course entry reads do not send the whole page'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
