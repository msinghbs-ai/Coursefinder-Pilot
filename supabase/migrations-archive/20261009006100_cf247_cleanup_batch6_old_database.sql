-- =====================================================================
-- CF-247 clean-up batch 6: the last old Layer 2 discovery, acquisition
-- and provider-asset chains
-- Approved: Platform Admin, 9 Oct 2026 (multiple choice: "Check usage,
-- then retire").
--
-- What: drops 19 database functions and removes the run-token rows of 5
-- edge functions retired in the same release (source removed from the
-- repository and deleted from the live project):
--   edge: layer2-provider-page-fanout, layer2-provider-asset-promote, layer2-hotcourses-directory-parse, layer2-acquire-v2, layer2-scope-discover-scheduled
--   database: the provider page fan-out and logo promote apply RPCs; the
--   old acquisition invoke and shared-fetch register (with the scholarship
--   shared-fetch helper); the discovery and scope dispatch chain (dispatch,
--   scope dispatch v1/v2 in both schemas, the bound and context-bound
--   wrappers, the scale-pattern dispatch, the source-pattern hand-off and
--   the provider-catalogue submit); the profile binding snapshot only that
--   chain used; and three admin read helpers no operation calls any more
--   (scholarship runtime, Layer 2 profiles, Layer 2 config).
--
-- Why: confirmed read-only, live, 9 Oct 2026: no cron job (active or
-- inactive); no caller in src/ or any other edge function; every database
-- caller of a dropped function is itself in this set; none of the 5 edge
-- functions was called in the last 24 hours of logs, none is in
-- pipeline.edge_request_log or platform_edge_calls, and the last queued
-- call of any of them was layer2-acquire-v2 on 24 Aug 2026. Logos keep
-- working: the panel uploads through provider-asset-upload and reads
-- through provider-asset-access, which are not touched.
--
-- Kept (still referenced by layer2-scale-qualify-scheduled, a later
-- decision): layer2_provider_attempt_start,
-- scheduler_workflow_queueable_url_allowed_v1, scheduler_workflow_https_host_v1.
--
-- Not touched: no table is dropped, no data or history is deleted apart
-- from the 5 run-token allowlist rows.
--
-- Guard: md5(pg_get_functiondef), carriage returns removed, of every
-- function dropped, checked against the live values read on 9 Oct 2026; any
-- drift, or any cron job naming a dropped function, aborts the migration.
-- No CASCADE is used.
-- =====================================================================

do $guard$
declare
  v_expected jsonb := jsonb_build_object(
    'public.layer2_provider_page_fanout_apply(uuid,jsonb,jsonb)', 'ed266479da8efa5821124e6c667f469e',
    'public.layer2_provider_asset_promote_apply(uuid,text,text,text,integer,integer)', 'e3294aa382ed261c1573bce11cb4c4b2',
    'pipeline.svc_pilot_invoke_layer2_v2(jsonb)', 'efad98344c45525a1be1df37b0baa366',
    'public.scholarship_catalogue_shared_fetch_from_evidence(uuid,uuid)', 'e10409f3e47c9b461dd02cb6be2781f1',
    'public.layer2_shared_fetch_register(text,uuid,text,text,uuid,uuid,integer)', '8b4b1ac9ded7ee119d6213625f0e6374',
    'public.layer2_provider_catalogue_submit_v1(uuid,text,text,boolean)', 'b727567f9843069db4b13c0954f865a1',
    'security.layer2_provider_catalogue_submit_impl(uuid,uuid,text,text,boolean,text)', 'e8611a210999938a4f811e9abc7c7cf7',
    'public.layer3_source_pattern_handoff_service(uuid,uuid)', 'bb4b52a4df3c30334f574986f9f346a5',
    'security.layer2_scale_pattern_dispatch(uuid,integer)', 'd04d70da4c3cc5942896a9c88e0c0f8c',
    'public.layer2_discovery_scope_dispatch_bound_v1(uuid,uuid,uuid,uuid[],integer,uuid[])', 'f511caac7e76df0b3ec2dbb225b423db',
    'public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer)', '32d2bef8093cbfc91002e9dc2660ff5b',
    'public.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[])', '47d8fb4a94c87ae1eb8da38026172ac9',
    'security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[])', 'c7640d386bf66e415771f3469d292e57',
    'security.layer2_discovery_scope_dispatch(uuid,uuid[],integer)', 'f0422f04c03ad3cbb3523a0f3fa8391a',
    'security.layer2_discovery_dispatch(uuid,integer)', 'bfb3874c22a6ddc81cbb45ccd404c2be',
    'security.scheduler_workflow_profile_binding_snapshot_v1(uuid,uuid[],uuid[])', 'fe60ebd2c8040fb74c803c72874f1c92',
    'security.admin_scholarship_runtime_read(jsonb)', '73bb9096efa4d7705a9408e98332bdc1',
    'security.admin_layer2_profiles_page(jsonb)', '59cc65c927c1cc08e0644cb534029285',
    'security.admin_layer2_config_read(text,jsonb)', 'bd8fa77a70e5917a6c90cc0244b3e432'
  );
  v_sig text;
  v_oid regprocedure;
  v_md5 text;
  v_hits text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      raise exception 'CF-247 batch 6 guard: % does not exist', v_sig;
    end if;
    v_md5 := md5(replace(pg_get_functiondef(v_oid), E'\r', ''));
    if v_md5 <> v_expected->>v_sig then
      raise exception 'CF-247 batch 6 guard: % definition drifted (live %, expected %)', v_sig, v_md5, v_expected->>v_sig;
    end if;
  end loop;

  select string_agg(j.jobid::text || ':' || coalesce(j.jobname,'?') || ' -> ' || n.x, '; ')
    into v_hits
    from cron.job j
    join (values
  ('admin_layer2_config_read'),
  ('admin_layer2_profiles_page'),
  ('admin_scholarship_runtime_read'),
  ('layer2_discovery_context_scope_bound_v1'),
  ('layer2_discovery_dispatch'),
  ('layer2_discovery_scope_dispatch'),
  ('layer2_discovery_scope_dispatch_bound_v1'),
  ('layer2_discovery_scope_dispatch_v2'),
  ('layer2_provider_asset_promote_apply'),
  ('layer2_provider_catalogue_submit_impl'),
  ('layer2_provider_catalogue_submit_v1'),
  ('layer2_provider_page_fanout_apply'),
  ('layer2_scale_pattern_dispatch'),
  ('layer2_shared_fetch_register'),
  ('layer3_source_pattern_handoff_service'),
  ('scheduler_workflow_profile_binding_snapshot_v1'),
  ('scholarship_catalogue_shared_fetch_from_evidence'),
  ('svc_pilot_invoke_layer2_v2')
    ) n(x) on j.command ilike '%' || n.x || '%';
  if v_hits is not null then
    raise exception 'CF-247 batch 6 guard: cron job still names a dropped function: %', v_hits;
  end if;
end
$guard$;

drop function public.layer2_provider_page_fanout_apply(uuid,jsonb,jsonb);
drop function public.layer2_provider_asset_promote_apply(uuid,text,text,text,integer,integer);
drop function pipeline.svc_pilot_invoke_layer2_v2(jsonb);
drop function public.scholarship_catalogue_shared_fetch_from_evidence(uuid,uuid);
drop function public.layer2_shared_fetch_register(text,uuid,text,text,uuid,uuid,integer);
drop function public.layer2_provider_catalogue_submit_v1(uuid,text,text,boolean);
drop function security.layer2_provider_catalogue_submit_impl(uuid,uuid,text,text,boolean,text);
drop function public.layer3_source_pattern_handoff_service(uuid,uuid);
drop function security.layer2_scale_pattern_dispatch(uuid,integer);
drop function public.layer2_discovery_scope_dispatch_bound_v1(uuid,uuid,uuid,uuid[],integer,uuid[]);
drop function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer);
drop function public.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]);
drop function security.layer2_discovery_scope_dispatch_v2(uuid,uuid[],integer,uuid,uuid[]);
drop function security.layer2_discovery_scope_dispatch(uuid,uuid[],integer);
drop function security.layer2_discovery_dispatch(uuid,integer);
drop function security.scheduler_workflow_profile_binding_snapshot_v1(uuid,uuid[],uuid[]);
drop function security.admin_scholarship_runtime_read(jsonb);
drop function security.admin_layer2_profiles_page(jsonb);
drop function security.admin_layer2_config_read(text,jsonb);

delete from pipeline.pilot_nonce_functions where function_name in (
  'layer2-provider-page-fanout', 'layer2-provider-asset-promote', 'layer2-hotcourses-directory-parse', 'layer2-acquire-v2', 'layer2-scope-discover-scheduled'
);

do $post$
declare v_left text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_left
    from pg_proc p
   where p.proname in ('admin_layer2_config_read', 'admin_layer2_profiles_page', 'admin_scholarship_runtime_read', 'layer2_discovery_context_scope_bound_v1', 'layer2_discovery_dispatch', 'layer2_discovery_scope_dispatch', 'layer2_discovery_scope_dispatch_bound_v1', 'layer2_discovery_scope_dispatch_v2', 'layer2_provider_asset_promote_apply', 'layer2_provider_catalogue_submit_impl', 'layer2_provider_catalogue_submit_v1', 'layer2_provider_page_fanout_apply', 'layer2_scale_pattern_dispatch', 'layer2_shared_fetch_register', 'layer3_source_pattern_handoff_service', 'scheduler_workflow_profile_binding_snapshot_v1', 'scholarship_catalogue_shared_fetch_from_evidence', 'svc_pilot_invoke_layer2_v2');
  if v_left is not null then
    raise exception 'CF-247 batch 6 post-check: still present: %', v_left;
  end if;
  if not exists (select 1 from pg_proc where proname='layer2_provider_attempt_start') then
    raise exception 'CF-247 batch 6 post-check: layer2_provider_attempt_start must be kept';
  end if;
end
$post$;
