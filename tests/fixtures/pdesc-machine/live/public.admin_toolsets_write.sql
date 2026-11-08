CREATE OR REPLACE FUNCTION public.admin_toolsets_write(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_set pipeline.platform_toolset_settings%rowtype; v_val jsonb; v_num numeric; v_before jsonb; v_t pipeline.platform_toolsets%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'setting' then
    select * into v_set from pipeline.platform_toolset_settings where toolset_key = p_args->>'toolset' and key = p_args->>'key';
    if v_set.key is null then raise exception 'unknown setting'; end if;
    v_val := p_args->'value';
    if v_set.kind = 'number' then
      v_num := (v_val #>> '{}')::numeric;
      if v_num is null or (v_set.min_value is not null and v_num < v_set.min_value) or (v_set.max_value is not null and v_num > v_set.max_value) then
        raise exception 'value must be between % and %', v_set.min_value, v_set.max_value; end if;
      v_val := to_jsonb(v_num);
    elsif v_set.kind = 'boolean' then v_val := to_jsonb((v_val #>> '{}')::boolean);
    elsif v_set.kind = 'list' then
      if jsonb_typeof(v_val) <> 'array' then raise exception 'a list is needed'; end if;
    else v_val := to_jsonb(btrim(v_val #>> '{}'));
      if length(v_val #>> '{}') = 0 then raise exception 'text cannot be empty'; end if;
    end if;
    v_before := v_set.value;
    update pipeline.platform_toolset_settings set value = v_val, reason = v_reason, updated_by = auth.uid(), updated_at = now() where toolset_key = v_set.toolset_key and key = v_set.key;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'setting', v_set.toolset_key || '.' || v_set.key, jsonb_build_object('before', v_before, 'after', v_val, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'toolset', v_set.toolset_key, 'key', v_set.key, 'value', v_val);
  elsif p_action = 'enforcement' then
    select * into v_t from pipeline.platform_toolsets where key = p_args->>'toolset';
    if v_t.key is null or v_t.enforcement is null then raise exception 'this toolset has no enforcement mode'; end if;
    if p_args->>'enforcement' not in ('observe', 'stop') then raise exception 'enforcement must be observe or stop'; end if;
    update pipeline.platform_toolsets set enforcement = p_args->>'enforcement', reason = v_reason, updated_by = auth.uid(), updated_at = now() where key = v_t.key;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'enforcement', v_t.key, jsonb_build_object('before', v_t.enforcement, 'after', p_args->>'enforcement', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'toolset', v_t.key, 'enforcement', p_args->>'enforcement');
  elsif p_action = 'job_layer' then
    if not exists (select 1 from cron.job where jobname = p_args->>'jobname') then raise exception 'unknown job'; end if;
    if (p_args->>'layer')::int not between 0 and 4 then raise exception 'layer must be 0 to 4'; end if;
    insert into pipeline.platform_job_layers(jobname, layer, updated_at) values (p_args->>'jobname', (p_args->>'layer')::int, now())
      on conflict (jobname) do update set layer = excluded.layer, updated_at = now();
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'job_layer', p_args->>'jobname', jsonb_build_object('layer', p_args->'layer', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  elsif p_action = 'ack' then
    if coalesce(p_args->>'notice_key', '') = '' then raise exception 'notice_key required'; end if;
    insert into pipeline.platform_notice_acks(notice_key, acknowledged_at, acknowledged_by, reason) values (p_args->>'notice_key', now(), auth.uid(), v_reason)
      on conflict (notice_key) do update set acknowledged_at = now(), acknowledged_by = auth.uid(), reason = v_reason;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'ack', p_args->>'notice_key', jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action %', p_action;
end $function$
