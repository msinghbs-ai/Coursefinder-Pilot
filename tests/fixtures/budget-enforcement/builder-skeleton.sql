-- public.admin_adapter_builder is 11,929 characters live and has no complete migration in this repository, so the fixture holds a skeleton:
-- its 'start', 'add_sample' and 'propose' actions with the lines the 20261102070000 migration edits exactly as live (read 2 Nov 2026; live
-- counts 1 (propose) and 2 (capture: start, add sample), checked by builder-edit.mjs check on production, read-only). run.sh applies the migration's own edits to this skeleton
-- (builder-edit.mjs variant) and checks the applied md5 equals the md5 the check query predicts the same way.
-- Live check (2 Nov 2026 11:46 AEDT, read-only, node builder-edit.mjs check): before 23c611e79c25ab1663f65fcea709b202, edits apply 1 and 2 times,
-- after 62e93d40ff0616e87a8960d2d29a2b21 (the md5s the migration checks); no carriage returns in the live text.
create or replace function public.admin_adapter_builder(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_d pipeline.uni_adapter_drafts%rowtype; v_id uuid; v_pid uuid; v_b jsonb; v_m jsonb;
begin
  if p_action = 'start' then
    v_pid := (p_args->>'provider_id')::uuid;
    insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, '[{"url": "https://uni.example/c1"}]', 'fixture', auth.uid()) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_start', v_pid::text, jsonb_build_object('draft_id', v_id), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  select * into v_d from pipeline.uni_adapter_drafts where id = (p_args->>'draft_id')::uuid;
  if v_d.id is null then raise exception 'unknown draft'; end if;
  if p_action = 'add_sample' then
      update pipeline.uni_adapter_drafts set samples = samples || jsonb_build_array(p_args->'sample'), status = 'capturing', updated_at = now() where id = v_d.id;
      v_id := v_d.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_add_sample', v_d.provider_id::text, jsonb_build_object('draft_id', v_id), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  elsif p_action = 'propose' then
    if jsonb_array_length(v_d.captures) = 0 then raise exception 'capture the sample pages first'; end if;
    v_b := security.adapter_builder_budget();
    if (v_b->>'used_usd')::numeric >= (v_b->>'limit_usd')::numeric then raise exception 'the AI allowance for today is used (US$ % of %). It is a setting under Adapter builder', v_b->>'used_usd', v_b->>'limit_usd'; end if;
    v_m := security.adapter_builder_model_for_v1(v_d.provider_id);
    update pipeline.uni_adapter_drafts set status = 'proposing', model = v_m->>'model', model_profile = v_m->>'code', updated_at = now() where id = v_d.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_propose', v_d.provider_id::text, jsonb_build_object('draft_id', v_d.id, 'budget', v_b, 'model', v_m), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_propose', 'draft_id', v_d.id));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $function$;
