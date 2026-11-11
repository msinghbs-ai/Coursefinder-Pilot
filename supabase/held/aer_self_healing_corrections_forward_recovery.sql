-- Forward recovery for migration 20261111110000_cf247_aer_self_healing_corrections (F-AER.02). Paste in the SQL editor (Platform Admin) or apply as a new
-- migration. Restores security.aer_schedule_held_v1 and security.aer_schedule_tick_v1 to the bodies they had before (md5 d390d02a... and f995e952...), byte for byte:
-- the same guarded text edits, reversed. The setting aer.schedule_correction_daily_max is left in place and set to 0 (nothing is deleted); with the old tick it is unused.
-- A quicker reversal without code: set aer.schedule_correction_daily_max to 0 on Settings > Pipeline settings (the job then reads no held item again).

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_schedule_held_v1(integer)', 'd0863451d50241d239a8db2bb62cd15f', 'd390d02a5e9b59b6e8ffaadadbf2c7e8',
     array[$o$    elsif coalesce((g->>'rows_cut')::int, 0) > 0 then outcome := 'cut at the row limit: for a person';
    elsif jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';$o$],
     array[$n$    -- 11 Nov 2026 (F-AER.02 self-healing): a read cut at the row limit goes to the shared recovery rule like every other hold; it is read again only when the
    -- rule makes it eligible (the limit was raised since the read: changed_conditions), otherwise it waits with the rule's class (row_limit) and next action below
    elsif coalesce((g->>'rows_cut')::int, 0) = 0 and jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';$n$]),
    ('security.aer_schedule_tick_v1(boolean)', 'b96163772b72f02b6c9956b1a263224a', 'f995e9521198ae57ab0401564e4e5a20',
     array[$o$v_rr jsonb; v_tech jsonb; v_parked int := 0;$o$,
           $o$  select coalesce(sum(x.course_reads + x.corrections), 0) into v_used from pipeline.aer_schedule_runs x$o$,
           $o$  v_room := greatest(0, least(v_batch, v_daymax - v_used));$o$,
           $o$                when v_room = 0 and v_daymax <= v_used then 'the daily cap is reached'
                when v_room = 0 then 'no course reads a run'
                when v_bal is not null and v_bal - v_room * v_cost < v_floor then$o$,
           $o$security.aer_schedule_held_v1(least(v_heldmax, v_room))$o$,
           $o$if not v_bp and v_room - v_nh > 0 then$o$,
           $o$security.aer_schedule_courses_v1((v_room - v_nh) * 2)$o$,
           $o$security.aer_fair_courses_v1(v_room - v_nh)$o$,
           $o$exit when v_nn >= v_room - v_nh;$o$,
           $o$'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked));$o$,
           $o$|| jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked);$o$],
     array[$n$v_rr jsonb; v_tech jsonb; v_parked int := 0;
        -- 11 Nov 2026 (F-AER.02 self-healing): corrected reads have their own 24-hour allowance, apart from new reads
        v_cmax int := security.pipeline_num_v1('aer.schedule_correction_daily_max', 100)::int; v_cused int := 0; v_croom int := 0;$n$,
           $n$  select coalesce(sum(x.course_reads), 0), coalesce(sum(x.corrections), 0) into v_used, v_cused from pipeline.aer_schedule_runs x$n$,
           $n$  v_room := greatest(0, least(v_batch, v_daymax - v_used));
  v_croom := greatest(0, least(v_heldmax, v_cmax - v_cused));$n$,
           $n$                when v_room = 0 and v_croom = 0 and (v_daymax <= v_used or v_cmax <= v_cused) then 'the daily cap is reached'
                when v_room = 0 and v_croom = 0 then 'no course reads a run'
                when v_bal is not null and v_bal - (v_room + v_croom) * v_cost < v_floor then$n$,
           $n$security.aer_schedule_held_v1(v_croom)$n$,
           $n$if not v_bp and v_room > 0 then$n$,
           $n$security.aer_schedule_courses_v1(v_room * 2)$n$,
           $n$security.aer_fair_courses_v1(v_room)$n$,
           $n$exit when v_nn >= v_room;$n$,
           $n$'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked,
                               'corrections_used_24h', v_cused, 'corrections_daily_max', v_cmax, 'corrections_room', v_croom));$n$,
           $n$|| jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked,
                            'corrections_used_24h', v_cused, 'corrections_daily_max', v_cmax, 'corrections_room', v_croom);$n$])
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

update pipeline.platform_toolset_settings set value = to_jsonb(0), reason = 'F-AER.02 forward recovery: corrected-read allowance not used', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.schedule_correction_daily_max';
