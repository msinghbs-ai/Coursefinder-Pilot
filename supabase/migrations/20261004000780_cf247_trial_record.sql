-- CF-247 Decision 252: record one trial call (service role only). Results are kept for review; nothing is admitted.
-- A refusal by the service (key, plan or credit limit) stops the run and leaves the case to be tried again later.
create or replace function public.svc_toolset_trial_record(p_item_id uuid, p_result jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_i pipeline.toolset_trial_items%rowtype; v_r pipeline.toolset_trial_runs%rowtype; v_credits numeric := coalesce((p_result->>'credits')::numeric, 0); v_cap numeric;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_i from pipeline.toolset_trial_items where id = p_item_id;
  if v_i.id is null then raise exception 'unknown item'; end if;
  select * into v_r from pipeline.toolset_trial_runs where id = v_i.run_id;
  v_cap := coalesce((v_r.settings->>'trial_max_credits_per_run')::numeric, 0);
  if p_result->>'outcome' = 'vendor_limit' then
    update pipeline.toolset_trial_items set leased_until = now() where id = p_item_id;
    update pipeline.toolset_trial_runs set status = 'stopped_vendor_limit', status_note = left(p_result->>'message', 300), finished_at = now(), updated_at = now() where id = v_r.id;
    return jsonb_build_object('continue', false);
  end if;
  update pipeline.toolset_trial_items set status = 'done', outcome = p_result->>'outcome', done_at = now() where id = p_item_id;
  update pipeline.toolset_trial_items set http_status = (p_result->>'http_status')::int, credits = v_credits, latency_ms = (p_result->>'latency_ms')::int where id = p_item_id;
  update pipeline.toolset_trial_items set result = p_result - 'outcome' - 'http_status' - 'credits' - 'latency_ms' where id = p_item_id;
  update pipeline.toolset_trial_runs set credits_used = credits_used + v_credits, updated_at = now() where id = v_r.id;
  if v_r.credits_used + v_credits >= v_cap then
    update pipeline.toolset_trial_runs set status = 'stopped_credit_cap', status_note = 'the run used its credit allowance', finished_at = now() where id = v_r.id and status = 'running';
  end if;
  if v_credits > 0 then
    insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url)
    select p.id, v_credits, 'trial_' || v_r.toolset_key, v_i.provider_id, coalesce(v_i.input->>'url', p_result->>'query')
    from pipeline.layer2_acquisition_providers p where p.provider_key = v_r.toolset_key;
  end if;
  return jsonb_build_object('continue', v_r.credits_used + v_credits < v_cap and (select status = 'running' from pipeline.toolset_trial_runs where id = v_r.id));
end $f$;
revoke all on function public.svc_toolset_trial_record(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_toolset_trial_record(uuid, jsonb) to service_role;
