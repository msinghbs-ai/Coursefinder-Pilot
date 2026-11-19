-- CF-247 priority queue: university search lists the largest matches first (by active courses), not the shortest name.
do $g$
declare d text; n text;
begin
  d:=pg_get_functiondef('security.admin_priority_search_v1(text,text)'::regprocedure);
  n:=replace(d,'order by length(coalesce(pr.display_name,pr.canonical_name)) limit 20',
               'order by (select count(*) from catalogue.courses c where c.provider_id=pr.id and c.lifecycle_status=''active'') desc, length(coalesce(pr.display_name,pr.canonical_name)) limit 20');
  if n=d then raise exception 'search edit did not apply'; end if;
  execute n;
end $g$;
