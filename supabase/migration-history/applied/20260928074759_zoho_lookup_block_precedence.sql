do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('api.zoho_course_lookup_v1(text)'::regprocedure);
  if md5(d)<>'1d30db8739355cb224376b6922344c9f' then raise exception 'zoho_course_lookup_v1 changed since review (%); not patched', md5(d); end if;
  n:=replace(d,'      and lower(d.course_stable_key)=lower(btrim(p_identifier))
       or lower(d.course_code)=lower(btrim(p_identifier))','      and (lower(d.course_stable_key)=lower(btrim(p_identifier))
       or lower(d.course_code)=lower(btrim(p_identifier)))');
  if n=d then raise exception 'patch point not found'; end if;
  execute n;
end $patch$;
