-- CF-247 AER selector fix: the cases (part before: the defects with the live definitions; part after: fixed).
select :'part' = 'before' as is_before \gset
create temp view rc as select i.id, security.aer_recovery_rule_v1(i.id) r from pipeline.layer4_review_items i
 where i.status = 'pending' and i.field_code = 'course_entry_first_read';
\if :is_before
do $$
declare v_cc int; v_el int; v_lane int; m jsonb;
begin
  select count(*) into v_cc from rc where r->>'class' = 'changed_conditions' and r->>'gate_class' = 'row_limit';
  if v_cc < 100 then raise exception 'before: expected the row-limit cuts classed changed_conditions (production 109), found %', v_cc; end if;
  raise notice 'before (defect reproduced): % row-limit cuts classed changed_conditions although no row limit applying to them changed', v_cc;
  select count(*) into v_lane from pipeline.work_items w where w.lane = 'aer_technical' and w.unresolved_blocker->>'class' = 'reread_eligible' and w.stage <> 'done';
  select count(*) filter (where eligible) into v_el from security.aer_schedule_held_v1(10);
  if v_el <> 0 or v_lane < 40 then raise exception 'before: expected no eligible read reached with % waiting (found %)', v_lane, v_el; end if;
  raise notice 'before (defect reproduced): the held step scans 40 holds and reaches none of the % items the rule makes eligible', v_lane;
  m := security.progress_measure_v1('aer_technical_correction', now() - interval '1 hour');
  if (m->>'created')::int <> 0 then raise exception 'before: expected created 0, found %', m; end if;
  raise notice 'before (defect reproduced): the measure counts created 0 although 2 corrected reads replaced their read in the window (%)', m->>'basis';
end $$;
\else
select security.aer_technical_recovery_v1() \gset lane_
do $$
declare v_cc int; v_rl int; v_el int; v_bad int; v_pid uuid; v_item uuid; m jsonb; v_lane_el int; v_par int;
begin
  -- 1 a row-limit cut stays a row-limit hold while no limit applying to it changed
  select count(*) into v_cc from rc where r->>'class' = 'changed_conditions' and r->>'gate_class' = 'row_limit';
  select count(*) into v_rl from rc where r->>'class' = 'row_limit';
  if v_cc <> 0 then raise exception 'after: % row-limit cuts still changed_conditions', v_cc; end if;
  if exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.unresolved_blocker->>'class' = 'changed_conditions' and w.stage <> 'done'
               and exists (select 1 from rc where rc.id::text = w.entity and rc.r->>'gate_class' = 'row_limit')) then
    raise exception 'after: the lane still holds a row-limit cut as eligible'; end if;
  raise notice 'ok: row-limit cuts are row_limit holds (%), parked by the lane, none eligible', v_rl;
  -- 2 a row limit for the university, set after the read, makes its cuts eligible again; without it, not
  select rc.id, c.provider_id into v_item, v_pid from rc join pipeline.layer4_review_items i on i.id = rc.id join catalogue.courses c on c.id = i.entity_id
   where rc.r->>'class' = 'row_limit' and rc.r->>'gate_class' = 'row_limit' limit 1;
  update pipeline.platform_toolset_settings set value = jsonb_build_array(v_pid::text || '=10'), updated_at = now() where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';
  if security.aer_recovery_rule_v1(v_item)->>'class' <> 'changed_conditions' then raise exception 'after: a new row limit for the university did not make the cut eligible'; end if;
  update pipeline.platform_toolset_settings set value = jsonb_build_array(gen_random_uuid()::text || '=10') where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';
  if security.aer_recovery_rule_v1(v_item)->>'class' <> 'row_limit' then raise exception 'after: another university''s row limit made the cut eligible'; end if;
  update pipeline.platform_toolset_settings set value = '[]'::jsonb, updated_at = '2026-11-01 19:43:26.950319+00' where toolset_key = 'pipeline' and key = 'entry.max_rows_by_provider';
  raise notice 'ok: a row limit for its own university set after the read makes a cut eligible; another university''s does not';
  -- 3 the held step reaches what the rule makes eligible, and nothing else
  select count(*) filter (where h.eligible), count(*) filter (where h.eligible and coalesce(security.aer_recovery_rule_v1(h.item_id)->>'class', '') not in ('reread_eligible', 'changed_conditions'))
    into v_el, v_bad from security.aer_schedule_held_v1(10) h;
  if v_el = 0 or v_bad > 0 then raise exception 'after: held step eligible %, of which % not eligible by the rule', v_el, v_bad; end if;
  if exists (select 1 from security.aer_schedule_held_v1(10) h join pipeline.work_items w on w.lane = 'aer_technical' and w.entity = h.item_id::text
              where w.failure_class in ('aer_row_limit', 'aer_unchanged_evidence')) then raise exception 'after: a deterministic hold was scanned'; end if;
  raise notice 'ok: the held step asks % corrected reads (batch 10), all eligible by the shared rule; no deterministic hold scanned', v_el;
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
  if (select producer_jobs from pipeline.progress_transitions where key = 'aer_technical_correction') <> '{aer-scheduled-read}' then raise exception 'producer'; end if;
  raise notice 'ok: aer_technical_correction is produced by aer-scheduled-read';
end $$;
\endif
