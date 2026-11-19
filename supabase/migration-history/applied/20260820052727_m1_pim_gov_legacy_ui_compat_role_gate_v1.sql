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
      and p.proname in ('ui_courses_decision_page','ui_scholarships_page','ui_qilt_outcomes_page','ui_prisms_student_flow_page')
  loop
    ddl:=pg_get_functiondef(r.oid);
    patched:=regexp_replace(
      ddl,
      'begin[[:space:]]+if auth\.uid\(\) is null then raise exception ''authentication required''[^;]*; end if;',
      E'begin\n  if auth.uid() is null then raise exception ''authentication required'' using errcode=''42501''; end if;\n  if security.current_role_rank() < 1 then raise exception ''assigned CourseFinder role required'' using errcode=''42501''; end if;',
      'i'
    );
    if patched=ddl then
      raise exception 'compatibility role guard patch failed for %',r.proname;
    end if;
    execute patched;
  end loop;

  for r in
    select p.oid,p.proname
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('ui_qilt_filter_options','ui_prisms_filter_options')
  loop
    ddl:=pg_get_functiondef(r.oid);
    patched:=replace(ddl,'case when auth.uid() is null then null else','case when auth.uid() is null or security.current_role_rank() < 1 then null else');
    if patched=ddl then
      raise exception 'compatibility filter role guard patch failed for %',r.proname;
    end if;
    execute patched;
  end loop;

  for r in
    select p.oid,p.proname
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('ui_attributes_list','ui_attribute_families_list','ui_attribute_groups_list','ui_attribute_options_list','ui_completeness_profiles_list')
  loop
    ddl:=pg_get_functiondef(r.oid);
    patched:=replace(ddl,'where auth.uid() is not null','where auth.uid() is not null and security.current_role_rank() >= 5');
    if patched=ddl then
      raise exception 'compatibility PIM role guard patch failed for %',r.proname;
    end if;
    execute patched;
  end loop;
end
$$;

grant execute on function public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean) to authenticated;
grant execute on function public.ui_scholarships_page(integer,integer,text,text,text,text,text,text) to authenticated;
grant execute on function public.ui_qilt_outcomes_page(integer,integer,text,text,text,uuid,text,integer,text,text) to authenticated;
grant execute on function public.ui_qilt_filter_options(text) to authenticated;
grant execute on function public.ui_prisms_student_flow_page(integer,integer,text,text,text,text,text,boolean,text,text) to authenticated;
grant execute on function public.ui_prisms_filter_options() to authenticated;
grant execute on function public.ui_attributes_list() to authenticated;
grant execute on function public.ui_attribute_families_list() to authenticated;
grant execute on function public.ui_attribute_groups_list() to authenticated;
grant execute on function public.ui_attribute_options_list(integer) to authenticated;
grant execute on function public.ui_completeness_profiles_list() to authenticated;
