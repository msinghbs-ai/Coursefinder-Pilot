-- CF-247 coverage drill-down: catalogue.providers has canonical_name, not name; the course list read failed.
do $patch$
declare v_def text; v_old text:='p.name provider_name'; v_new text:='coalesce(p.display_name,p.canonical_name) provider_name';
begin
  if (select md5(prosrc) from pg_proc where oid='security.admin_course_coverage_read(text,jsonb)'::regprocedure)<>'20ba41b7e8a7c30342d5d5e903577ab9' then
    raise exception 'security.admin_course_coverage_read changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('security.admin_course_coverage_read(text,jsonb)'::regprocedure);
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'anchor not found exactly once'; end if;
  v_def:=replace(v_def,v_old,v_new);
  v_def:=replace(v_def,'order by p.name, c.canonical_title','order by coalesce(p.display_name,p.canonical_name), c.canonical_title');
  execute v_def;
end $patch$;
