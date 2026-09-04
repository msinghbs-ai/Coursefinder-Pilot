-- CF-117 — refresh percentage-derived Course scholarship calculations after governed fee/scholarship changes.
create or replace function scholarship.refresh_course_financial_calculations(p_course_id uuid default null,p_scholarship_id uuid default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','scholarship','catalogue' as $$
declare r record; v_total integer:=0; v_calculated integer:=0; v_unresolved integer:=0; v_status text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 for r in select m.id from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id where m.mapping_state='mapped' and (p_course_id is null or m.course_id=p_course_id) and (p_scholarship_id is null or m.scholarship_id=p_scholarship_id) and (s.award_value_type='percentage' or exists(select 1 from scholarship.course_financial_calculations fc where fc.mapping_id=m.id))
 loop
  select (scholarship.refresh_course_financial_calculation(r.id)).calculation_status into v_status;
  v_total:=v_total+1;
  if v_status='calculated' then v_calculated:=v_calculated+1; else v_unresolved:=v_unresolved+1; end if;
 end loop;
 return jsonb_build_object('ok',true,'refreshed',v_total,'calculated',v_calculated,'unresolved',v_unresolved);
end $$;
revoke all on function scholarship.refresh_course_financial_calculations(uuid,uuid) from public,anon,authenticated;
grant execute on function scholarship.refresh_course_financial_calculations(uuid,uuid) to service_role;
