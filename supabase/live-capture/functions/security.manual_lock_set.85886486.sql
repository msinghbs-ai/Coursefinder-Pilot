CREATE OR REPLACE FUNCTION security.manual_lock_set(p_entity text, p_id uuid, p_field text, p_mode text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values (p_entity, p_id, p_field, p_mode, auth.uid())
  on conflict (entity, entity_id, field) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now();
$function$
