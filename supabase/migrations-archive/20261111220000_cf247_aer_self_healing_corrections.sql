-- CF-247 F-AER.02 AER self-healing: corrected reads keep draining Layer 4 when nobody reviews (Platform Admin 11 Nov 2026 05:42 AEDT: "Find the issue with AER not
-- admitting fast enough ... why parking on layer 4 ... Make sure platform is autonomous to execute this in future, self sustaining").
-- Guards: G1 (no job added), G2 (the new allowance is a setting with label, range, unit and used_by; no operational number in code), G3 (no consumer API object read or
--   changed), Decision 260 (housekeeping), "a passing qualification never switches anything on by itself" (no switch, mode or job state changed), Layer 4 authority unchanged
--   (a corrected read is a NEW waiting item; nothing is approved, admitted or made active here).
-- Evidence (production, read only, 11 Nov 2026 08:15-08:50 AEDT, project fxcwkweaxjtknorudmwp):
--   * Layer 4 holds 668 course_entry_first_read and 49 entry_matrix_first_run items (717 >= aer.schedule_layer4_max 600); no person has decided an AER item since 1 Nov.
--     Every hourly aer-scheduled-read run since 14:13Z on 10 Nov started 0 reads: back_pressure true and "the daily cap is reached" (200 used by the 04:13-13:13Z runs).
--   * aer-machine-admission (shadow) declines 354 of the 668: gate_incomplete 277, no_bound_page 39, row_unsupported 22, identity_not_admitted 16.
--   * Of the 277 incomplete reads, the shared recovery rule (security.aer_recovery_rule_v1) makes 160 eligible for an automatic corrected read today (changed_conditions 156:
--     the row limits were raised on 10 Nov by 20261111010000; reread_eligible 4). None is read again, for two reasons:
--     (1) security.aer_schedule_held_v1 sends every read with rows_cut > 0 to a person ('cut at the row limit: for a person') BEFORE it asks the recovery rule, so the 60
--         row-limit reads the rule makes eligible after the limit was raised are never read again (the comment's own rule is "never a row-limit cut under the SAME limit");
--     (2) security.aer_schedule_tick_v1 counts corrected reads and new reads against one 24-hour cap (aer.schedule_daily_max). New reads used it, back-pressure then
--         stopped new reads, and the cap also stopped the corrected reads, which are the only automatic way the waiting items are replaced. Nothing drains Layer 4.
-- What this changes:
--   1. security.aer_schedule_held_v1 (md5-guarded edit): a read cut at the row limit goes to the recovery rule like every other hold; it is read again only when the rule
--      makes it eligible (and course_entry_correction_check_v1 passes), otherwise it waits with the rule's class and next action ('held, not read again: row_limit (...)').
--   2. security.aer_schedule_tick_v1 (md5-guarded edit): corrected reads (held reads read again through D-R2) have their own 24-hour allowance,
--      aer.schedule_correction_daily_max (new setting, 100), at most batch.aer_schedule_held a run; aer.schedule_daily_max now counts new reads only. Corrected reads still
--      run under back-pressure (they replace a waiting item, never add one), within the AI guards and the OpenRouter floor. The run result carries corrections_used_24h,
--      corrections_daily_max and corrections_room. Spend: at most 100 x US$0.0058 = about US$0.58 a day more than today's ceiling, inside the US$14 daily AI ceiling.
--   3. Setting help of aer.schedule_daily_max and batch.aer_schedule_held updated to say so.
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 08:40 AEDT), before -> after:
--   security.aer_schedule_held_v1(integer) d390d02a5e9b59b6e8ffaadadbf2c7e8 -> d0863451d50241d239a8db2bb62cd15f
--   security.aer_schedule_tick_v1(boolean) f995e9521198ae57ab0401564e4e5a20 -> b96163772b72f02b6c9956b1a263224a
-- Replaces: security.aer_schedule_held_v1, security.aer_schedule_tick_v1 (same names; md5-guarded text edits, resulting md5 checked); taken back by
--   supabase/held/aer_self_healing_corrections_forward_recovery.sql
-- Retires: nothing.
-- Reversal without code: aer.schedule_correction_daily_max = 0 stops corrected reads by the job (new reads unchanged).

do $g$
declare r record;
begin
  for r in select * from (values ('security.aer_schedule_tick_v1(boolean)'), ('security.aer_schedule_held_v1(integer)'), ('security.aer_recovery_rule_v1(uuid)'),
                                 ('security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.aer_schedule_runs') is null then raise exception 'pipeline.aer_schedule_runs is missing'; end if;
end $g$;

-- 1. the setting ------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.schedule_correction_daily_max', 'Scheduled entry reading: corrected reads a day at most',
  'Most waiting course reads held as incomplete that the scheduled entry reading reads again (D-R2: a corrected read replaces the waiting item only when it is complete) in any 24 hours. Counted apart from new reads, so the waiting items keep being replaced while new reads are stopped by their cap or by Layer 4 back-pressure. 0 stops corrected reads by the job.',
  'number', to_jsonb(100), 0, 1000, 'reads a day', 946, 'Entry requirements', 'security.aer_schedule_tick_v1; job aer-scheduled-read',
  'CF-247 F-AER.02 (Platform Admin 11 Nov 2026 05:42 "self sustaining"): corrected reads have their own allowance; about US$0.58 a day at most')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings
   set help = 'Most NEW course reads the scheduled entry reading asks for in any 24 hours. Corrected reads of held items have their own allowance (aer.schedule_correction_daily_max). Manual batches are not counted.',
       reason = 'CF-247 F-AER.02: the daily cap counts new reads only; value unchanged', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.schedule_daily_max';
update pipeline.platform_toolset_settings
   set help = 'Most waiting course reads held as incomplete (printed requirements dropped that no row covers) that one run reads again through the corrected-read path (D-R2), within aer.schedule_correction_daily_max.',
       reason = 'CF-247 F-AER.02: counted against the corrected-read allowance; value unchanged', updated_at = now()
 where toolset_key = 'pipeline' and key = 'batch.aer_schedule_held';

-- 2. the guarded edits ------------------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_schedule_held_v1(integer)', 'd390d02a5e9b59b6e8ffaadadbf2c7e8', 'd0863451d50241d239a8db2bb62cd15f',
     array[$o$    elsif coalesce((g->>'rows_cut')::int, 0) > 0 then outcome := 'cut at the row limit: for a person';
    elsif jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';$o$],
     array[$n$    -- 11 Nov 2026 (F-AER.02 self-healing): a read cut at the row limit goes to the shared recovery rule like every other hold; it is read again only when the
    -- rule makes it eligible (the limit was raised since the read: changed_conditions), otherwise it waits with the rule's class (row_limit) and next action below
    elsif coalesce((g->>'rows_cut')::int, 0) = 0 and jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';$n$]),
    ('security.aer_schedule_tick_v1(boolean)', 'f995e9521198ae57ab0401564e4e5a20', 'b96163772b72f02b6c9956b1a263224a',
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
  ) v(sig, md5_before, md5_after, olds, news) loop
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

comment on function security.aer_schedule_held_v1(integer) is 'CF-247 scheduled AER reading (b): waiting course reads held as incomplete, each checked by the E13 gate and the shared recovery rule (security.aer_recovery_rule_v1); a read is eligible to be read again (D-R2) only when the rule makes it eligible and the correction check passes. A read cut at the row limit follows the same rule (F-AER.02, 11 Nov 2026): read again only when the limit was raised since the read.';

-- 3. register, post-check --------------------------------------------------------------------------------------------------------------------
do $post$ begin
  if position('rows_cut'')::int, 0) > 0 then outcome' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_held_v1(integer)'::regprocedure)) > 0 then
    raise exception 'post-check: row-limit cuts still bypass the recovery rule'; end if;
  if position('aer_recovery_rule_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_held_v1(integer)'::regprocedure)) = 0 then raise exception 'post-check: the recovery rule was lost'; end if;
  if position('aer.schedule_correction_daily_max' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_tick_v1(boolean)'::regprocedure)) = 0 then raise exception 'post-check: no corrected-read allowance'; end if;
  if position('v_l4max' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_tick_v1(boolean)'::regprocedure)) = 0 then raise exception 'post-check: the Layer 4 limit was lost'; end if;
  if position('aer_parked_items_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_tick_v1(boolean)'::regprocedure)) = 0 then raise exception 'post-check: parked holds lost'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'aer.schedule_correction_daily_max') then raise exception 'post-check: setting missing'; end if;
end $post$;
