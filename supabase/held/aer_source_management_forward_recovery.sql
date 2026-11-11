-- Forward recovery for migration 20261112113700_cf247_aer_source_management (F-AER.04 D3). Paste in the SQL editor (Platform Admin) or apply as a new migration.
-- Takes security.aer_matrix_machine_check_v1 back to its definition before the change, byte for byte (md5-guarded). Nothing is dropped: the attachments table, the
-- screen functions and the upload record stay (a drop goes to the Platform Admin as a paste file); the screen panel and edge function stop being used when the frontend is reverted.
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_matrix_machine_check_v1(uuid)', '26e7a3f959a5bc7c2c29fc9031c594c2', '8b25b3dcb246a08561dd0ebd48f0ff37',
     array[$o$  -- 12 Nov 2026 (D3): a copy a person uploaded is not proven to be what the official address serves; it stays with a person
  if f.read_via is null and exists (select 1 from pipeline.aer_source_attachments a where a.source_id = f.id and a.how = 'pdf_upload' and a.content_hash = f.content_hash) then
    return jsonb_build_object('ok', false, 'rule', 'uploaded_copy', 'reason', 'The stored copy was uploaded by a person, not fetched from the official address.', 'next_action', decline, 'checks', v_checks); end if;
  if r.content_hash is distinct from f.content_hash then$o$],
     array[$n$  if r.content_hash is distinct from f.content_hash then$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition migration 20261112113700 left (body md5 %)', r.sig, md5(v_src); end if;
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
