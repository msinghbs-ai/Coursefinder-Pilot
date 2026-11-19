
do $$
declare v_oid oid;v_def text;v_old text;v_new text;
begin
 select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='layer2_scale_qualification_prepare' limit 1;
 if v_oid is null then raise exception 'prepare function not found'; end if;
 select pg_get_functiondef(v_oid) into v_def;
 v_old:='    where qi.run_id=p_run_id
    order by p.canonical_name';
 v_new:='    where qi.run_id=p_run_id
      and qi.status in (''selected'',''qualifying'')
    order by p.canonical_name';
 if position(v_old in v_def)=0 then raise exception 'prepare provider anchor not found'; end if;
 v_def:=replace(v_def,v_old,v_new);
 execute v_def;
end $$;
