-- CF-247 Remove Parse.bot completely (Platform Admin, 1 Oct 2026: "Parse.bot remove completely").
-- Parse.bot was never used to fetch a page (0 attempts, 0 shared fetches, 0 run items, 0 benchmark or trial rows).
-- It was used only by the ranking "import from publisher URL" route, which is removed with it; ranking imports are
-- file upload only. Evidence already captured (one superseded QS 2026 file) and the rankings applied from it are kept.
--   1. Its 2,098 source routes, the provider row and its stored key are deleted.
--   2. Two functions that named it are edited in place, each behind an md5(prosrc) guard.

do $$
declare v_id uuid; v_secret uuid;
begin
  select id, vault_secret_id into v_id, v_secret from pipeline.layer2_acquisition_providers where provider_key = 'parsebot';
  if v_id is null then raise notice 'parsebot already removed'; return; end if;
  if exists (select 1 from pipeline.layer2_provider_attempts where acquisition_provider_id = v_id)
     or exists (select 1 from pipeline.layer2_shared_fetches where acquisition_provider_id = v_id)
     or exists (select 1 from pipeline.layer2_run_items where selected_provider_id = v_id)
     or exists (select 1 from pipeline.layer2_scope_wave_items where selected_provider_id = v_id)
     or exists (select 1 from pipeline.layer2_provider_benchmark_observations where acquisition_provider_id = v_id)
     or exists (select 1 from pipeline.layer2_provider_trial_results where acquisition_provider_id = v_id) then
    raise exception 'Parse.bot has fetch history; refusing to delete it';
  end if;
  delete from pipeline.layer2_provider_environment_gates where acquisition_provider_id = v_id;
  delete from pipeline.layer2_profile_provider_routes where acquisition_provider_id = v_id;
  delete from pipeline.layer2_acquisition_providers where id = v_id;
  if v_secret is not null then delete from vault.secrets where id = v_secret; end if;
end $$;

do $$
declare v_def text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.scheduler_workflow_route_gap_count_v1(text,text,uuid)'::regprocedure) <> 'f86a250be8b9ef8e4a3372bf6d563f88' then
    raise exception 'security.scheduler_workflow_route_gap_count_v1 changed since it was checked; not editing';
  end if;
  v_def := pg_get_functiondef('security.scheduler_workflow_route_gap_count_v1(text,text,uuid)'::regprocedure);
  if position(E'\n             and lower(coalesce(pc->>''provider_key'',''''))<>''parsebot''' in v_def) = 0 then raise exception 'expected text not found (route gap count)'; end if;
  execute replace(v_def, E'\n             and lower(coalesce(pc->>''provider_key'',''''))<>''parsebot''', '');

  if (select md5(prosrc) from pg_proc where oid = 'public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean)'::regprocedure) <> '717772bc7b7bd0d4b99997ab298b407e' then
    raise exception 'public.scholarship_international_detail_batch_service changed since it was checked; not editing';
  end if;
  v_def := pg_get_functiondef('public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean)'::regprocedure);
  if position('''direct-http'',''parsebot'',''firecrawl''' in v_def) = 0 then raise exception 'expected text not found (scholarship detail)'; end if;
  v_def := replace(v_def, '''direct-http'',''parsebot'',''firecrawl''', '''direct-http'',''firecrawl''');
  v_def := replace(v_def, ' when ''parsebot'' then 20', '');
  execute v_def;
end $$;
