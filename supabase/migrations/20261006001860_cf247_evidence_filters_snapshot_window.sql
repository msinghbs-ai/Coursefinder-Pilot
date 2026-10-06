do $p$
declare v_def text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_evidence_filter_options()'::regprocedure) is distinct from '2c6ad61f540b3335c2d8a4fadc8f92a6' then
    raise exception 'security.admin_evidence_filter_options is not the expected definition; refusing to replace it';
  end if;
  v_def := pg_get_functiondef('security.admin_evidence_filter_options()'::regprocedure);
  if (length(v_def) - length(replace(v_def, 'interval ''60 minutes''', ''))) / length('interval ''60 minutes''') <> 1 then
    raise exception 'expected snippet not found exactly once';
  end if;
  v_new := replace(v_def, 'interval ''60 minutes''', 'interval ''150 minutes''');
  execute v_new;
end $p$;
