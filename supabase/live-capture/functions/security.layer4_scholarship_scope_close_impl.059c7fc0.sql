CREATE OR REPLACE FUNCTION security.layer4_scholarship_scope_close_impl(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'scholarship'
AS $function$
declare v_item pipeline.layer4_review_items%rowtype; v_open int;
begin
  select * into v_item from pipeline.layer4_review_items where id=p_item_id;
  select count(*) into v_open from scholarship.course_mapping_candidates where scholarship_id=v_item.entity_id and status='needs_review';
  if v_open>0 then raise exception '% course(s) still need a scope decision. Decide them in Batches, then mark this as done.', v_open; end if;
  return jsonb_build_object('scope_closed',true);
end $function$
