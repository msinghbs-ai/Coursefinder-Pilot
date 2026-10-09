-- =====================================================================
-- CF-247 clean-up batch 4: retire old data-admission database objects
-- Approved: Platform Admin, 9 Oct 2026 ("Prepare it now")
--
-- What: drops 15 functions of the old data-admission system (Layer 2
-- operator/scope/wave schedulers, the Layer 3 enqueue service, the public
-- scholarship settings wrapper, and the onboarding-case RPCs); removes the
-- Layer 2 branch from pipeline.trg_submit_pilot_edge_execution (those
-- function names now fall through to 'function not allowlisted'); and
-- removes run-token allowlist rows for retired edge functions.
--
-- Why: the screens, cron jobs and edge functions that used these were
-- removed on 9 Oct 2026. Every dropped function was confirmed (read-only,
-- live, 9 Oct 2026) to have no caller outside this set, no cron job
-- (active or inactive), no trigger, no view, no policy and no default.
--
-- Not touched: no table is dropped, no data or history is deleted (apart
-- from the run-token allowlist rows below). Seed functions still reached
-- from live code (admin_read 'scholarship_runtime_uat', the scheduler
-- workflow bridges, layer2_background_scope_service) are kept for a later
-- batch. public.admin_read is not modified.
--
-- Guard: md5(pg_get_functiondef) of every function dropped or replaced is
-- checked against the live values read on 9 Oct 2026; any drift, or any
-- cron job naming one of them, aborts the migration. No CASCADE is used.
-- =====================================================================


do $guard$
declare
  v_expected constant jsonb := jsonb_build_object(
    'public.layer2_operator_sync_service(uuid,text,uuid,integer)', 'c27da2b32b749bbef4cd13221df4115c',
    'public.layer2_scope_profile_batch_bound_v1(uuid,uuid,uuid,uuid[])', '4bf0b89dbdbefde1f8e2593e7c2fd7dc',
    'security.layer2_refresh_scheduler_tick_impl(timestamp with time zone,integer,boolean)', 'af7bb2b4e8cb30b1653388684175f251',
    'public.svc_layer2_wave_scheduler()', '8ca5de9dc04eaf09903e4fcc993f2fe1',
    'security.layer2_fanout_scheduler_tick_impl(timestamp with time zone,integer,boolean)', 'e1e60fe60d13a344bfa7406efc2cd4c3',
    'security.layer2_qualification_finalizer_tick_impl()', '7551b7c37b29a73429c98e3c671e7688',
    'security.layer2_qualification_scheduler_tick_impl(integer)', '4e408460e6b732b255affbc58cde8467',
    'security.layer2_auto_discovery_tick_v1()', '4f22db661331a5de4da151cfe61663b8',
    'security.layer2_wave_request_close_stale_v1(boolean,interval)', 'c86df70aa732b9e0fb527834310d6cdf',
    'public.layer3_enqueue_eligible_layer2_service(integer)', '51c62d08661006688dd4e9d0226b2397',
    'public.scholarship_runtime_settings_write(jsonb)', '0e85c242f62753a4b64cc2e01425529e',
    'public.onboarding_cases_list(text,text,text,text,integer)', '1964fd14f667d8be95d6db8f5348015e',
    'public.onboarding_case_context(uuid)', 'fd7afc6c1b693f27a4484d0b59fd55d4',
    'public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text)', 'eeab1ab5b1d4331b708880f1f58a5ba5',
    'public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text)', '86a6577f484744585feebb7fe54c8152',
    'pipeline.trg_submit_pilot_edge_execution()', '9d4cf527ba29c2d306b21c4d5bd72ee6'
  );
  v_sig text;
  v_oid regprocedure;
  v_md5 text;
  v_hits text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      raise exception 'CF-247 batch 4 guard: % does not exist', v_sig;
    end if;
    v_md5 := md5(pg_get_functiondef(v_oid));
    if v_md5 <> v_expected->>v_sig then
      raise exception 'CF-247 batch 4 guard: % definition drifted (live %, expected %)', v_sig, v_md5, v_expected->>v_sig;
    end if;
  end loop;

  select string_agg(j.jobid::text || ':' || coalesce(j.jobname,'?') || ' -> ' || n.x, '; ')
    into v_hits
    from cron.job j
    join (values
  ('layer2_auto_discovery_tick_v1'),
  ('layer2_fanout_scheduler_tick_impl'),
  ('layer2_operator_sync_service'),
  ('layer2_qualification_finalizer_tick_impl'),
  ('layer2_qualification_scheduler_tick_impl'),
  ('layer2_refresh_scheduler_tick_impl'),
  ('layer2_scope_profile_batch_bound_v1'),
  ('layer2_wave_request_close_stale_v1'),
  ('layer3_enqueue_eligible_layer2_service'),
  ('onboarding_case_context'),
  ('onboarding_case_create'),
  ('onboarding_case_transition'),
  ('onboarding_cases_list'),
  ('scholarship_runtime_settings_write'),
  ('svc_layer2_wave_scheduler')
    ) n(x) on j.command ~ ('\m' || n.x || '\M');
  if v_hits is not null then
    raise exception 'CF-247 batch 4 guard: cron job(s) still reference retired functions: %', v_hits;
  end if;
end
$guard$;

-- Drops (no intra-set call edges were found, so order is free; listed
-- callers-first by original call direction). No CASCADE.
drop function public.layer2_operator_sync_service(uuid,text,uuid,integer);
drop function public.layer2_scope_profile_batch_bound_v1(uuid,uuid,uuid,uuid[]);
drop function security.layer2_refresh_scheduler_tick_impl(timestamp with time zone,integer,boolean);
drop function public.svc_layer2_wave_scheduler();
drop function security.layer2_fanout_scheduler_tick_impl(timestamp with time zone,integer,boolean);
drop function security.layer2_qualification_finalizer_tick_impl();
drop function security.layer2_qualification_scheduler_tick_impl(integer);
drop function security.layer2_auto_discovery_tick_v1();
drop function security.layer2_wave_request_close_stale_v1(boolean,interval);
drop function public.layer3_enqueue_eligible_layer2_service(integer);
drop function public.scholarship_runtime_settings_write(jsonb);
drop function public.onboarding_cases_list(text,text,text,text,integer);
drop function public.onboarding_case_context(uuid);
drop function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text);
drop function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text);

-- Replace the pilot edge-execution trigger function without the Layer 2
-- branch. Everything else is unchanged; SECURITY DEFINER and search_path kept.
-- Live md5 before: 9d4cf527ba29c2d306b21c4d5bd72ee6
-- Expected md5 after: 6e6f2d16653913617191a1520f26143f
CREATE OR REPLACE FUNCTION pipeline.trg_submit_pilot_edge_execution()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pipeline', 'public'
AS $function$
begin
 if new.function_name not in ('layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue') then new.status:='failed';new.error_text:='function not allowlisted';return new;end if;
 begin new.net_request_id:=pipeline.svc_pilot_invoke_edge(new.function_name,new.body);new.status:='submitted';new.submitted_at:=now();exception when others then new.status:='failed';new.error_text:=sqlerrm;end;return new;
end $function$;

do $post$
begin
  if md5(pg_get_functiondef('pipeline.trg_submit_pilot_edge_execution()'::regprocedure)) <> '6e6f2d16653913617191a1520f26143f' then
    raise exception 'CF-247 batch 4 post-check: trigger function definition not as intended';
  end if;
end
$post$;

-- Run-token allowlist rows for retired edge functions (11 names; rows
-- present on 9 Oct 2026: layer2-batch-runner, layer2-scholarship-extract-v2,
-- layer2-v2-diagnostic, scholarship-scope-job-execute).
delete from pipeline.pilot_nonce_functions where function_name in (
  'layer2-batch-runner',
  'layer2-scholarship-extract-v2',
  'layer2-v2-diagnostic',
  'scholarship-scope-job-execute',
  'layer2-extract',
  'layer2-course-fact-extract',
  'layer3-interpret',
  'layer2-sync-control',
  'layer2-config-control',
  'layer2-acquire',
  'scholarship-runtime-control'
);

-- Run-token rows for dormant edge functions whose only remaining database
-- reference after this migration is the allowlist inside
-- pipeline.svc_pilot_invoke_layer2 (its only surviving caller passes
-- 'scholarship-scope-job-execute'). Kept deliberately: layer2-acquire-v2
-- (layer2_shared_fetch_register, svc_pilot_invoke_layer2_v2) and
-- layer2-scope-discover-scheduled (security.layer2_discovery_* dispatchers).
-- These four edge functions are retired in the same release (source removed, deleted from the live project).
-- Also kept: layer2-provider-page-fanout, layer2-provider-asset-promote and layer2-hotcourses-directory-parse (provider
-- assets and logos, CF-101 and CF-102; a later decision).
delete from pipeline.pilot_nonce_functions where function_name in (
  'layer2-extract-v2',
  'layer2-course-fact-extract-v2',
  'layer2-scholarship-extract',
  'layer2-scholarship-catalogue-enumerate'
);

