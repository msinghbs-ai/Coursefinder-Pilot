-- CF-247 / Decision 136 guard: the Zoho course lookup applied the Layer 4 search block only to
-- matches by course ID. A missing bracket meant "not blocked AND id matches OR code matches", so a
-- blocked course could be returned by its course code. No course is blocked today (0 rows), so no
-- output changed; the block now applies to both match types. Checksum-guarded.
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
