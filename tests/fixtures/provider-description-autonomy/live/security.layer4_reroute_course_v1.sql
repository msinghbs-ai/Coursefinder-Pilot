CREATE OR REPLACE FUNCTION security.layer4_reroute_course_v1(p_course uuid, p_field_code text, p_apply boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_f text := security.layer4_adapter_field_v1(p_field_code); v_ok boolean;
begin
  if v_f is null then return false; end if;
  select true into v_ok from catalogue.courses c join pipeline.uni_adapters a on a.provider_id = c.provider_id
   where c.id = p_course and a.enabled and coalesce(a.admit, false) and (a.admit_fields is null or v_f = any (a.admit_fields))
     and exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = c.id and pg.status in ('bound', 'ambiguous'));
  if not coalesce(v_ok, false) then return false; end if;
  if p_apply then
    update pipeline.coverage_course_pages set next_read_at = now(), leased_until = null, read_attempts = 0 where course_id = p_course and status in ('bound', 'ambiguous');
  end if;
  return true;
end $function$

