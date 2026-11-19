CREATE OR REPLACE FUNCTION security.scholarship_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int; v_due int; v_sent int := 0; v_block timestamptz; v_okat timestamptz;
begin
  -- v2.15.258: in Stop at limits, not past the daily guard or below the credit floor
  if not security.ai_use_allowed_v1('scholarship_ai') then return 0; end if;
  select calls_at_once into v_max from pipeline.scholarship_ai_extract_settings where id = 1;
  -- F-SCH.15 (13 Nov 2026): a vendor-side block (OpenRouter key limit HTTP 403, no credit HTTP 402) holds the lane to one probe call; the first
  -- success after it re-queues the items the block closed
  select max(e.at) into v_block from pipeline.scholarship_ai_extractions e
   where e.at > now() - make_interval(hours => security.pipeline_num_v1('scholarship.vendor_block_lookback_hours', 24)::int)
     and (e.error like 'HTTP 403%limit%' or e.error like 'HTTP 402%');
  if v_block is not null then
    select max(e.at) into v_okat from pipeline.scholarship_ai_extractions e where e.at > v_block and e.error is null;
    if v_okat is null then v_max := least(coalesce(v_max, 3), 1);  -- fixed: one probe call while the vendor refuses
    else perform security.scholarship_ai_vendor_requeue_v1(v_block - make_interval(hours => security.pipeline_num_v1('scholarship.vendor_block_lookback_hours', 24)::int)); end if;
  end if;
  select count(*) into v_due from pipeline.scholarship_ai_queue q where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3;  -- fixed: the picker's attempt cap (svc_scholarship_ai_next); 20261118184000: a dead lease no longer blocks the idle fill
  -- F-SCH redesign (12 Nov 2026): when nothing else is due, existing records are filled from their stored official page
  if v_due = 0 then
    v_due := security.scholarship_detail_backfill_v1(security.pipeline_num_v1('batch.sch_detail_backfill', 40)::int);
    if v_due = 0 then return 0; end if;
  end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'scholarship_ai' and l.created_at > now() - interval '3 minutes'
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < coalesce(v_max, 3) and v_sent * 8 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_ai'));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$
