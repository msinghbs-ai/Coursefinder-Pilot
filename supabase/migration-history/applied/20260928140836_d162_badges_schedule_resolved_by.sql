-- Provider tuition from a fee schedule says so in the badge tooltip (resolved_by), instead of "provider rule".
do $patch$
declare v_def text; v_old text; v_new text;
begin
  v_def:=pg_get_functiondef('security.admin_course_field_states(uuid)'::regprocedure);
  if md5(v_def)<>'a5f8b7f791d4ab6ab44c1329934f58f5' then raise exception 'security.admin_course_field_states changed since review; not replaced'; end if;
  v_old:='else ''Layer 2 provider rule'' end,';
  v_new:='when exists (select 1 from pipeline.sources fs where fs.id=v_fee.source_id and fs.source_type=''provider_fee_schedule'') then ''Layer 2 provider fee schedule'' else ''Layer 2 provider rule'' end,';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;
