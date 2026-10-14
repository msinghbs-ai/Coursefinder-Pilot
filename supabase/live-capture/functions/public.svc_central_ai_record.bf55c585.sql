CREATE OR REPLACE FUNCTION public.svc_central_ai_record(p_queue_id bigint, p_parsed jsonb, p_cost numeric, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q pipeline.central_ai_queue%rowtype; r jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.central_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false); end if;
  if p_error is not null then
    update pipeline.central_ai_queue set state = case when p_error = 'time budget' then 'queued' when attempts >= 3 then 'failed' else 'queued' end,
           attempts = case when p_error = 'time budget' then greatest(attempts - 1, 0) else attempts end, leased_until = null, error = left(p_error, 400), cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0)
     where id = q.id;
    return jsonb_build_object('ok', true, 'status', 'error');
  end if;
  r := public.svc_provider_policy_record(q.fact_source_id, p_parsed);
  update pipeline.central_ai_queue set state = 'done', done_at = now(), leased_until = null, status = r->>'status', cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0), error = null where id = q.id;
  if r->>'status' = 'proposed' then
    update pipeline.provider_onboarding o set stop_reason = 'approve_central', updated_at = now(),
           note = 'The AI read its central pages; approve or reject them in the Adapter builder (1.3) or Providers › Onboarding › Approvals waiting.'
     where o.provider_id = q.provider_id and o.status = 'stopped' and o.stop_reason = 'nothing_ready';
  end if;
  return jsonb_build_object('ok', true, 'status', r->>'status');
end $function$
