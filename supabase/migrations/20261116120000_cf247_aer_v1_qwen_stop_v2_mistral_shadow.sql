-- CF-247 AER route change (Platform Admin 16 Nov 2026 16:52, decision "Stop Qwen, shadow Mistral").
-- Replaces: the Qwen3 30B qualifications of course_entry_requirements and entry_matrices (status unqualified; rows kept), and the cascade
--           [qwen3-30b, mistral-small-3.2] of entry_requirements_v2_shadow (now [mistral-small-3.2]).
-- Retires: nothing is dropped or deleted. The two AER v1 entry routes are switched off; their rows, caps and history stay.
--
-- Evidence (coursefinder-admin docs/platform/layer4-clearance-and-model-benchmark-2026-11-16.md, Admin #519):
--   * Qwen3 30B on the frozen 50-case AER set (run 20, aer-v2-course-v3): 2 right of 50, 18 timeouts of 40. Live on course_entry_requirements
--     in the 48 hours to 16 Nov 2026 16:52: 1,357 answers and 726 failed attempts. It is the only model qualified for the two AER v1 entry routes.
--   * No model passed the qualification gate (ai_eval.min_source_integrity_pct 100, max_error_rate_pts 10). Mistral Small 3.2 (run 19) had the
--     best source integrity of the models that answer (83.3%) and the lowest cost per right answer (US$0.0032), with error rate 30 points.
--
-- What this does:
--   1. AER v1 entry reading stops: course_entry_requirements and entry_matrices are switched off (security.ai_route_v1 then holds them: what is
--      already claimed finishes and records its cost; nothing new is handed out). Qwen3 30B is recorded unqualified on both, so neither route can
--      be switched on again until a model is qualified for it (public.admin_ai_route_set_v1 refuses a route with no qualified model).
--   2. AER v2 shadow: the cascade is Mistral Small 3.2 alone (no fallback across models: each result stays bound to one model). Qwen3 30B is
--      recorded unqualified there too. Mistral stays status pending, marked provisional, so the resolver still hands it nothing: the route and
--      aer.v2_shadow_on stay off. Qualifying it is a separate Platform Admin step after benchmark round 3 (long-page section reading) passes.
--   3. Each change is logged in pipeline.admin_control_events (area ai_models) with the reason.
-- Nothing switches on. No consumer API object is read or changed (G3). No new table, job or setting.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the route updates below

do $chg$
declare
  v_reason constant text := 'Platform Admin 16 Nov 2026 16:52: stop Qwen3 30B on AER entry reading (benchmark round 2, Admin #519: 2/50 right, 18 timeouts; live 726 failed attempts in 48 h); AER v1 entry reading waits for a qualified model';
  v_shadow constant text := 'Platform Admin 16 Nov 2026 16:52: Mistral Small 3.2 pinned alone on the AER v2 shadow (provisional; not qualified: round 2 source integrity 83.3%, gate 100%). Qualify only after round 3 passes.';
  r record;
begin
  -- 1. AER v1 entry routes off
  for r in select * from pipeline.ai_service_routes where service_code in ('course_entry_requirements', 'entry_matrices') for update loop
    update pipeline.ai_service_routes set enabled = false, reason = v_reason, changed_at = now(), changed_by = null where service_code = r.service_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('ai_models', 'route_set', r.service_code, jsonb_build_object(
              'before', jsonb_build_object('cascade', to_jsonb(r.cascade), 'daily_usd_cap', r.daily_usd_cap, 'daily_calls_cap', r.daily_calls_cap, 'enabled', r.enabled),
              'after', jsonb_build_object('cascade', to_jsonb(r.cascade), 'daily_usd_cap', r.daily_usd_cap, 'daily_calls_cap', r.daily_calls_cap, 'enabled', false),
              'resolver', r.resolver, 'reason', v_reason, 'by', 'migration 20261116120000'), null);
  end loop;

  -- Qwen3 30B unqualified on the two v1 routes and on the v2 shadow
  for r in select * from pipeline.ai_route_qualifications
            where model_code = 'qwen3-30b' and service_code in ('course_entry_requirements', 'entry_matrices', 'entry_requirements_v2_shadow') for update loop
    update pipeline.ai_route_qualifications set status = 'unqualified', provisional = false, qualified_at = null, qualified_by = null, note = v_reason, changed_at = now()
     where service_code = r.service_code and model_code = r.model_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('ai_models', 'route_qualification', r.service_code || ' / ' || r.model_code,
            jsonb_build_object('before', to_jsonb(r) - 'evidence_detail', 'after', 'unqualified', 'reason', v_reason, 'by', 'migration 20261116120000'), null);
  end loop;

  -- 2. AER v2 shadow: Mistral Small 3.2 alone, provisional, still off
  for r in select * from pipeline.ai_service_routes where service_code = 'entry_requirements_v2_shadow' for update loop
    update pipeline.ai_service_routes set cascade = array['mistral-small-3.2'], reason = v_shadow, changed_at = now(), changed_by = null
     where service_code = r.service_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('ai_models', 'route_set', r.service_code, jsonb_build_object(
              'before', jsonb_build_object('cascade', to_jsonb(r.cascade), 'daily_usd_cap', r.daily_usd_cap, 'daily_calls_cap', r.daily_calls_cap, 'enabled', r.enabled),
              'after', jsonb_build_object('cascade', to_jsonb(array['mistral-small-3.2']), 'daily_usd_cap', r.daily_usd_cap, 'daily_calls_cap', r.daily_calls_cap, 'enabled', r.enabled),
              'resolver', r.resolver, 'reason', v_shadow, 'by', 'migration 20261116120000'), null);
  end loop;
  for r in select * from pipeline.ai_route_qualifications where service_code = 'entry_requirements_v2_shadow' and model_code = 'mistral-small-3.2' for update loop
    update pipeline.ai_route_qualifications set status = 'pending', provisional = true, note = v_shadow, changed_at = now()
     where service_code = r.service_code and model_code = r.model_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('ai_models', 'route_qualification', r.service_code || ' / ' || r.model_code,
            jsonb_build_object('before', to_jsonb(r) - 'evidence_detail', 'after', 'pending (provisional)', 'reason', v_shadow, 'by', 'migration 20261116120000'), null);
  end loop;
end $chg$;

-- post-checks: everything above or nothing
do $post$
declare v text; g jsonb;
begin
  select string_agg(service_code, ', ') into v from pipeline.ai_service_routes
   where service_code in ('course_entry_requirements', 'entry_matrices') and enabled;
  if v is not null then raise exception 'post-check: still switched on: %', v; end if;
  if (select count(*) from pipeline.ai_service_routes where service_code in ('course_entry_requirements', 'entry_matrices')) <> 2 then
    raise exception 'post-check: an AER v1 entry route is missing';
  end if;
  select string_agg(service_code, ', ') into v from pipeline.ai_route_qualifications
   where model_code = 'qwen3-30b' and service_code in ('course_entry_requirements', 'entry_matrices', 'entry_requirements_v2_shadow') and status <> 'unqualified';
  if v is not null then raise exception 'post-check: Qwen3 30B not unqualified on: %', v; end if;
  if (select cascade from pipeline.ai_service_routes where service_code = 'entry_requirements_v2_shadow') is distinct from array['mistral-small-3.2'] then
    raise exception 'post-check: the AER v2 shadow cascade is not Mistral Small 3.2 alone';
  end if;
  if exists (select 1 from pipeline.ai_service_routes where service_code = 'entry_requirements_v2_shadow' and enabled) then
    raise exception 'post-check: the AER v2 shadow must stay switched off';
  end if;
  if exists (select 1 from pipeline.ai_route_qualifications where service_code = 'entry_requirements_v2_shadow' and status = 'qualified') then
    raise exception 'post-check: nothing is qualified on the AER v2 shadow by this change';
  end if;
  -- the resolver holds all three
  for v in select unnest(array['course_entry_requirements', 'entry_matrices', 'entry_requirements_v2_shadow']) loop
    g := security.ai_route_v1(v);
    if not coalesce((g->>'held')::boolean, false) then raise exception 'post-check: % is not held: %', v, g; end if;
  end loop;
end $post$;
