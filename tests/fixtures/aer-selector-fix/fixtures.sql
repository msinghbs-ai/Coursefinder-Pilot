-- CF-247 AER selector fix: the cases. Part before: the held-step and measure defects with the live definitions; part after: fixed. The row-limit
-- regression (a setting TIME moving is not a changed condition) runs in both parts: live already holds it (rule 35281a19, 20261107130100) and this change
-- must not disturb it.
select :'part' = 'before' as is_before \gset
create temp view rc as select i.id, security.aer_recovery_rule_v1(i.id) r from pipeline.layer4_review_items i
 where i.status = 'pending' and i.field_code = 'course_entry_first_read';

-- R row-limit regression (negative and positive), both parts
do $$
declare v_cut int; v_el int; v_item uuid; v_pid uuid; v_need int;
begin
  -- negative: every entry.% setting was touched after the cuts were read (values unchanged); none of the cuts is eligible
  select count(*) into v_cut from rc join pipeline.layer4_review_items i on i.id = rc.id
   where rc.r->>'gate_class' = 'row_limit' and i.created_at < (select max(updated_at) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'entry.%');
  select count(*) into v_el from rc where rc.r->>'gate_class' = 'row_limit' and (rc.r->>'eligible')::boolean;
  if v_cut < 100 then raise exception 'row limit: the seed lacks the production precondition (cuts read before the settings were touched): %', v_cut; end if;
  if v_el <> 0 then raise exception 'row limit: % cuts are eligible although no row limit changed', v_el; end if;
  raise notice 'ok: % row-limit cuts read before the entry settings were last touched, none eligible (a setting time alone changes nothing)', v_cut;
  -- positive and negative on one cut, inside a sub-transaction that is rolled back
  select rc.id, c.provider_id, (rc.r->>'rows_needed')::int into v_item, v_pid, v_need from rc join pipeline.layer4_review_items i on i.id = rc.id
    join catalogue.courses c on c.id = i.entity_id where rc.r->>'class' = 'row_limit' and rc.r->>'gate_class' = 'row_limit' order by (rc.r->>'rows_needed')::int limit 1;
  begin
    -- a bare touch (same value, newer time) of the settings that apply: still a row-limit hold
    update pipeline.platform_toolset_settings set updated_at = now() where toolset_key = 'pipeline' and key in ('entry.max_rows_per_course', 'entry.max_rows_by_provider');
    if security.aer_recovery_rule_v1(v_item)->>'class' <> 'row_limit' then raise exception 'row limit: touching the row-limit settings without a new value made the cut eligible'; end if;
    -- a limit for its university below what the read needs: not eligible
    update pipeline.platform_toolset_settings set value = jsonb_build_array(v_pid::text || '=' || (v_need - 1)), updated_at = now() where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';
    if security.aer_recovery_rule_v1(v_item)->>'class' <> 'row_limit' then raise exception 'row limit: a limit of % (needs %) made the cut eligible', v_need - 1, v_need; end if;
    -- another university's limit: not eligible
    update pipeline.platform_toolset_settings set value = jsonb_build_array(gen_random_uuid()::text || '=' || (v_need + 5)), updated_at = now() where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';
    if security.aer_recovery_rule_v1(v_item)->>'class' <> 'row_limit' then raise exception 'row limit: another university''s limit made the cut eligible'; end if;
    -- its own university's limit that fits the read: eligible again
    update pipeline.platform_toolset_settings set value = jsonb_build_array(v_pid::text || '=' || v_need), updated_at = now() where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';
    if security.aer_recovery_rule_v1(v_item)->>'class' <> 'changed_conditions' then raise exception 'row limit: a limit of % for its own university did not make the cut eligible', v_need; end if;
    raise exception 'fx_rollback';
  exception when others then if sqlerrm <> 'fx_rollback' then raise; end if; end;
  raise notice 'ok: a bare setting touch, a limit below the need and another university''s limit leave the cut a row-limit hold; its own university''s limit of % (the need) makes it eligible', v_need;
end $$;

\if :is_before
do $$
declare v_lane int; v_el int; m jsonb;
begin
  -- the held step with the live order: its scan is spent on holds, none of the items the rule makes eligible is reached
  select count(*) into v_lane from pipeline.work_items w where w.lane = 'aer_technical' and w.unresolved_blocker->>'class' in ('reread_eligible', 'changed_conditions') and w.stage <> 'done';
  select count(*) filter (where eligible) into v_el from security.aer_schedule_held_v1(10);
  if v_el <> 0 or v_lane < 40 then raise exception 'before: expected no eligible read reached with % waiting (found %)', v_lane, v_el; end if;
  raise notice 'before (defect reproduced): the held step scans 40 holds and reaches none of the % items the rule makes eligible', v_lane;
  -- the measure counted the lane's bookkeeping, not the corrected reads
  m := security.progress_measure_v1('aer_technical_correction', now() - interval '1 hour');
  if (m->>'created')::int <> 0 then raise exception 'before: expected created 0, found %', m; end if;
  raise notice 'before (defect reproduced): the measure counts created 0 although 2 corrected reads replaced their read in the window (%)', m->>'basis';
  if (select producer_jobs from pipeline.progress_transitions where key = 'aer_technical_correction') <> '{work-continuity}' then raise exception 'before: producer'; end if;
end $$;
\else
select security.aer_technical_recovery_v1() \gset lane_
do $$
declare v_el int; v_bad int; v_scanned int; v_ahead int; v_item uuid; m jsonb; v_lane_el int; v_par int; v_def text;
begin
  -- 1 the rule is the live rule: this change did not touch it
  if md5(pg_get_functiondef('security.aer_recovery_rule_v1(uuid)'::regprocedure)) <> '35281a190b1465699ef3cc7eccaf6d41' then raise exception 'after: the rule was changed'; end if;
  if exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.unresolved_blocker->>'class' = 'changed_conditions' and w.stage <> 'done'
               and exists (select 1 from rc where rc.id::text = w.entity and rc.r->>'gate_class' = 'row_limit')) then
    raise exception 'after: the lane still holds a row-limit cut as eligible'; end if;
  raise notice 'ok: the rule is the live rule (35281a19); the lane holds no row-limit cut as eligible';
  -- 2 the held step reaches what the rule makes eligible, and nothing else
  select count(*) filter (where h.eligible), count(*) filter (where h.eligible and coalesce(security.aer_recovery_rule_v1(h.item_id)->>'class', '') not in ('reread_eligible', 'changed_conditions')),
         count(*), count(*) filter (where coalesce(security.aer_recovery_rule_v1(h.item_id)->>'class', '') not in ('reread_eligible', 'changed_conditions'))
    into v_el, v_bad, v_scanned, v_ahead from security.aer_schedule_held_v1(10) h;
  if v_el = 0 or v_bad > 0 then raise exception 'after: held step eligible %, of which % not eligible by the rule', v_el, v_bad; end if;
  if v_ahead > 0 then raise exception 'after: % of the % scanned items are not eligible by the rule although more than the scan of them wait', v_ahead, v_scanned; end if;
  if exists (select 1 from security.aer_schedule_held_v1(10) h join pipeline.work_items w on w.lane = 'aer_technical' and w.entity = h.item_id::text
              where w.failure_class in ('aer_row_limit', 'aer_unchanged_evidence')) then raise exception 'after: a deterministic hold was scanned'; end if;
  raise notice 'ok: the held step scans % items, all eligible by the shared rule, and asks % corrected reads (batch 10); no deterministic hold scanned', v_scanned, v_el;
  -- 3 negative: the scan filters of the held step are unchanged (an item read again within the retry period, or at the tries limit, is not scanned)
  begin
    select h.item_id into v_item from security.aer_schedule_held_v1(10) h where h.eligible limit 1;
    insert into pipeline.aer_read_supersessions(old_item_id, course_id, state, outcome, requested_at, closed_at)
      select i.id, i.entity_id, 'refused', 'the corrected read still drops 1 printed requirement(s)', now() - interval '1 day', now() - interval '1 day' from pipeline.layer4_review_items i where i.id = v_item;
    if exists (select 1 from security.aer_schedule_held_v1(10) h where h.item_id = v_item) then raise exception 'after: an item read again yesterday was scanned'; end if;
    raise exception 'fx_rollback';
  exception when others then if sqlerrm <> 'fx_rollback' then raise; end if; end;
  raise notice 'ok: an item with a corrected read inside the retry period is not scanned (the held step''s own filters are unchanged)';
  -- 4 the measure counts corrected reads; deterministic holds are not eligible
  m := security.progress_measure_v1('aer_technical_correction', now() - interval '1 hour');
  select count(*) filter (where w.failure_class = 'aer_reread_eligible' and w.stage <> 'done'), count(*) filter (where w.stage = 'parked')
    into v_lane_el, v_par from pipeline.work_items w where w.lane = 'aer_technical';
  if (m->>'created')::int <> 2 or (m->>'downstream')::int <> 2 or (m->>'processed')::int <> 3 or (m->>'rejected')::int <> 1 or (m->>'excluded')::int <> 1
     or (m->>'eligible')::int <> v_lane_el or (m->>'parked')::int <> v_par or (m->>'parked')::int = 0 then
    raise exception 'after: measure %', m; end if;
  if exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class in ('aer_row_limit', 'aer_unchanged_evidence') and w.stage <> 'parked') then
    raise exception 'after: a deterministic hold is not parked'; end if;
  raise notice 'ok: measure created 2, downstream 2, processed 3, rejected 1, eligible % (rule-eligible only), parked % not counted as eligible', v_lane_el, v_par;
  -- 5 negative: the lane's own bookkeeping (a recovery or a re-check) is not a corrected read; a read outside the window is not counted
  begin
    update pipeline.work_items set recovered_at = now(), last_attempt_at = now() where id = (select id from pipeline.work_items where lane = 'aer_technical' and stage <> 'done' limit 1);
    m := security.progress_measure_v1('aer_technical_correction', now() - interval '1 hour');
    if (m->>'created')::int <> 2 or (m->>'processed')::int <> 3 or (m->>'recovered')::int < 1 then raise exception 'after: bookkeeping counted as corrected reads: %', m; end if;
    m := security.progress_measure_v1('aer_technical_correction', now() + interval '1 hour');
    if (m->>'created')::int <> 0 or (m->>'processed')::int <> 0 then raise exception 'after: reads outside the window counted: %', m; end if;
    raise exception 'fx_rollback';
  exception when others then if sqlerrm <> 'fx_rollback' then raise; end if; end;
  raise notice 'ok: a lane recovery or re-check is not a corrected read; a window after the reads counts none';
  -- 6 the measure keeps every other branch (the intake branches of 20261106400000 and the other AER branches are intact)
  v_def := pg_get_functiondef('security.progress_measure_v1(text,timestamp with time zone)'::regprocedure);
  if position('when ''intake_selection'' then' in v_def) = 0 or position('when ''aer_extraction'' then' in v_def) = 0 or position('when ''aer_layer4_review'' then' in v_def) = 0 then
    raise exception 'after: the measure lost a branch'; end if;
  if (select producer_jobs from pipeline.progress_transitions where key = 'aer_technical_correction') <> '{aer-scheduled-read}' then raise exception 'producer'; end if;
  if (select producer_jobs from pipeline.progress_transitions where key = 'aer_extraction') <> '{aer-scheduled-read,entry-matrix-read}' then raise exception 'another transition changed'; end if;
  raise notice 'ok: the intake and other AER measure branches are intact; aer_technical_correction is produced by aer-scheduled-read; no other transition changed';
end $$;
\endif
