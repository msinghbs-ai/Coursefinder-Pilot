CREATE OR REPLACE FUNCTION security.layer4_evidence_link_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Trigger layer4_review_items_zz_evidence (BEFORE INSERT): a new waiting item of a kind in layer4.evidence_link_kinds that arrives without a
-- stored copy gets the newest stored copy of its page. No read is made; nothing else changes.
begin
  if new.evidence_id is null and new.status = 'pending' and security.pipeline_num_v1('layer4.evidence_link_on', 1) >= 1
     and new.field_code = any (security.pipeline_list_v1('layer4.evidence_link_kinds', '[]'::jsonb)) then
    new.evidence_id := security.layer4_stored_copy_v1(security.layer4_item_page_v1(new.field_code, new.proposed_value, new.layer2_state));
  end if;
  return new;
end $function$

