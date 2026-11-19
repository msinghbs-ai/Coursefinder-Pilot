CREATE OR REPLACE FUNCTION security.provider_description_approved_lineage_v1(p_provider uuid, p_text text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select li.id from pipeline.provider_description_reads h join pipeline.layer4_review_items li on li.id=h.review_item_id
 where h.provider_id=p_provider and h.state in ('admitted','superseded') and li.status in ('approved','edited_approved')
 and h.proposal->>'description'=p_text and li.proposed_value->>'description'=p_text
 order by h.created_at desc,h.id desc limit 1
$function$
