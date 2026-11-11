-- Forward recovery for migration 20261112093700_cf247_aer_matrix_machine_admission (F-AER.04, decision D1). Paste in the SQL editor (Platform Admin) or apply as a new migration.
-- Restores security.aer_machine_run_v1 to its body before the change (md5 ad143b44...), byte for byte, and switches the matrix class off. The ledger, validations, settings and
-- functions are kept (nothing is dropped or deleted). Rows the class admitted stay admitted: reverse any of them with security.aer_matrix_machine_withdraw_v1(item, reason).
-- A quicker reversal without code: aer.matrix_machine_mode 0 on Settings > Pipeline settings.

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_machine_run_v1()', 'f88ab3f16833dec601786af5c7cdbbcc', 'ad143b44722ba6fbc0129cd38386661c',
     array[$o$  if v_mode < 1 then return jsonb_build_object('mode', 0); end if;$o$,
           $o$                            'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap, 'suspension', v_susp);$o$],
     array[$n$  -- 12 Nov 2026 (F-AER.04, decision D1): with course admission off the job still steps the matrix class, which has its own switch (aer.matrix_machine_mode)
  if v_mode < 1 then return jsonb_build_object('mode', 0, 'matrix', security.aer_matrix_machine_run_v1()); end if;$n$,
           $n$                            'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap, 'suspension', v_susp)
         -- 12 Nov 2026 (F-AER.04, decision D1): the same job steps rule aer-matrix-machine-v1 (country tables and qualification rows); its own ledger, errors returned, never raised
         || jsonb_build_object('matrix', security.aer_matrix_machine_run_v1());$n$])
  ) v(sig, md5_before, md5_after, news, olds) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
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

update pipeline.platform_toolset_settings set value = to_jsonb(0), reason = 'F-AER.04 forward recovery: matrix machine class off', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.matrix_machine_mode';
