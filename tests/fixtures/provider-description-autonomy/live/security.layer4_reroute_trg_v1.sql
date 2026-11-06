CREATE OR REPLACE FUNCTION security.layer4_reroute_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.entity_type = 'course' and new.status = 'pending' and security.layer4_reroute_course_v1(new.entity_id, new.field_code, true) then
    new.status := 'superseded'; new.decided_at := now();
    new.change_control_ref := coalesce(new.change_control_ref || '; ', '') || 'CF-247 v2.15.250: rerouted to the university adapter';
    insert into pipeline.layer4_reroutes(item_id, entity_type, entity_id, field_code, route, note) values (new.id, 'course', new.entity_id, new.field_code, 'adapter', 'on arrival');
  end if;
  return new;
end $function$

