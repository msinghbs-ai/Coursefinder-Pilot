-- Forward recovery for migration 20261112110700_cf247_aer_matrix_machine_quote_proof (F-AER.04 D1). Paste in the SQL editor (Platform Admin) or apply as a new migration.
-- Takes security.aer_matrix_machine_check_v1 and security.aer_matrix_machine_validate_v1 back to their definitions before the change, byte for byte (md5-guarded), and sets
-- aer.matrix_machine_mode to 1 (shadow) first, so no read is admitted without the quote proof. Run it before the recovery of 20261112113700 only if that one was taken back
-- first (the check's md5 chain). Nothing is dropped: security.aer_quote_has_value_v1 stays.
update pipeline.platform_toolset_settings set value = to_jsonb(least((value #>> '{}')::numeric, 1)), reason = 'forward recovery of 20261112110700', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.matrix_machine_mode';
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_matrix_machine_check_v1(uuid)', '8b25b3dcb246a08561dd0ebd48f0ff37', '6eece704435e4c72cdbcbccc683b194f',
     array[$o$                when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote' end why$o$,
           $o$                when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote' end$o$],
     array[$n$                when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum' end why$n$,
           $n$                when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum' end$n$]),
    ('security.aer_matrix_machine_validate_v1()', '5c9d6e287b60f1a48fb28f71f4c3dba3', 'c4cb5e0f02bcee4b04c5bb0702c2a8c7',
     array[$o$                                  or not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null)
                                  or not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value)))$o$],
     array[$n$                                  or not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null)))$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition migration 20261112110700 left (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;
