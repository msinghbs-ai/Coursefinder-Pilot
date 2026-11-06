CREATE OR REPLACE FUNCTION security.provider_description_fire_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int;
begin
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  v_q := security.provider_description_enqueue_v1();
  select count(*) into v_dead from pipeline.provider_description_reads r where r.state = 'dead_letter';
  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('queued', v_q, 'ai', 'stopped', 'dead_letter', v_dead); end if;
  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening') >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then
    return jsonb_build_object('queued', v_q, 'ai', 'ceiling', 'dead_letter', v_dead);
  end if;
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
  select count(*) into v_due from pipeline.provider_description_reads r
   where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now())) and r.tries < security.pipeline_num_v1('pdesc.tries', 3);
  select max(l.created_at) into v_last from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description'
     and l.created_at > now() - make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int);
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if v_due > 0 and v_open = 0 and v_last is null then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int));
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 1, 'dead_letter', v_dead);
  end if;
  return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 0, 'dead_letter', v_dead);
end $function$

