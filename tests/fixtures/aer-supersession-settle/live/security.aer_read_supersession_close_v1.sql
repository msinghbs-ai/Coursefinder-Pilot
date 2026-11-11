CREATE OR REPLACE FUNCTION security.aer_read_supersession_close_v1(p_id uuid, p_state text, p_why text, p_new_item uuid, p_diff jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update pipeline.aer_read_supersessions set state = p_state, outcome = left(p_why, 500), new_item_id = p_new_item, diff = p_diff, closed_at = now()
   where id = p_id and state = 'requested'
$function$
