CREATE OR REPLACE FUNCTION public.admin_adapter_autobuild(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_today int; v_cap int; v_id uuid; v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'states' then
    select coalesce(jsonb_object_agg(x.id, security.adapter_autobuild_state_v1(x.id::uuid)), '{}'::jsonb) into v
      from (select distinct jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) id limit 200) x;
    return v;
  end if;
  if p_action = 'read' then
    return security.adapter_autobuild_state_v1(v_pid) || jsonb_build_object('can_manage', v_rank >= 6,
      'today', (select count(*) from pipeline.adapter_autobuilds b where (b.created_at at time zone 'Australia/Melbourne')::date = (now() at time zone 'Australia/Melbourne')::date),
      'per_day', (security.firecrawl_setting('autobuild_per_day') #>> '{}')::int,
      'model', security.firecrawl_setting('builder_model') #>> '{}');
  end if;
  if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    if not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'unknown provider'; end if;
    if exists (select 1 from pipeline.uni_adapters u where u.provider_id = v_pid and u.admit) then raise exception 'this provider already has an admitting adapter: change it in the builder instead'; end if;
    if exists (select 1 from pipeline.adapter_autobuilds b where b.provider_id = v_pid and b.status not in ('done', 'failed', 'stopped')) then raise exception 'a build is already running for this provider'; end if;
    v_today := (select count(*) from pipeline.adapter_autobuilds b where (b.created_at at time zone 'Australia/Melbourne')::date = (now() at time zone 'Australia/Melbourne')::date);
    v_cap := coalesce((security.firecrawl_setting('autobuild_per_day') #>> '{}')::int, 25);
    if v_today >= v_cap then raise exception 'the automatic builds for today are used (% of %). It is a setting under Adapter builder', v_today, v_cap; end if;
    insert into pipeline.adapter_autobuilds(provider_id, credits_cap, requested_by, reason, note)
    values (v_pid, coalesce((security.firecrawl_setting('autobuild_credits') #>> '{}')::int, 150), auth.uid(), v_reason, 'Waiting to start (within 2 minutes).')
    returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_autobuild_start', v_pid::text, jsonb_build_object('build_id', v_id, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'build_id', v_id);
  elsif p_action = 'stop' then
    update pipeline.adapter_autobuilds set status = 'stopped', note = 'Stopped by a Platform Admin: ' || v_reason, updated_at = now()
     where provider_id = v_pid and status not in ('done', 'failed', 'stopped') returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_autobuild_stop', v_pid::text, jsonb_build_object('build_id', v_id, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', v_id is not null);
  end if;
  raise exception 'unknown action';
end $function$
