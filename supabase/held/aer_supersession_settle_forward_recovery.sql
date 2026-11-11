-- Forward recovery for migration 20261112123700_cf247_aer_supersession_settle (F-AER.02). Paste in the SQL editor (Platform Admin) or apply as a new migration.
-- Takes security.aer_schedule_tick_v1 back to its definition before the change, byte for byte (md5-guarded). Nothing is dropped and no closed corrected read is reopened:
-- security.aer_supersession_settle_v1 stays, unused.
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_schedule_tick_v1(boolean)', '800af9161234c24387bff6a74d6acb99', 'b96163772b72f02b6c9956b1a263224a',
     array[$o$  -- 12 Nov 2026 (F-AER.02): a corrected read the reader skipped before reading records nothing; close it as refused so its item is not blocked
  if not p_preview then perform security.aer_supersession_settle_v1(); end if;
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;$o$],
     array[$n$  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition migration 20261112123700 left (body md5 %)', r.sig, md5(v_src); end if;
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
