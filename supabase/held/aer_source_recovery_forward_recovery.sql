-- HELD (not a migration): forward recovery for 20261110160000 (AER source recovery). Run only if the Platform Admin decides to take the three in-place edits back:
--   security.aer_schedule_tick_v1       the parked holds count against the Layer 4 limit again (live body md5 705375f3705eb739cbc2bc2b9d64de53)
--   security.aer_current_findings_v1    the no_source finding carries only its country again (live body md5 a9796f1cf7a3308c01972f2a4226eb90)
--   security.data_delivery_v1           the key aer_sources is removed (the text 20261110150000 leaves)
-- Each tick and findings edit is applied only to the text this change wrote (its after md5); a function that is neither that text nor the original stops with a message and nothing is applied.
-- The Data Delivery edit removes the one inserted line wherever it sits in whatever is live. The three new read-only functions (security.aer_parked_items_v1, security.aer_no_source_route_v1,
-- security.data_delivery_aer_v1) are left in place (nothing calls them once the edits are taken back); they are dropped by a paste file only on the Platform Admin's say. Repeatable.

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_schedule_tick_v1(boolean)', '705375f3705eb739cbc2bc2b9d64de53', 'f995e9521198ae57ab0401564e4e5a20',
     array[$o$v_rr jsonb; v_tech jsonb; v_parked int := 0;$o$,
           $o$  -- 10 Nov 2026 (AER source recovery): a hold the technical lane has parked with its reason (row limit, human input, duplicate, stale read) waits for a setting, a person or another copy of the page;
  -- it is not a decision a reviewer can make, so it does not use the capacity (security.aer_parked_items_v1). The limit itself is unchanged. With wc.aer_fair_on the count below is replaced as before.
  select count(*) into v_parked from security.aer_parked_items_v1();
  v_bp := v_l4 - v_parked + v_prog >= v_l4max;$o$,
           $o$'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked));$o$,
           $o$|| jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked);$o$],
     array[$n$v_rr jsonb; v_tech jsonb;$n$,
           $n$  v_bp := v_l4 + v_prog >= v_l4max;$n$,
           $n$'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech));$n$,
           $n$|| jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech);$n$]),
    ('security.aer_current_findings_v1()', 'a9796f1cf7a3308c01972f2a4226eb90', '13b3a30c15b10135a2441158fc80f48c',
     array[$o$(jsonb_build_object('country', e.country) || coalesce(jsonb_strip_nulls(jsonb_build_object('route', r.route, 'reason', r.reason, 'next_action', r.next_action, 'parked', r.parked,
                                                                                                    'courses_waiting', r.courses_waiting, 'best_url', r.best_url, 'best_score', r.best_score)), '{}'::jsonb)) evidence$o$,
           $o$from el e left join security.aer_no_source_route_v1() r on r.provider_id = e.provider_id where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)$o$],
     array[$n$jsonb_build_object('country', e.country) evidence$n$,
           $n$from el e where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)$n$]),
    ('security.data_delivery_v1()', '849453412a8b9a448118e7b87362752a', '04b560cfb6b79758e2b694c96771be33',
     array[$o$'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,
      'aer_sources', case when s.stream = 'aer' then security.data_delivery_aer_v1() end,$o$],
     array[$n$'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    if v_sig is null then raise exception '% is missing', r.sig; end if;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if r.sig <> 'security.data_delivery_v1()' then
      if md5(v_src) = r.md5_before then raise notice '%: already the original text', r.sig; continue; end if;
      if md5(v_src) <> r.md5_after then raise exception 'live % is neither the text this change wrote nor the original (body md5 %)', r.sig, md5(v_src); end if;
    elsif position('data_delivery_aer_v1' in v_src) = 0 then raise notice '%: carries no AER key', r.sig; continue;
    end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if r.sig <> 'security.data_delivery_v1()' and md5(v_src) <> r.md5_before then raise exception '% after the recovery has body md5 %, expected %', r.sig, md5(v_src), r.md5_before; end if;
    raise notice '%: restored', r.sig;
  end loop;
end $m$;
