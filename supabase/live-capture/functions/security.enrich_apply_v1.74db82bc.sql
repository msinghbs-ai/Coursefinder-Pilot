CREATE OR REPLACE FUNCTION security.enrich_apply_v1(p_item bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.field_enrich_items%rowtype; v_n int := 0; v_lock boolean;
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  if i.id is null or i.value is null then return 'nothing'; end if;
  v_lock := exists (select 1 from pipeline.manual_locks l where l.entity = case when i.course_id is null then 'provider' else 'course' end
                     and l.entity_id = coalesce(i.course_id, i.provider_id) and l.field in (i.field, 'all'));
  if v_lock then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'locked by hand', updated_at = now() where id = i.id; return 'locked';
  end if;
  if i.field = 'duration' then
    update catalogue.courses set duration_value = (i.value->>'value')::numeric, duration_unit = i.value->>'unit', updated_at = now()
     where id = i.course_id and duration_value is null;
  elsif i.field = 'level' then
    update catalogue.courses set study_level_id = (i.value->>'level_id')::uuid, updated_at = now() where id = i.course_id and study_level_id is null;
  elsif i.field = 'delivery' then
    update catalogue.courses set delivery_mode = i.value->>'mode', updated_at = now() where id = i.course_id and nullif(btrim(delivery_mode), '') is null;
  elsif i.field = 'field_of_study' then
    update catalogue.courses set primary_field_id = (i.value->>'field_id')::uuid, updated_at = now() where id = i.course_id and primary_field_id is null;
  elsif i.field = 'international' then
    update catalogue.courses set open_to_international = (i.value->>'open')::boolean, updated_at = now() where id = i.course_id and open_to_international is null;
  elsif i.field = 'provider_address' then
    update catalogue.providers set address_line1 = left(i.value->>'street', 200), postcode = coalesce(postcode, left(i.value->>'postcode', 20)),
           primary_city = coalesce(nullif(btrim(primary_city), ''), left(i.value->>'city', 120)), updated_at = now()
     where id = i.provider_id and nullif(btrim(address_line1), '') is null;
  elsif i.field = 'campus' and i.course_id is not null then
    insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary, evidence_id)
    select i.course_id, (x->>'campus_id')::uuid, coalesce((select nullif(btrim(c.delivery_mode), '') from catalogue.courses c where c.id = i.course_id and c.delivery_mode in ('on_campus', 'blended', 'on_campus_and_online')), 'on_campus'),
           row_number() over () = 1, i.evidence_id
      from jsonb_array_elements(i.value->'campuses') x
     where not exists (select 1 from catalogue.course_campuses cc where cc.course_id = i.course_id and cc.campus_id = (x->>'campus_id')::uuid)
    on conflict do nothing;
  end if;
  get diagnostics v_n = row_count;
  update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end,
         reason = case when v_n > 0 then reason else coalesce(reason, 'already filled') end, updated_at = now() where id = i.id;
  return case when v_n > 0 then 'filled' else 'already' end;
end $function$
