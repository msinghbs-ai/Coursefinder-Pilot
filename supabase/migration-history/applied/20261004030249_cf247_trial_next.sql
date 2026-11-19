-- CF-247 Decision 252: lease the next cases of a trial run to the worker (service role only), with the run's settings
-- snapshot and the service's runtime configuration (key from the vault, as for every Layer 2 service).
create or replace function public.svc_toolset_trial_next(p_run_id uuid, p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r pipeline.toolset_trial_runs%rowtype; v_items jsonb; v_ids uuid[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_r from pipeline.toolset_trial_runs where id = p_run_id for update;
  if v_r.id is null or v_r.status not in ('ready', 'running', 'paused_time_limit') then return jsonb_build_object('items', '[]'::jsonb, 'status', v_r.status); end if;
  if v_r.credits_used >= coalesce((v_r.settings->>'trial_max_credits_per_run')::numeric, 0) then
    update pipeline.toolset_trial_runs set status = 'stopped_credit_cap', status_note = 'the run used its credit allowance', finished_at = now(), updated_at = now() where id = p_run_id;
    return jsonb_build_object('items', '[]'::jsonb, 'status', 'stopped_credit_cap');
  end if;
  update pipeline.toolset_trial_runs set status = 'running', updated_at = now() where id = p_run_id;
  select array_agg(i.id) into v_ids from (
    select i.id from pipeline.toolset_trial_items i
    where i.run_id = p_run_id and (i.status = 'pending' or (i.status = 'leased' and i.leased_until < now()))
    order by i.country, i.id limit greatest(1, least(p_limit, 50)) for update skip locked) i;
  update pipeline.toolset_trial_items set status = 'leased', leased_until = now() + interval '10 minutes' where id = any(coalesce(v_ids, '{}'));
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'country', i.country, 'input', i.input)), '[]'::jsonb) into v_items
    from pipeline.toolset_trial_items i where i.id = any(coalesce(v_ids, '{}'));
  return jsonb_build_object('items', v_items, 'status', 'running', 'purpose', v_r.purpose, 'settings', v_r.settings,
    'provider', (select public.layer2_provider_runtime_config(p.id) from pipeline.layer2_acquisition_providers p where p.provider_key = v_r.toolset_key));
end $f$;
revoke all on function public.svc_toolset_trial_next(uuid, int) from public, anon, authenticated;
grant execute on function public.svc_toolset_trial_next(uuid, int) to service_role;
