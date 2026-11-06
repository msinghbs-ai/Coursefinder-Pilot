CREATE OR REPLACE FUNCTION security.provider_description_review_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update pipeline.provider_description_reads set
         state = case when new.status = 'rejected' then 'rejected' when new.status in ('more_evidence', 'returned_layer2', 'returned_layer3') then 'held' when new.status = 'superseded' then 'superseded' else state end,
         rule = case when new.status in ('approved', 'edited_approved') then rule else 'layer4_' || new.status end,
         updated_at = now()
   where review_item_id = new.id and state = 'proposed' and new.status not in ('approved', 'edited_approved');
  return new;
end $function$

