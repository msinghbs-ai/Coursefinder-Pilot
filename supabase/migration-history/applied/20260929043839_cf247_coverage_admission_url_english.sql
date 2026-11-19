do $p$
declare v text;
begin
  v:=pg_get_functiondef('security.coverage_admission_apply_v1(int,text)'::regprocedure);
  v:=replace(v,'p_extractor text DEFAULT ''coverage-sweep-v0.5.4''::text)','p_extractor text DEFAULT ''coverage-sweep-v0.5.4''::text, p_attributes text[] DEFAULT ARRAY[''official_url''::text, ''english''::text])');
  v:=replace(v,$o$where action in ('write','differs');$o$,$n$where action in ('write','differs') and attribute=any(p_attributes);$n$);
  v:=replace(v,$o$cross join unnest(array['official_course_url','course_english','course_intake']) d$o$,$n$cross join unnest(array_remove(array['official_course_url', case when 'english'=any(p_attributes) then 'course_english' end, case when 'intakes'=any(p_attributes) then 'course_intake' end],null)) d$n$);
  if position('p_attributes text[]' in v)=0 or position('attribute=any(p_attributes)' in v)=0 or position('array_remove(array[''official_course_url''' in v)=0 then raise exception 'patch anchors not found'; end if;
  execute v;
  drop function security.coverage_admission_apply_v1(int,text);
  revoke all on function security.coverage_admission_apply_v1(int,text,text[]) from public, anon, authenticated;
end $p$;
