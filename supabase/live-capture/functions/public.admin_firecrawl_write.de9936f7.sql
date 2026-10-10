CREATE OR REPLACE FUNCTION public.admin_firecrawl_write(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_uc text := p_args->>'use_case';
        v_run uuid; v_n int; v_settings jsonb; v_cap numeric; v_budget jsonb; v_pid uuid; v_inc boolean; v_r pipeline.firecrawl_runs%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'target' then
    v_pid := (p_args->>'provider_id')::uuid;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    if p_args->'included' is null or jsonb_typeof(p_args->'included') = 'null' then
      update pipeline.firecrawl_targets set included = (select t.rule_match from security.firecrawl_targets_v1() t where t.provider_id = v_pid), reason = 'back to the rule: ' || v_reason, set_by = auth.uid(), set_at = now() where provider_id = v_pid;
    else
      v_inc := (p_args->>'included')::boolean;
      insert into pipeline.firecrawl_targets(provider_id, included, reason, set_by, set_at) values (v_pid, v_inc, v_reason, auth.uid(), now())
        on conflict (provider_id) do update set included = excluded.included, reason = excluded.reason, set_by = excluded.set_by, set_at = now() where pipeline.firecrawl_targets.provider_id = excluded.provider_id;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_target', v_pid::text, jsonb_build_object('included', p_args->'included', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  elsif p_action = 'start' then
    if v_uc not in ('read_page', 'find_page') then raise exception 'use case must be read_page or find_page'; end if;
    if exists (select 1 from pipeline.firecrawl_runs r where r.use_case = v_uc and r.status = 'running') then raise exception 'a run of this use case is still open. Let it finish or stop it first'; end if;
    v_budget := security.layer2_provider_budget_status((select p.id from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl'), 1);
    if not coalesce((v_budget->>'allowed')::boolean, false) then raise exception 'Firecrawl is at its reserve. Check the plan on this page first'; end if;
    select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) into v_settings from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl';
    v_cap := (v_settings->>(case when v_uc = 'read_page' then 'read_credits_per_run' else 'find_credits_per_run' end))::numeric;
    insert into pipeline.firecrawl_runs(use_case, settings, reason, requested_by, credits_cap) values (v_uc, v_settings, v_reason, auth.uid(), v_cap) returning id into v_run;
    insert into pipeline.firecrawl_run_items(run_id, course_id, provider_id, country, url, input)
      select v_run, b.course_id, b.provider_id, b.country, b.url, b.input from (select distinct on (b0.course_id) b0.* from security.firecrawl_backlog_v1(v_uc) b0 order by b0.course_id) b
      order by b.provider_id, b.course_id;
    get diagnostics v_n = row_count;
    update pipeline.firecrawl_runs set items = v_n, status = case when v_n = 0 then 'done' else 'running' end, finished_at = case when v_n = 0 then now() end where id = v_run;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_run_start', v_uc, jsonb_build_object('run_id', v_run, 'items', v_n, 'credits_cap', v_cap, 'reason', v_reason), auth.uid());
    if v_n > 0 then perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', v_run)); end if;
    return jsonb_build_object('ok', true, 'run_id', v_run, 'items', v_n, 'credits_cap', v_cap);
  elsif p_action in ('stop', 'continue') then
    select * into v_r from pipeline.firecrawl_runs where id = (p_args->>'run_id')::uuid;
    if v_r.id is null then raise exception 'unknown run'; end if;
    if p_action = 'stop' then
      update pipeline.firecrawl_runs set status = 'stopped', finished_at = now() where id = v_r.id and status = 'running';
    else
      if v_r.status not in ('running', 'stopped_credit_cap', 'stopped_plan_reserve', 'stopped') then raise exception 'only an open or stopped run can be continued'; end if;
      if p_args ? 'add_credits' then update pipeline.firecrawl_runs set credits_cap = credits_cap + greatest((p_args->>'add_credits')::numeric, 0) where id = v_r.id; end if;
      update pipeline.firecrawl_runs set status = 'running', finished_at = null where id = v_r.id;
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', v_r.id));
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_run_' || p_action, v_r.id::text, jsonb_build_object('add_credits', p_args->'add_credits', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $function$
