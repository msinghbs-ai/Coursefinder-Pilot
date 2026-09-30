-- CF-247 Models & services (Platform Admin, 1 Oct 2026: "Model or external should have toggle button to enable /
-- disable. Disable should grey out or not available in operation but only in admin menu").
-- One admin page lists every AI model profile (by task) and every external fetching service, each with an on/off
-- switch. PIM Operator and above can switch; every change is logged (admin_control_events area 'services').
--   A model switched off is also paused, and its cascade steps are switched off, so no task can use it. It stays listed
--   (greyed) only on this page; operation screens (Layer 3 Control, Send back to AI) already show enabled models only,
--   and Layer 3 Control now hides steps whose model is switched off. Switching a model on does not put it back into a
--   cascade; that stays a Layer 3 Control decision.
--   A service switched off is skipped by page fetching (routes already require the service to be on).
-- Retired models (failed tests) are listed separately and cannot be switched on here.

create or replace function public.admin_services_read() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_control', v_rank >= 5,
    'models', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'model', p.model_identifier, 'provider', p.aggregator_provider,
                 'tasks', to_jsonb(p.allowed_task_classes), 'enabled', p.enabled and not p.paused, 'retired', p.retired_at is not null,
                 'retired_reason', p.retired_reason, 'qualified', coalesce((p.quality_benchmark->>'pass')::boolean, false),
                 'steps', (select coalesce(jsonb_agg(jsonb_build_object('task', t.task_class, 'step', t.tier_no, 'active', t.active) order by t.task_class, t.tier_no), '[]'::jsonb)
                             from pipeline.layer3_route_tiers t where t.profile_id = p.id),
                 'calls_7d', (select count(*) from pipeline.layer3_interpretations i where i.profile_id = p.id and i.created_at >= now() - interval '7 days'),
                 'cost_7d_usd', (select round(coalesce(sum(i.estimated_cost_usd), 0), 4) from pipeline.layer3_interpretations i where i.profile_id = p.id and i.created_at >= now() - interval '7 days'))
               order by p.retired_at is not null, (p.enabled and not p.paused) desc, p.allowed_task_classes[1], p.model_identifier), '[]'::jsonb)
               from pipeline.layer3_model_profiles p),
    'services', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'key', a.provider_key, 'name', a.display_name, 'type', a.adapter_type,
                 'enabled', a.enabled, 'credential', a.vault_secret_id is not null,
                 'routes', (select count(*) from pipeline.layer2_profile_provider_routes r where r.acquisition_provider_id = a.id and r.enabled),
                 'last_test', jsonb_build_object('at', a.last_tested_at, 'status', a.last_test_status))
               order by a.enabled desc, a.priority, a.display_name), '[]'::jsonb)
               from pipeline.layer2_acquisition_providers a),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
               from (select * from pipeline.admin_control_events where area = 'services' order by created_at desc limit 15) e left join auth.users u on u.id = e.actor));
end $$;
revoke all on function public.admin_services_read() from public, anon;
grant execute on function public.admin_services_read() to authenticated;

create or replace function public.admin_services_control(p_kind text, p_id uuid, p_enabled boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_label text; v_steps int := 0;
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if p_kind = 'model' then
    select model_identifier into v_label from pipeline.layer3_model_profiles where id = p_id;
    if v_label is null then raise exception 'model not found'; end if;
    if p_enabled and exists (select 1 from pipeline.layer3_model_profiles where id = p_id and retired_at is not null) then
      raise exception 'this model was retired after failing its tests and cannot be switched on here';
    end if;
    update pipeline.layer3_model_profiles set enabled = p_enabled, paused = not p_enabled, updated_at = now() where id = p_id;
    if not p_enabled then
      update pipeline.layer3_route_tiers set active = false, updated_at = now() where profile_id = p_id and active;
      get diagnostics v_steps = row_count;
    end if;
  elsif p_kind = 'service' then
    select display_name into v_label from pipeline.layer2_acquisition_providers where id = p_id;
    if v_label is null then raise exception 'service not found'; end if;
    update pipeline.layer2_acquisition_providers set enabled = p_enabled, updated_at = now() where id = p_id;
  else
    raise exception 'unknown kind %', p_kind;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('services', case when p_enabled then 'switch_on' else 'switch_off' end, v_label,
          jsonb_build_object('kind', p_kind, 'id', p_id, 'steps_switched_off', v_steps, 'reason', nullif(btrim(coalesce(p_reason, '')), '')), auth.uid());
  return public.admin_services_read() || jsonb_build_object('steps_switched_off', v_steps);
end $$;
revoke all on function public.admin_services_control(text, uuid, boolean, text) from public, anon;
grant execute on function public.admin_services_control(text, uuid, boolean, text) to authenticated;

-- Layer 3 Control: steps whose model is switched off or retired are not shown (md5-guarded in-place edit).
do $$
declare d text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_layer3_control_read_v1()'::regprocedure) <> 'fa6b908067833a4ab295bc3736d7b7cd' then
    raise exception 'admin_layer3_control_read_v1 changed; review first';
  end if;
  d := pg_get_functiondef('security.admin_layer3_control_read_v1()'::regprocedure);
  n := regexp_replace(d, 'join pipeline\.layer3_model_profiles p on p\.id=t\.profile_id(\s+)where t\.task_class=b\.task_class\)(\s+)else',
                      'join pipeline.layer3_model_profiles p on p.id=t.profile_id\1where t.task_class=b.task_class and p.enabled and not p.paused and p.retired_at is null)\2else');
  if n = d or (length(n) - length(d)) <> length(' and p.enabled and not p.paused and p.retired_at is null') then raise exception 'edit did not apply once'; end if;
  execute n;
end $$;
