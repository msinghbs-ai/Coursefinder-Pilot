-- =====================================================================
-- CF-247 clean-up batch 7: unused background functions and the last old
-- Layer 2 qualification chain
-- Approved: Platform Admin, 9 Oct 2026 (multiple choice: "Check usage,
-- retire unused"; capability group "None of these"; Reset database
-- "Remove button and function").
--
-- What: drops 6 database functions (the scale-qualification
-- continuation service and dispatch, the provider attempt start and its two
-- URL helpers) and removes the run-token rows of the 8 edge functions
-- retired in the same release (source removed, deleted from the live
-- project): coursefacts-au-qut, coursefacts-au-rmit, coursefacts-au-uq, layer2-scale-qualify-scheduled, layer2-screenshot-backfill-scheduled, layer3-source-pattern-benchmark, layer1-au-completeness, pilot-reset.
-- pilot-reset is retired with the Settings > Go-live "Reset database"
-- control (removed from the screen in the same release).
--
-- Why: confirmed read-only, live, 9 Oct 2026: no cron job; no caller in
-- src/ (apart from the reset button, removed) or any other edge function;
-- every database caller of a dropped function is in this set; none of the
-- 8 edge functions was called in the edge logs from 30 Sep to 9 Oct 2026
-- or in the request logs.
--
-- Kept (unused but a capability, Platform Admin decision): the contact
-- discovery pair and the Layer 3 model benchmarks. Kept while Canada is
-- parked: every Canada function. Kept (external callers): the course APIs.
--
-- Not touched: no table is dropped; no data or history is deleted apart
-- from the run-token allowlist rows.
--
-- Guard: md5(pg_get_functiondef), carriage returns removed, of every
-- function dropped, checked against the live values read on 9 Oct 2026; any
-- drift, or any cron job naming a dropped function, aborts the migration.
-- No CASCADE is used.
-- =====================================================================

do $guard$
declare
  v_expected jsonb := jsonb_build_object(
    'public.layer2_qualification_continue_service(uuid)', '7514962e364c92b93dd5c530d253ca7f',
    'security.layer2_qualification_continue_impl(uuid)', 'd3c48714557a4eb7b43ede64b2d8a01b',
    'security.layer2_scale_qualification_dispatch(uuid)', '0c1d036d1ef297fa4c3bef743c4b95fd',
    'public.layer2_provider_attempt_start(uuid,uuid,text)', 'ea90e5f5e2cc6c941e1a071d92f683f7',
    'security.scheduler_workflow_queueable_url_allowed_v1(uuid,text)', '2bfb6a819e427d429aa28a01d60bbbaa',
    'security.scheduler_workflow_https_host_v1(text)', 'e8cd7e428b3862ee55e5fe9f2482bf1a'
  );
  v_sig text;
  v_oid regprocedure;
  v_md5 text;
  v_hits text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      raise exception 'CF-247 batch 7 guard: % does not exist', v_sig;
    end if;
    v_md5 := md5(replace(pg_get_functiondef(v_oid), E'\r', ''));
    if v_md5 <> v_expected->>v_sig then
      raise exception 'CF-247 batch 7 guard: % definition drifted (live %, expected %)', v_sig, v_md5, v_expected->>v_sig;
    end if;
  end loop;

  select string_agg(j.jobid::text || ':' || coalesce(j.jobname,'?') || ' -> ' || n.x, '; ')
    into v_hits
    from cron.job j
    join (values
  ('layer2_provider_attempt_start'),
  ('layer2_qualification_continue_impl'),
  ('layer2_qualification_continue_service'),
  ('layer2_scale_qualification_dispatch'),
  ('scheduler_workflow_https_host_v1'),
  ('scheduler_workflow_queueable_url_allowed_v1')
    ) n(x) on j.command ilike '%' || n.x || '%';
  if v_hits is not null then
    raise exception 'CF-247 batch 7 guard: cron job still names a dropped function: %', v_hits;
  end if;
end
$guard$;

drop function public.layer2_qualification_continue_service(uuid);
drop function security.layer2_qualification_continue_impl(uuid);
drop function security.layer2_scale_qualification_dispatch(uuid);
drop function public.layer2_provider_attempt_start(uuid,uuid,text);
drop function security.scheduler_workflow_queueable_url_allowed_v1(uuid,text);
drop function security.scheduler_workflow_https_host_v1(text);

delete from pipeline.pilot_nonce_functions where function_name in (
  'coursefacts-au-qut', 'coursefacts-au-rmit', 'coursefacts-au-uq', 'layer2-scale-qualify-scheduled', 'layer2-screenshot-backfill-scheduled', 'layer3-source-pattern-benchmark', 'layer1-au-completeness', 'pilot-reset'
);

do $post$
declare v_left text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_left
    from pg_proc p
   where p.proname in ('layer2_provider_attempt_start', 'layer2_qualification_continue_impl', 'layer2_qualification_continue_service', 'layer2_scale_qualification_dispatch', 'scheduler_workflow_https_host_v1', 'scheduler_workflow_queueable_url_allowed_v1');
  if v_left is not null then
    raise exception 'CF-247 batch 7 post-check: still present: %', v_left;
  end if;
end
$post$;
