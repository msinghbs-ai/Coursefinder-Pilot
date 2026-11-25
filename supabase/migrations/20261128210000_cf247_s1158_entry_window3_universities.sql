-- CF-247 s1158 (S1-Build / Release Controller; Platform Admin 26 Nov 2026 03:59 AEDT: "Prioritise cohorts closest to canonical admission ... Reuse existing
-- stored evidence, paid extraction results and qualified readers"; course entry route on gpt-4.1-mini approved 25 Nov 2026 18:26 AEDT; Authority Charter
-- 23 Nov 2026 item 2: Tier 2 micro-spend for Tier 1 universities without asking, inside US$5.00 a day).
-- The Window 2 remainder (s1157) finished at 04:53 AEDT: its 7 genuine re-reads went to Layer 4 (US$0.0104); no course entry read is left waiting.
-- Found live (rolled back, 26 Nov 2026 05:00 AEDT): 3,351 active AU courses open to international students were read by the $0 deterministic reader with no
-- admissible row and never had a course entry AI read; 1,219 of them have a course page whose identity is proven for entry requirements (CRICOS code,
-- adapter code or a person), 523 at university providers. Window 1 cost US$0.133 per million stored characters on this route.
-- What this does, live on apply, through the audited writers' checks and logs:
--   1. closes the Window 2 remainder: route off, its request closed;
--   2. opens Window 3: the university courses of that cohort whose stored page is shortest first, up to 9,000,000 stored characters in all (about US$1.20 at
--      the measured rate), each queued through the entry Read now (security.course_entry_read_enqueue_v1: stored course page, no scraper, Firecrawl 0); the
--      route on again with its US$0 daily cap (the scheduled reader stays held) and one on-demand request for their providers.
-- The route is switched off again once Window 3 is read (next change), or held at once if its spend runs above the measured rate.
-- G1: no job. G2: the route's own audited cap. G3: no consumer object changed (checked). Locks and cron checked unchanged. Nothing admitted here.
-- Replaces: the Window 2 remainder's open state.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and the window's queue writes

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if exists (select 1 from pipeline.field_enrich_items where field = 'entry_requirements' and state in ('queued', 'waiting', 'ai', 'leased')) then
    raise exception 'guard: a course entry read is still open; Window 3 opens only on an empty queue';
  end if;
end $g$;
create temp table s1158_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1158_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1158_c on commit drop as
  select co.id course_id, co.provider_id,
         (select a.chars from pipeline.aer_det_academic_pages a where a.course_id = co.id order by a.read_at desc nulls last limit 1) ch,
         (select g.identity_basis from pipeline.coverage_course_pages g where g.course_id = co.id and g.status = 'bound' order by g.bound_at desc nulls last limit 1) ib
    from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id join ref.provider_types pt on pt.id = p.provider_type_id
   where co.lifecycle_status = 'active' and k.iso_alpha2 = 'AU' and co.open_to_international is not false and pt.code = 'university'
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
     and not exists (select 1 from catalogue.course_entry_requirements q where q.course_id = co.id and q.status in ('active', 'proposed'))
     and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = co.id and i.field_code = 'course_entry_first_read')
     and exists (select 1 from pipeline.aer_det_academic_pages a where a.course_id = co.id and a.outcome is not null)
     and not exists (select 1 from pipeline.aer_det_academic_pages a where a.course_id = co.id and a.outcome is null)
     and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = co.id and f.field = 'entry_requirements' and (f.state in ('filled', 'review') or f.reason ~* 'does not state|no quoted|admission rules|superseded'))
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field in ('entry_requirements', 'all'));
create temp table s1158_w on commit drop as
  select course_id, provider_id, ch from (
    select c.*, sum(c.ch) over (order by c.ch, c.course_id) cum from s1158_c c
     where c.ch is not null and security.coverage_identity_allowed(c.provider_id, c.ib, 'entry_requirements')) z
   where cum <= 9000000;  -- fixed: the window's stored-character bound (about US$1.20 at the measured rate)

do $act$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- fixed: the Platform Admin, who approved the course entry windows
  v_r0 constant text := 'Window 2 remainder complete (7 to Layer 4); route switched off, its request closed';
  v_r constant text := 'Platform Admin 26 Nov 2026 03:59 AEDT (closest to admission) and 25 Nov 18:26 AEDT (gpt-4.1-mini, whole page): Window 3, university courses read by the deterministic reader with no admissible row and never AI-read, shortest stored page first; US$0 daily cap keeps the scheduled reader held';
  r record; rt pipeline.ai_service_routes%rowtype; v_od jsonb; v_prov uuid[]; v_n int := 0; v_chars bigint;
begin
  select count(*), sum(ch) into v_n, v_chars from s1158_w;
  if v_n < 200 or v_n > 700 then raise exception 'guard: Window 3 holds % courses, outside the planned 200 to 700', v_n; end if;  -- fixed: the planned window's size
  v_n := 0;
  -- 1. the Window 2 remainder closes
  select * into rt from pipeline.ai_service_routes where service_code = 'course_entry_requirements' for update;
  if rt.cascade <> array['gpt-4.1-mini'] or rt.daily_usd_cap <> 0 then raise exception 'guard: the route is not the course entry window route (gpt-4.1-mini, cap 0)'; end if;
  update pipeline.ai_service_routes set enabled = false, reason = v_r0, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', rt.enabled), 'after', jsonb_build_object('enabled', false), 'reason', v_r0, 'via', 'CF-247 s1158 migration'), v_pa);
  for r in select id from pipeline.on_demand_requests where state = 'open' and requested_via = 'claude_session' and reason like 'Platform Admin 26 Nov 2026 03:59 AEDT (resolve technical exceptions;%' loop
    perform security.on_demand_close_v1(r.id);
  end loop;
  -- 2. Window 3 opens
  update pipeline.ai_service_routes set enabled = true, reason = v_r, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', false), 'after', jsonb_build_object('enabled', true, 'cascade', to_jsonb(rt.cascade), 'daily_usd_cap', 0),
          'reason', v_r, 'approved_by', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT; 26 Nov 2026 03:59 AEDT)', 'via', 'CF-247 s1158 migration'), v_pa);
  select array_agg(distinct provider_id) into v_prov from s1158_w;
  v_od := security.on_demand_open_v1('claude_session', v_r, v_prov,
          jsonb_build_object('openrouter_usd', round(v_chars * 0.000000133, 2), 'stored_chars', v_chars, 'firecrawl_credits', 0, 'courses', (select count(*) from s1158_w), 'model', 'gpt-4.1-mini', 'input', 'whole page'), null, array['openrouter']);  -- fixed: the measured US$ per stored character
  for r in select course_id from s1158_w order by ch, course_id loop
    perform security.course_entry_read_enqueue_v1(r.course_id, v_pa, v_r);
    v_n := v_n + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_open', 'course_entry_requirements', jsonb_build_object('reason', v_r, 'window', 3, 'courses', v_n, 'providers', cardinality(v_prov), 'stored_chars', v_chars,
          'estimate_usd', round(v_chars * 0.000000133, 2), 'on_demand', v_od->'id', 'by', 'migration CF-247 s1158'), v_pa);
  raise notice 's1158: window 3 % courses at % providers, % chars, request %', v_n, cardinality(v_prov), v_chars, v_od->'id';
end $act$;

do $c$
declare v_api jsonb; v_r jsonb; v_od uuid[]; v_out int;
begin
  if (select count(*) from cron.job where active) <> (select n from s1158_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1158_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_r := security.ai_enrich_routes_v1();
  if not coalesce(v_r->'limit_fields' ? 'entry_requirements', false) then raise exception 'post-check: the entry field is not held by the US$0 cap: %', v_r; end if;
  v_od := array(select jsonb_array_elements_text(v_r->'on_demand_providers'))::uuid[];
  select count(*) into v_out from pipeline.field_enrich_items f
   where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased') and f.provider_id = any(v_od)
     and not exists (select 1 from s1158_w w where w.course_id = f.course_id);
  if v_out > 0 then raise exception 'post-check: % entry items outside Window 3 could be read under an open request', v_out; end if;
  if (select count(*) from pipeline.field_enrich_items f join s1158_w w on w.course_id = f.course_id where f.field = 'entry_requirements' and f.state = 'queued') <> (select count(*) from s1158_w) then
    raise exception 'post-check: Window 3 is not all queued';
  end if;
  if security.ai_route_v1('course_entry_requirements')->>'held' is distinct from 'true' then raise exception 'post-check: the scheduled reader is not held by the cap'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
