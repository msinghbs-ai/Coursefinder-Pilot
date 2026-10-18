-- CF-247 Phase 5 (19 Oct 2026). Platform Admin 09:29: "Phase 5: hardening, plus retiring the leftovers above", "keep in mind the Consumer API
-- wont get affected".
-- 1 New objects in schema public are no longer open to the anonymous role by default (default privileges of role postgres: functions,
--   tables, sequences). Existing grants are not changed, so every consumer API function, table and grant stays exactly as it is.
-- 2 The two scholarship-AI wrappers in public (an admin screen's calls) are no longer executable by the anonymous role; signed-in staff
--   and the service role keep them.
-- 3 32 helper functions without a fixed search_path get one (public, extensions: the path they resolve with today), so a caller cannot
--   change what they call. Left out on purpose: security.provider_presentable_name and security.place_presentable, which consumer API
--   functions call (Decision 266); none of the 32 is in the consumer API baseline or called from it, directly or through other functions.
-- 4 Leftovers recorded: the 6 Layer 3 edge functions (no source in git; archived on branch edge-live-snapshot/39172698955) and the 12
--   Canadian probe stubs, removed from live through the deploy workflow's delete list; security.zz_probe_v1 (a one-off probe, executable
--   by postgres only) is marked retiring and is dropped by the Platform Admin's paste file.
-- Replaces: nothing
-- Retires: edge functions layer3-cf245-tuition-benchmark, -contact-benchmark, -intake-benchmark, -model-routing, -work-dispatch, -work-interpret and the
--   12 layer1-ca-* probe and audit stubs (retired); security.zz_probe_v1 (retiring, paste file)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): no consumer function, table, column or grant is altered, and the
-- post-check requires security.consumer_api_check_v1() to report no drift.

do $pre$
declare v_bad text;
begin
  -- the consumer API must be clean before this change, so any drift afterwards would be this change's
  if jsonb_array_length(security.consumer_api_check_v1() -> 'drift') <> 0 then raise exception 'consumer API already drifting; not applying'; end if;
  if md5(pg_get_functiondef('public.scholarship_ai_control_read(text)'::regprocedure)) <> 'ff1b194e901cb8cd360b95709e25e8ce'
     or md5(pg_get_functiondef('public.scholarship_ai_run_create(text,text,uuid,integer,text,boolean)'::regprocedure)) <> 'ed720742ec2658b017ac825236dcca10' then
    raise exception 'scholarship-AI wrappers differ from the definitions this change reviewed';
  end if;
  select string_agg(b.name, ', ') into v_bad from pipeline.consumer_api_baseline b
   where b.name ~ '(admin_automation_control|admin_automations_read|admin_data_flag|admin_layer3_control|admin_priority_|admin_requeue|admin_scholarship_publishing|layer3_routing_service_guard|au_regional_class|automation_batch|consumer_api_compare_v1|coverage_norm_url|coverage_slug|coverage_text_tokens|coverage_tuition_target_v1|english_title_|institution_name_key|layer3_task_job|provider_english_flagged|quoted_study_periods|review_reason_key|scholarship_level_codes|scholarship_tier_text|site_host|scholarship_ai_control_read|scholarship_ai_run_create)';
  if v_bad is not null then raise exception 'consumer API object in this change: %', v_bad; end if;
end $pre$;

-- 1 default privileges in public: nothing new is open to anon by default
alter default privileges for role postgres in schema public revoke execute on functions from anon;
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;

-- 2 scholarship-AI wrappers: signed-in staff and the service role only
revoke execute on function public.scholarship_ai_control_read(text) from anon;
revoke execute on function public.scholarship_ai_run_create(text,text,uuid,integer,text,boolean) from anon;

-- 3 fixed search_path (the path these resolve with today)
do $sp$
declare v_sig text; v_n int := 0;
begin
  foreach v_sig in array array[
    'public.admin_automation_control(text,text,jsonb)', 'public.admin_automations_read()', 'public.admin_data_flag_resolve(uuid,text,jsonb)',
    'public.admin_data_flags_read(jsonb)', 'public.admin_layer3_control_read()', 'public.admin_layer3_control(text,jsonb)',
    'public.admin_priority_control(text,jsonb)', 'public.admin_priority_read()', 'public.admin_priority_search(text,text)',
    'public.admin_requeue_read()', 'public.admin_requeue(text,jsonb)', 'public.admin_scholarship_publishing_read()',
    'public.admin_scholarship_publishing(text,jsonb)', 'public.layer3_routing_service_guard()',
    'security.au_regional_class(text,text)', 'security.automation_batch(text)', 'security.consumer_api_compare_v1(jsonb,jsonb)',
    'security.coverage_norm_url(text)', 'security.coverage_slug(text)', 'security.coverage_text_tokens(text)',
    'security.coverage_tuition_target_v1(jsonb)', 'security.english_title_key(text)', 'security.english_title_overlap(text,text)',
    'security.english_title_tokens(text)', 'security.institution_name_key(text)', 'security.layer3_task_job(text)',
    'security.provider_english_flagged(jsonb)', 'security.quoted_study_periods(text)', 'security.review_reason_key(text)',
    'security.scholarship_level_codes(jsonb)', 'security.scholarship_tier_text(numeric[],numeric[],boolean)', 'security.site_host(text)'] loop
    if exists (select 1 from pg_proc p, unnest(coalesce(p.proconfig, '{}')) c where p.oid = v_sig::regprocedure and c like 'search_path=%') then
      raise exception '% already has a search_path', v_sig;
    end if;
    execute format('alter function %s set search_path = public, extensions', v_sig::regprocedure);
    v_n := v_n + 1;
  end loop;
  if v_n <> 32 then raise exception 'expected 32 functions, did %', v_n; end if;  -- fixed: the reviewed list
end $sp$;

-- 4 leftovers
insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in, note) values
 ('edge_function', 'layer3-cf245-tuition-benchmark', 'L3 interpret', 'Layer 3 model benchmark (retired Layer 3)', 'retired', 'live-only', 'Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list'),
 ('edge_function', 'layer3-contact-benchmark', 'L3 interpret', 'Layer 3 model benchmark (retired Layer 3)', 'retired', 'live-only', 'Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list'),
 ('edge_function', 'layer3-intake-benchmark', 'L3 interpret', 'Layer 3 model benchmark (retired Layer 3)', 'retired', 'live-only', 'Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list'),
 ('edge_function', 'layer3-model-routing', 'L3 interpret', 'Layer 3 model routing (retired Layer 3)', 'retired', 'live-only', 'Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list'),
 ('edge_function', 'layer3-work-dispatch', 'L3 interpret', 'Layer 3 work dispatch (retired Layer 3)', 'retired', 'live-only', 'Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list'),
 ('edge_function', 'layer3-work-interpret', 'L3 interpret', 'Layer 3 work interpretation (retired Layer 3)', 'retired', 'live-only', 'Phase 5, 19 Oct 2026: no source in git; archived on edge-live-snapshot/39172698955; removed from live by the deploy workflow delete list'),
 ('edge_function', 'layer1-ca-ab-alis-probe', 'L1 register', 'Canadian source probe stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-cpic-probe', 'L1 register', 'Canadian source probe stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-ircc-nvit-probe', 'L1 register', 'Canadian source probe stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-mb-designation-probe', 'L1 register', 'Canadian source probe stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-qc-pdf-probe', 'L1 register', 'Canadian source probe stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-qc-pdf-probe2', 'L1 register', 'Canadian source probe stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-sk-sitemap-probe', 'L1 register', 'Canadian source probe stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-qc-audit', 'L1 register', 'Canadian source audit stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-qc-parse-audit', 'L1 register', 'Canadian source audit stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-qc-prefix-audit', 'L1 register', 'Canadian source audit stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-qc-strict-audit', 'L1 register', 'Canadian source audit stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live'),
 ('edge_function', 'layer1-ca-northern-code-audit', 'L1 register', 'Canadian source audit stub (returned 410)', 'retired', 'stub', 'Phase 5, 19 Oct 2026: removed from git and from live')
on conflict (kind, name) do update set status = 'retired', note = excluded.note, updated_at = now();

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in, replaced_by, retire_after, note) values
 ('function', 'security.zz_probe_v1', 'Operations', 'One-off probe left behind (executable by postgres only)', 'retiring', 'live-only', 'nothing', current_date,
  'Phase 5, 19 Oct 2026: dropped by the Platform Admin''s paste file')
on conflict (kind, name) do update set status = 'retiring', replaced_by = 'nothing', retire_after = current_date, note = excluded.note, updated_at = now();

do $post$
declare v_left int;
begin
  if jsonb_array_length(security.consumer_api_check_v1() -> 'drift') <> 0 then raise exception 'post-check: consumer API drift'; end if;
  if has_function_privilege('anon', 'public.scholarship_ai_control_read(text)', 'execute')
     or has_function_privilege('anon', 'public.scholarship_ai_run_create(text,text,uuid,integer,text,boolean)', 'execute') then
    raise exception 'post-check: anon still executes the scholarship-AI wrappers';
  end if;
  if exists (select 1 from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace
              and d.defaclacl::text ~ '(^|[{,])anon=') then raise exception 'post-check: default privileges still open to anon'; end if;
  select count(*) into v_left from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'security') and p.prokind = 'f'
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
  if v_left <> 2 then raise exception 'post-check: % functions without a search_path (expected the 2 consumer helpers)', v_left; end if;  -- fixed: the two consumer helpers
end $post$;
