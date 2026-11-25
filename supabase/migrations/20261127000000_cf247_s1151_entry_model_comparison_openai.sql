-- CF-247 s1151 (S1-Build / Release Controller; Platform Admin 25 Nov 2026 15:40 AEDT: "Stop further DeepSeek-only qualification cycles ... Use the existing
-- 83-page qualification cohort and previously paid answers to compare: openai/gpt-4.1-mini, openai/gpt-5-mini, openai/gpt-5-nano, if suitable for the existing
-- structured extraction contract. Reuse the existing DeepSeek, Qwen and MiMo results ... Use the same meaningful-content preprocessing, extraction instructions
-- and output schema for each model ... Do not introduce another reader, preprocessing engine, pipeline or qualification mechanism.")
-- What this does, in the existing qualification harness (job lean-qualify, pipeline.lean_qualify_cases, worker mode lean_qualify, worker v1.0.44):
--   1. adds openai/gpt-5-mini and openai/gpt-5-nano to the model catalogue as allowed (OpenRouter list prices of 25 Nov 2026), so the harness can read on them.
--      Allowed is not qualified: a model enters a route only once it is qualified for that service (public.admin_ai_route_set_v1). No route names them.
--   2. seeds run s1151-entry-qualify-openai-v6-2026-11-25: the same 83 benchmark pages and labels as s1150, on gpt-4.1-mini, gpt-5-mini and gpt-5-nano, page by
--      page with the three models in turn. Each page is read whole and as its lean-sections-v6 selection, with the same prompt (course-entry-v1), schema and
--      request (temperature 0, provider parameters required, provider data collection denied). A model the provider cannot serve under that request fails at $0.
--   3. raises batch.lean_qualify from 3 to 6 pages per worker call (inside its range 1 to 20), through the settings pattern with its reason.
-- Spend: estimated US$1.06 to US$1.66, stopped by the existing run ceiling reading.lean_qualify_ceiling_usd (US$2); platform daily limit US$5.
-- G1: no job. G2: the batch is the existing setting. G3: no consumer object changed (checked). Locks, cron and the course entry route checked unchanged.
-- Replaces: nothing (the s1125 and s1150 runs stay as recorded and are reused).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if exists (select 1 from pipeline.lean_qualify_cases where run_label = 's1150-entry-qualify-deepseek-v6-2026-11-25' and state = 'pending') then
    raise exception 'guard: the s1150 re-read is not complete';
  end if;
  if not exists (select 1 from pipeline.ai_model_catalogue where code = 'gpt-4.1-mini' and status = 'allowed') then raise exception 'guard: gpt-4.1-mini is not an allowed model'; end if;
end $g$;
create temp table s1151_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1151_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1151_route on commit drop as select enabled, daily_usd_cap, cascade from pipeline.ai_service_routes where service_code = 'course_entry_requirements';

do $cat$
declare v_reason constant text := 'Platform Admin 25 Nov 2026 15:40 AEDT: course entry requirements model comparison on the 83-page cohort (qualification harness only; in no route)';
begin
  insert into pipeline.ai_model_catalogue (code, family, label, model_identifier, input_usd_per_mtok, output_usd_per_mtok, price_checked_at, context_tokens, status, note, sort, reason, changed_at, changed_by)
  values ('gpt-5-mini', 'other', 'GPT-5 mini', 'openai/gpt-5-mini', 0.25, 2.00, now(), 400000, 'allowed', 'Course entry requirements comparison (CF-247 s1151); in no route; reasoning tokens are billed as output', 903, v_reason, now(), null),  -- fixed: OpenRouter list price, 25 Nov 2026
         ('gpt-5-nano', 'other', 'GPT-5 nano', 'openai/gpt-5-nano', 0.05, 0.40, now(), 400000, 'allowed', 'Course entry requirements comparison (CF-247 s1151); in no route; reasoning tokens are billed as output', 904, v_reason, now(), null)  -- fixed: OpenRouter list price, 25 Nov 2026
  on conflict (code) do nothing;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'catalogue_add', 'gpt-5-mini, gpt-5-nano', jsonb_build_object('reason', v_reason, 'status', 'allowed', 'routes', '[]'::jsonb,
          'approved_by', 'Platform Admin (chat, 25 Nov 2026 15:40 AEDT)', 'via', 'CF-247 s1151 migration'), null);
end $cat$;

do $seed$
declare v_run constant text := 's1151-entry-qualify-openai-v6-2026-11-25'; v_from constant text := 's1150-entry-qualify-deepseek-v6-2026-11-25';
  v_models constant text[] := array['gpt-4.1-mini', 'gpt-5-nano', 'gpt-5-mini'];
  v_reason constant text := 'Platform Admin 25 Nov 2026 15:40 AEDT: compare gpt-4.1-mini, gpt-5-mini and gpt-5-nano on the 83-page course entry cohort (same selection, prompt and schema)';
  v_n int; s record;
begin
  insert into pipeline.lean_qualify_cases (run_label, field, kind, source_ref, course_id, evidence_id, storage_path, gold, model_code, gold_source)
  select v_run, x.field, x.kind, x.course_id || ':' || m.code, x.course_id, x.evidence_id, x.storage_path, x.gold, m.code, x.gold_source
    from pipeline.lean_qualify_cases x cross join unnest(v_models) with ordinality m(code, k)
   where x.run_label = v_from and x.field = 'entry_requirements' and x.model_code = 'deepseek-v4-flash'
   order by md5(x.course_id::text), m.k
  on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n <> 249 then raise exception 's1151: % cases, not 83 pages on 3 models', v_n; end if;  -- fixed: the benchmark's size
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'seed', 'pipeline.lean_qualify_cases', jsonb_build_object('reason', v_reason, 'by', 'migration 20261127000000 (CF-247 s1151)', 'run', v_run, 'from_run', v_from,
          'models', to_jsonb(v_models), 'cases', v_n, 'estimate_usd', jsonb_build_object('low', 1.06, 'high', 1.66), 'ceiling_usd', security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0)), null);
  -- the harness batch, through the settings pattern
  select * into s from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'batch.lean_qualify' for update;
  if 6 < coalesce(s.min_value, 6) or 6 > coalesce(s.max_value, 6) then raise exception 's1151: 6 is outside batch.lean_qualify''s range'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(6), reason = v_reason, updated_at = now() where toolset_key = 'pipeline' and key = 'batch.lean_qualify';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline.batch.lean_qualify', jsonb_build_object('before', s.value, 'after', to_jsonb(6), 'reason', v_reason,
          'approved_by', 'Platform Admin (chat, 25 Nov 2026 15:40 AEDT)', 'via', 'CF-247 s1151 migration'), null);
  raise notice 's1151: % cases seeded', v_n;
end $seed$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1151_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1151_locks) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from pipeline.ai_service_routes r, s1151_route b where r.service_code = 'course_entry_requirements'
              and (r.enabled is distinct from b.enabled or r.daily_usd_cap is distinct from b.daily_usd_cap or r.cascade is distinct from b.cascade)) then
    raise exception 'post-check: the course entry route changed';
  end if;
  if exists (select 1 from pipeline.ai_service_routes r where 'gpt-5-mini' = any(r.cascade) or 'gpt-5-nano' = any(r.cascade)) then raise exception 'post-check: a route names a GPT-5 model'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
