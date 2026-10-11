CREATE OR REPLACE FUNCTION security.scholarship_mapping_decision_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d pipeline.scholarship_scope_decisions%rowtype;
begin
  if NEW.mapping_basis is distinct from 'sweep_level_field_scope' then return NEW; end if;
  select * into d from pipeline.scholarship_scope_decisions where scholarship_id = NEW.scholarship_id;
  if d.scholarship_id is not null and not security.scholarship_scope_match(NEW.course_id, d.decision, d.filter) then return null; end if;
  return NEW;
end $function$
