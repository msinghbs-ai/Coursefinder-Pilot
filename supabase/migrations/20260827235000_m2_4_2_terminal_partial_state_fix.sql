-- M2.4.2 — completed PARTIAL batches are terminal history, not active runs.
begin;

do $$
declare r record; v_def text; v_new text;
begin
  for r in
    select p.oid
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.prokind='f' and n.nspname='public'
      and p.proname in ('layer2_operator_scope_service','layer2_operator_sync_service','layer2_scope_profile_batch_service')
  loop
    select pg_get_functiondef(r.oid) into v_def;
    v_new:=replace(v_def,
      'b.status in (''queued'',''running'',''partial'')',
      '(b.status in (''queued'',''running'') or (b.status=''partial'' and b.completed_at is null))'
    );
    if v_new=v_def then raise exception 'active batch predicate marker not found for oid %',r.oid; end if;
    execute v_new;
  end loop;
end $$;

do $$
declare r record; v_def text; v_new text;
begin
  for r in
    select p.oid,p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.prokind='f' and n.nspname='public'
      and p.proname in ('layer2_run_batch_cancel','layer2_run_batch_start')
  loop
    select pg_get_functiondef(r.oid) into v_def;
    v_new:=replace(v_def,
      'status in (''queued'',''running'',''partial'')',
      '(status in (''queued'',''running'') or (status=''partial'' and completed_at is null))'
    );
    if v_new=v_def then raise exception 'batch state predicate marker not found for %',r.proname; end if;
    execute v_new;
  end loop;
end $$;

commit;
