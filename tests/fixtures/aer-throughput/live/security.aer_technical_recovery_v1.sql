CREATE OR REPLACE FUNCTION security.aer_technical_recovery_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 SS-021 F4: Layer 4 entry items that are not decisions are recorded for bounded technical recovery (lane aer_technical), not counted
-- and not sent anywhere: technically held items (readiness technical_blocked) are checked again at each backoff and parked after
-- wc.aer_tech_max_attempts; duplicates (a later waiting item for the same entity and kind) are parked once; an item that becomes ready, closes
-- or leaves the queue is recovered. Records only: no Layer 4 item, decision or value is changed.
declare v_n int := security.pipeline_num_v1('wc.tick_batch', 500)::int; r record; v_t int := 0; v_d int := 0; v_ok int := 0;
begin
  if security.pipeline_num_v1('wc.on', 1) < 1 then return jsonb_build_object('held', 'wc.on is 0'); end if;
  for r in select i.id, i.entity_id, i.entity_type, i.field_code, x.reasons, x.route, x.blockers, c.provider_id
             from pipeline.layer4_review_items i join pipeline.layer4_item_readiness x on x.item_id = i.id
             left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
             join pipeline.work_review_categories rc on rc.category = 'aer'
            where i.status = 'pending' and i.field_code = any (rc.field_codes) and x.readiness = 'technical_blocked'
              and security.work_item_eligible_v1('aer_technical', i.id::text, 'l4_item')
            order by i.created_at, i.id limit v_n loop
    perform security.work_item_report_v1('aer_technical', r.id::text, 'l4_item', 'failed', jsonb_build_object(
              'class', 'technical_hold', 'owner', 'aer-scheduled-read', 'field', r.field_code,
              'provider_id', coalesce(r.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
              'message', 'technically held: ' || coalesce(array_to_string(r.reasons, ', '), 'no reason'),
              'evidence', jsonb_build_object('route', r.route, 'blockers', r.blockers)));
    v_t := v_t + 1;
  end loop;
  for r in select z.* from (
             select i.id, i.entity_id, i.entity_type, i.field_code, c.provider_id,
                    first_value(i.id) over (partition by i.entity_id, i.field_code order by i.created_at, i.id) keep,
                    row_number() over (partition by i.entity_id, i.field_code order by i.created_at, i.id) rn
               from pipeline.layer4_review_items i left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
               join pipeline.work_review_categories rc on rc.category = 'aer'
              where i.status = 'pending' and i.field_code = any (rc.field_codes)) z
            where z.rn > 1 and not exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = z.id::text and w.work_kind = 'l4_item'
                                                                              and w.failure_class = 'duplicate' and w.stage = 'parked')
            limit v_n loop
    perform security.work_item_report_v1('aer_technical', r.id::text, 'l4_item', 'failed', jsonb_build_object(
              'class', 'duplicate', 'owner', 'aer-scheduled-read', 'field', r.field_code,
              'provider_id', coalesce(r.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
              'message', 'duplicate of the older waiting item', 'evidence', jsonb_build_object('kept_item', r.keep)));
    v_d := v_d + 1;
  end loop;
  for r in select w.entity from pipeline.work_items w
            where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.stage <> 'done'
              and not exists (select 1 from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id
                               where i.id::text = w.entity and i.status = 'pending'
                                 and (case when w.failure_class = 'duplicate' then true else x.readiness = 'technical_blocked' end))
            limit v_n loop
    perform security.work_item_report_v1('aer_technical', r.entity, 'l4_item', 'succeeded', jsonb_build_object('outcome', 'succeeded_with_result'));
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('technical_checked', v_t, 'duplicates_parked', v_d, 'recovered', v_ok);
end $function$
