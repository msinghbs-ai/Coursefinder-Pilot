-- CF-247 s1157 (S1-Build / Release Controller; Platform Admin 26 Nov 2026 03:59 AEDT: "S1-Build prioritises extraction and admission bottlenecks ...
-- Resolve technical exceptions automatically wherever authorised"; Window 2 approved 25 Nov 2026 14:36 (Decision 3) and 18:26 AEDT, held by s1156).
-- Found live (rolled back, 26 Nov 2026 04:30 AEDT): of the 137 course entry reads left waiting by the Window 2 hold, 130 are corrected reads (D-R2) whose
-- Layer 4 item is already superseded. Reading them is paid and then refused when recorded (105 were refused that way on 25 Nov). 90 of the 137 still sit
-- in state leased on leases that ended at 19:23 AEDT on 25 Nov. Only 7 are genuine: the S2-AER s1115 re-reads (Admin #1054) at 4 providers.
-- What this does, live on apply:
--   1. the 130 are skipped without a read, with the reason (the same outcome the recorder would give, at $0);
--   2. the 7 genuine reads are released from their ended leases (back to waiting for the AI read);
--   3. the 7 are read under the Window 2 containment: the course entry route on (gpt-4.1-mini, whole page, daily cap US$0, so the scheduled reader stays
--      held) and one on-demand request (OpenRouter only, Firecrawl 0) for their 4 providers. Estimate US$0.05.
-- The route is switched off again once they are read (next change). Nothing is admitted here; reads go through the existing gates and Layer 4.
-- G1: no job. G2: the route's own audited cap. G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: Window 2's held remainder (route off, 137 waiting).
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
create temp table s1157_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1157_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1157_w on commit drop as
  select f.id, f.state, f.provider_id, j.reason, substring(j.reason from '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid tgt
    from pipeline.field_enrich_items f join pipeline.admin_jobs j on j.id = f.job_id
   where f.field = 'entry_requirements' and f.state in ('ai', 'leased');
create temp table s1157_gone on commit drop as
  select w.id from s1157_w w where w.reason like 'Corrected read (D-R2) of Layer 4 item %' and w.tgt is not null
     and not exists (select 1 from pipeline.layer4_review_items l where l.id = w.tgt and l.status = 'pending');
create temp table s1157_keep on commit drop as select w.id, w.provider_id from s1157_w w where w.id not in (select id from s1157_gone);

do $act$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- fixed: the Platform Admin, who approved Window 2
  v_r constant text := 'Platform Admin 26 Nov 2026 03:59 AEDT (resolve technical exceptions; Window 2 approved 25 Nov 14:36 and 18:26 AEDT): Window 2 remainder, the genuine S2-AER s1115 re-reads on gpt-4.1-mini, whole page, under one scoped on-demand request; US$0 daily cap keeps the scheduled reader held';
  v_skip int; v_rel int; v_prov uuid[]; v_od jsonb; rt pipeline.ai_service_routes%rowtype;
begin
  if (select count(*) from s1157_w) > 137 then raise exception 'guard: % course entry reads wait, more than the 137 Window 2 left', (select count(*) from s1157_w); end if;  -- fixed: the held remainder
  if (select count(*) from s1157_keep) > 10 then raise exception 'guard: % reads would be read, more than the genuine remainder', (select count(*) from s1157_keep); end if;  -- fixed: the planned window's size
  -- 1. superseded corrections: skipped, never read
  update pipeline.field_enrich_items f set state = 'skipped', leased_until = null, updated_at = now(),
         reason = 'corrected read (D-R2) not read: its Layer 4 item is no longer pending (superseded); a read would be refused when recorded'
   where f.id in (select id from s1157_gone);
  get diagnostics v_skip = row_count;
  -- 2. the genuine reads leave their ended leases
  update pipeline.field_enrich_items f set state = 'ai', leased_until = null, updated_at = now()
   where f.id in (select id from s1157_keep) and f.state = 'leased' and f.leased_until < now();
  get diagnostics v_rel = row_count;
  -- 3. route on (cap 0) and one request for their providers
  select * into rt from pipeline.ai_service_routes where service_code = 'course_entry_requirements' for update;
  if rt.cascade <> array['gpt-4.1-mini'] or rt.daily_usd_cap <> 0 then raise exception 'guard: the route is not Window 2''s (gpt-4.1-mini, cap 0)'; end if;
  if not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'course_entry_requirements' and q.model_code = 'gpt-4.1-mini' and q.status = 'qualified') then raise exception 'guard: gpt-4.1-mini is not qualified'; end if;
  update pipeline.ai_service_routes set enabled = true, reason = v_r, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', rt.enabled), 'after', jsonb_build_object('enabled', true, 'cascade', to_jsonb(rt.cascade), 'daily_usd_cap', 0),
          'reason', v_r, 'approved_by', 'Platform Admin (chat, 25 Nov 2026 14:36 and 18:26 AEDT; 26 Nov 2026 03:59 AEDT)', 'via', 'CF-247 s1157 migration'), v_pa);
  select array_agg(distinct provider_id) into v_prov from s1157_keep;
  if v_prov is not null then
    v_od := security.on_demand_open_v1('claude_session', v_r, v_prov,
            jsonb_build_object('openrouter_usd', 0.05, 'calls', 40, 'firecrawl_credits', 0, 'items', (select count(*) from s1157_keep), 'model', 'gpt-4.1-mini', 'input', 'whole page'), null, array['openrouter']);  -- fixed: the remainder's estimate
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_open', 'course_entry_requirements', jsonb_build_object('reason', v_r, 'window', '2-remainder', 'skipped_superseded', v_skip, 'released_leases', v_rel,
          'to_read', (select count(*) from s1157_keep), 'providers', coalesce(cardinality(v_prov), 0), 'on_demand', v_od->'id', 'by', 'migration CF-247 s1157'), v_pa);
  raise notice 's1157: % skipped, % released, % to read (request %)', v_skip, v_rel, (select count(*) from s1157_keep), v_od->'id';
end $act$;

do $c$
declare v_api jsonb; v_r jsonb; v_od uuid[]; v_out int;
begin
  if (select count(*) from cron.job where active) <> (select n from s1157_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1157_locks) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from pipeline.field_enrich_items where id in (select id from s1157_gone) and state <> 'skipped') then raise exception 'post-check: a superseded correction is still waiting'; end if;
  v_r := security.ai_enrich_routes_v1();
  if not coalesce(v_r->'limit_fields' ? 'entry_requirements', false) then raise exception 'post-check: the entry field is not held by the US$0 cap: %', v_r; end if;
  v_od := array(select jsonb_array_elements_text(v_r->'on_demand_providers'))::uuid[];
  select count(*) into v_out from pipeline.field_enrich_items f
   where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased') and f.provider_id = any(v_od)
     and f.id not in (select id from s1157_keep);
  if v_out > 0 then raise exception 'post-check: % entry items outside the genuine remainder could be read under an open request', v_out; end if;
  if security.ai_route_v1('course_entry_requirements')->>'held' is distinct from 'true' then raise exception 'post-check: the scheduled reader is not held by the cap'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
