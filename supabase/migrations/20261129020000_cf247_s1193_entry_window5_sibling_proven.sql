-- CF-247 s1193 (S1-Build / Release Controller; Platform Admin 26 Nov 2026 03:59 AEDT: "Prioritise cohorts closest to canonical admission ... Reuse existing
-- stored evidence, paid extraction results and qualified readers"; course entry route on gpt-4.1-mini approved 25 Nov 2026 18:26 AEDT; Authority Charter
-- 23 Nov 2026 item 2: Tier 2 micro-spend for Tier 1 universities without asking, inside US$5.00 a day).
-- Platform Admin decision 26 Nov 2026 06:57 AEDT (option 2) and 08:19 AEDT: "After successful verification, evaluate the remaining identity-held cohorts
-- automatically under the approved rule". s1192 (live 08:39) put the proven sibling page in the AI read gate and AI recorder; the machine admission admitted the
-- first s1191 proposal under it (course 082307B, 2 active rows, read back through the website course read).
-- Found live (rolled back, 26 Nov 2026 08:50 AEDT): 346 AU courses (134 providers) read by the deterministic reader with no admissible row and never AI-read now
-- pass security.entry_sibling_identity_v1 (which includes the read gate's own page check), 7,740,487 stored characters.
-- What this does, live on apply, through the audited writers' checks and logs:
--   1. closes nothing open (Window 4 was closed by s1190; the route is off);
--   2. opens Window 5: those courses, shortest stored page first, up to 9,000,000 stored characters, each through the entry Read now (stored page, no scraper,
--      Firecrawl 0); route on with its US$0 daily cap (scheduled reader held) and one on-demand request for their providers. About US$1.00 at most.
-- The route is switched off again once Window 5 is read (next change), or held at once if its spend runs above the measured rate.
-- G1: no job. G2: the route's own audited cap. G3: no consumer object changed (checked). Locks and cron checked unchanged. Nothing admitted here.
-- Replaces: nothing open (the course entry route is off).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '300s';  -- fixed: the course page check over the cohort and the window's queue writes

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if exists (select 1 from pipeline.field_enrich_items where field = 'entry_requirements' and state in ('queued', 'waiting', 'ai', 'leased')) then
    raise exception 'guard: a course entry read is still open; Window 5 opens only on an empty queue';
  end if;
end $g$;
create temp table s1193_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1193_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none (existing jobs are switched routinely by their own dispatchers while this runs)
create temp table s1193_c on commit drop as
  select co.id course_id, co.provider_id,
         (select a.chars from pipeline.aer_det_academic_pages a where a.course_id = co.id order by a.read_at desc nulls last limit 1) ch,
         (select g.identity_basis from pipeline.coverage_course_pages g where g.course_id = co.id and g.status = 'bound' order by g.bound_at desc nulls last limit 1) ib
    from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
   where co.lifecycle_status = 'active' and k.iso_alpha2 = 'AU' and co.open_to_international is not false
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
     and not exists (select 1 from catalogue.course_entry_requirements q where q.course_id = co.id and q.status in ('active', 'proposed'))
     and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = co.id and i.field_code = 'course_entry_first_read')
     and exists (select 1 from pipeline.aer_det_academic_pages a where a.course_id = co.id and a.outcome is not null)
     and not exists (select 1 from pipeline.aer_det_academic_pages a where a.course_id = co.id and a.outcome is null)
     and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = co.id and f.field = 'entry_requirements' and (f.state in ('filled', 'review', 'queued', 'waiting', 'ai', 'leased') or f.reason ~* 'does not state|no quoted|admission rules|superseded'))
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field in ('entry_requirements', 'all'));
create temp table s1193_w on commit drop as
  select course_id, provider_id, ch from (
    select c.*, sum(c.ch) over (order by c.ch, c.course_id) cum from s1193_c c
     where c.ch is not null and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.course_id and g.status = 'bound' and g.read_status = 'read'
             and coalesce((security.entry_sibling_identity_v1(c.course_id, g.url)->>'ok')::boolean, false))) z
   where cum <= 9000000;  -- fixed: the window's stored-character bound (about US$1.20 at the measured rate)

do $act$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- fixed: the Platform Admin, who approved the course entry windows
  v_r0 constant text := 'No window open (s1190 closed Window 4); route stays off until Window 5 opens';
  v_r constant text := 'Platform Admin 26 Nov 2026 03:59 AEDT (closest to admission) and 25 Nov 18:26 AEDT (gpt-4.1-mini, whole page): Window 5, courses read by the deterministic reader with no admissible row and never AI-read whose page passes the proven sibling page (Platform Admin 26 Nov 06:57, option 2), shortest stored page first; US$0 daily cap keeps the scheduled reader held';
  r record; rt pipeline.ai_service_routes%rowtype; v_od jsonb; v_prov uuid[]; v_n int := 0; v_chars bigint;
begin
  select count(*), sum(ch) into v_n, v_chars from s1193_w;
  if v_n < 150 or v_n > 500 then raise exception 'guard: Window 5 holds % courses, outside the planned 150 to 500', v_n; end if;  -- fixed: the planned window's size
  v_n := 0;
  -- 1. nothing open: the route is confirmed off before Window 5
  select * into rt from pipeline.ai_service_routes where service_code = 'course_entry_requirements' for update;
  if rt.cascade <> array['gpt-4.1-mini'] or rt.daily_usd_cap <> 0 then raise exception 'guard: the route is not the course entry window route (gpt-4.1-mini, cap 0)'; end if;
  update pipeline.ai_service_routes set enabled = false, reason = v_r0, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', rt.enabled), 'after', jsonb_build_object('enabled', false), 'reason', v_r0, 'via', 'CF-247 s1193 migration'), v_pa);
  for r in select id from pipeline.on_demand_requests where state = 'open' and requested_via = 'claude_session' and reason like 'Platform Admin 26 Nov 2026 03:59 AEDT (closest to admission) and 25 Nov 18:26 AEDT (gpt-4.1-mini, whole page): Window 4,%' loop
    perform security.on_demand_close_v1(r.id);
  end loop;
  -- 2. Window 5 opens
  update pipeline.ai_service_routes set enabled = true, reason = v_r, changed_at = now(), changed_by = v_pa where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object('before', jsonb_build_object('enabled', false), 'after', jsonb_build_object('enabled', true, 'cascade', to_jsonb(rt.cascade), 'daily_usd_cap', 0),
          'reason', v_r, 'approved_by', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT; 26 Nov 2026 03:59 AEDT)', 'via', 'CF-247 s1193 migration'), v_pa);
  select array_agg(distinct provider_id) into v_prov from s1193_w;
  v_od := security.on_demand_open_v1('claude_session', v_r, v_prov,
          jsonb_build_object('openrouter_usd', round(v_chars * 0.000000133, 2), 'stored_chars', v_chars, 'firecrawl_credits', 0, 'courses', (select count(*) from s1193_w), 'model', 'gpt-4.1-mini', 'input', 'whole page'), null, array['openrouter']);  -- fixed: the measured US$ per stored character
  for r in select course_id from s1193_w order by ch, course_id loop
    perform security.course_entry_read_enqueue_v1(r.course_id, v_pa, v_r);
    v_n := v_n + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_open', 'course_entry_requirements', jsonb_build_object('reason', v_r, 'window', 5, 'courses', v_n, 'providers', cardinality(v_prov), 'stored_chars', v_chars,
          'estimate_usd', round(v_chars * 0.000000133, 2), 'on_demand', v_od->'id', 'by', 'migration CF-247 s1193'), v_pa);
  raise notice 's1193: window 5 % courses at % providers, % chars, request %', v_n, cardinality(v_prov), v_chars, v_od->'id';
end $act$;

do $c$
declare v_api jsonb; v_r jsonb; v_od uuid[]; v_out int;
begin
  if exists (select 1 from cron.job j where not exists (select 1 from s1193_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1193_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_r := security.ai_enrich_routes_v1();
  if not coalesce(v_r->'limit_fields' ? 'entry_requirements', false) then raise exception 'post-check: the entry field is not held by the US$0 cap: %', v_r; end if;
  v_od := array(select jsonb_array_elements_text(v_r->'on_demand_providers'))::uuid[];
  select count(*) into v_out from pipeline.field_enrich_items f
   where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased') and f.provider_id = any(v_od)
     and not exists (select 1 from s1193_w w where w.course_id = f.course_id);
  if v_out > 0 then raise exception 'post-check: % entry items outside Window 5 could be read under an open request', v_out; end if;
  if (select count(*) from pipeline.field_enrich_items f join s1193_w w on w.course_id = f.course_id where f.field = 'entry_requirements' and f.state = 'queued') <> (select count(*) from s1193_w) then
    raise exception 'post-check: Window 5 is not all queued';
  end if;
  if security.ai_route_v1('course_entry_requirements')->>'held' is distinct from 'true' then raise exception 'post-check: the scheduled reader is not held by the cap'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
