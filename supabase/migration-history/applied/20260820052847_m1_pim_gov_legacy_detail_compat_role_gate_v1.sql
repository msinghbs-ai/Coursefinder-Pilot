do $$
declare
  r record;
  ddl text;
  patched text;
begin
  for r in
    select p.oid,p.proname
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('ui_course_detail','ui_course_related_campuses','ui_scholarship_detail')
  loop
    ddl:=pg_get_functiondef(r.oid);
    patched:=replace(ddl,'auth.uid() is not null','auth.uid() is not null and security.current_role_rank() >= 1');
    if patched=ddl then
      raise exception 'legacy detail role guard patch failed for %',r.proname;
    end if;
    execute patched;
  end loop;
end
$$;

grant execute on function public.ui_course_detail(uuid) to authenticated;
grant execute on function public.ui_course_related_campuses(uuid) to authenticated;
grant execute on function public.ui_scholarship_detail(uuid) to authenticated;
