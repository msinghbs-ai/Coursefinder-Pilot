CREATE OR REPLACE FUNCTION security.layer4_arrival_guard_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Trigger layer4_review_items_zz_arrival (BEFORE INSERT; after layer4_review_items_reroute, before ops_guard_layer4). While layer4.arrival_guard_on
-- is 1, a new waiting item of a kind in layer4.platform_kinds that the platform can settle (security.layer4_resolution_for_v1) arrives superseded,
-- with the reason recorded in pipeline.layer4_supersessions. It never approves, rejects or changes any other row. Every generator passes here.
declare v_res jsonb;
begin
  if new.status is distinct from 'pending' or security.pipeline_num_v1('layer4.arrival_guard_on', 0) < 1
     or not (new.field_code = any (security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb))) then
    return new;
  end if;
  new.id := coalesce(new.id, gen_random_uuid());
  v_res := security.layer4_resolution_for_v1(new.id, new.entity_type, new.entity_id, new.field_code, new.proposed_value, new.layer2_state, new.evidence_id, coalesce(new.created_at, now()));
  if v_res is null then return new; end if;
  new.status := 'superseded';
  new.decided_at := now();
  new.change_control_ref := coalesce(new.change_control_ref || '; ', '') || 'CF-247 L4 readiness: settled on arrival (' || (v_res->>'reason') || ')';
  insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
  values (new.id, new.field_code, new.entity_type, new.entity_id, v_res->>'reason', nullif(v_res->>'covered_by_item', '')::uuid, coalesce(v_res->'evidence', '{}'::jsonb), 'arrival');
  return new;
end $function$

