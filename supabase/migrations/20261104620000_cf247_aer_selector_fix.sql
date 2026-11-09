-- CF-247 AER selector fix (v2.15.473 first-run verification, Integration Controller 4 Nov 2026 20:02; follows 20261104580000).
-- Why (production, read only, 4 Nov 2026 20:08-20:13 AEDT):
--   * first-run-verify judged job work-continuity (run 1229030, 18:58) on transition aer_technical_correction at 19:02: "55 eligible, 0 processed,
--     nothing created". work-continuity only returns due items to stage eligible; the corrected reads are asked by aer-scheduled-read at :13, and the
--     shared rule first ran at 19:13. The measure counted the lane's bookkeeping (items in stage eligible, re-checks, lane recoveries), so the 2
--     corrected reads that replaced their read at 18:14 (no lane item) counted nothing.
--   * The shared rule (security.aer_recovery_rule_v1) classed 109 items cut at the row limit as changed_conditions (eligible): it compared the newest
--     entry.% setting time (all touched 3 Nov 20:07, values unchanged) with the item's creation. None of them can be read again usefully: their
--     row limit (entry.max_rows_per_course 6, set 28 Oct; no university limit) is the one they were cut under.
--   * The held step (security.aer_schedule_held_v1) scans 40 waiting items in order of last check; at 19:13 its 40 were row-limit cuts (19), shared
--     pages (12), complete (4), unchecked (3) and decisions (2). None of the 51 items the rule makes eligible was reached, so no corrected read was asked.
-- What (three md5-guarded edits and one row; no cap, spending, enqueue or switch change):
--   1. security.aer_recovery_rule_v1: a row-limit cut is changed_conditions only when a row-limit setting that applies to its university
--      (entry.max_rows_per_course, or its own entry in entry.max_rows_by_provider) changed after its last read.
--   2. security.aer_schedule_held_v1: items the rule last classed reread_eligible, then changed_conditions, are scanned first.
--   3. security.progress_measure_v1 (owner: verification measures, v2.15.469), branch aer_technical_correction: eligible = items the rule allows a
--      corrected read (deterministic holds parked, not counted); processed = corrected reads asked; created = reads that replaced the held read;
--      excluded/rejected = refused by the reader; downstream = replacements in Layer 4; cap = the last scheduled run's refusal.
--   4. pipeline.progress_transitions aer_technical_correction: producer aer-scheduled-read (was work-continuity).
-- Before (live, 4 Nov 2026 20:08 AEDT) -> after:
--   security.aer_recovery_rule_v1(uuid) b194475a46186bc674a3364816a8b06b -> 605cba4a9b49d1cfebee8ada5414b561
--   security.aer_schedule_held_v1(integer) c866167b55d2494c366fd2700a518ff8 -> 483fbcead73c7996d02c372fd6128108
--   security.progress_measure_v1(text,timestamp with time zone) 40c0c972abc353be8f6eee35c79750e9 -> 4f10e10e25c30f35f05f7ba1bbb2a4d8
-- Replaces: security.aer_recovery_rule_v1, security.aer_schedule_held_v1, security.progress_measure_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object, cap, spending limit, setting, job, admission authority or gate changes.

do $g$
begin
  if to_regprocedure('security.course_entry_max_rows_v1(uuid)') is null or to_regclass('pipeline.progress_transitions') is null then
    raise exception 'needs the E13 row limit (security.course_entry_max_rows_v1) and first-run verification (pipeline.progress_transitions)'; end if;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 the rule: a row-limit cut changes only with a row limit that applies to it, set after its last read
select pg_temp.edit_once('security.aer_recovery_rule_v1(uuid)', 'b194475a46186bc674a3364816a8b06b', '605cba4a9b49d1cfebee8ada5414b561', array[
  [$e$    when v_cls = 'row_limit' and v_set_at > r.created_at then 'changed_conditions'$e$,
   $e$    -- 4 Nov 2026 20:02 (v2.15.473 first run): only a row limit that applies to this university, set after the last read, changes a row-limit cut
    when v_cls = 'row_limit' and (select max(t.updated_at) from pipeline.platform_toolset_settings t where t.toolset_key = 'pipeline'
                                     and (t.key = 'entry.max_rows_per_course' or (t.key = 'entry.max_rows_by_provider' and jsonb_typeof(t.value) = 'array'
                                          and exists (select 1 from jsonb_array_elements_text(t.value) e where btrim(split_part(e, '=', 1)) = v_pid::text))))
         > greatest(r.created_at, coalesce(v_last.closed_at, v_last.requested_at, r.created_at)) then 'changed_conditions'$e$]], array[1]);

-- 2 the held step: what the rule makes eligible is scanned first
select pg_temp.edit_once('security.aer_schedule_held_v1(integer)', 'c866167b55d2494c366fd2700a518ff8', '483fbcead73c7996d02c372fd6128108', array[
  [$e$            order by k.checked_at nulls first, i.created_at, i.id$e$,
   $e$            -- 4 Nov 2026 20:02 (v2.15.473 first run): items the shared rule last made eligible first, so the scan is not spent on holds it never reads
            order by coalesce((select case w.unresolved_blocker->>'class' when 'reread_eligible' then 0 when 'changed_conditions' then 1 end from pipeline.work_items w
                                where w.lane = 'aer_technical' and w.entity = i.id::text and w.work_kind = 'l4_item' and w.failure_class = 'aer_reread_eligible'
                                  and w.stage <> 'done' limit 1), 2),
                     k.checked_at nulls first, i.created_at, i.id$e$]], array[1]);

-- 3 the measure: corrected reads, not the lane's bookkeeping
select pg_temp.edit_once('security.progress_measure_v1(text,timestamp with time zone)', '40c0c972abc353be8f6eee35c79750e9', '4f10e10e25c30f35f05f7ba1bbb2a4d8', array[
  [$e$    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'eligible'),
      'processed', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.last_attempt_at >= p_since),
      'created', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.recovered_at >= p_since),
      'parked',$e$,
   $e$    -- 4 Nov 2026 20:02 (v2.15.473 first run): the corrected reads of held items (D-R2, job aer-scheduled-read), not the lane's bookkeeping;
    -- eligible is what the shared rule (security.aer_recovery_rule_v1) allows a corrected read: deterministic holds are parked, not counted
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'aer_reread_eligible' and w.stage <> 'done'),
      'processed', (select count(*) from pipeline.aer_read_supersessions s where s.requested_at >= p_since),
      'created', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'superseded' and s.closed_at >= p_since),
      'excluded', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'refused' and s.closed_at >= p_since),
      'rejected', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'refused' and s.closed_at >= p_since),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select case when s.outcome ilike '%row limit%' then 'cut at the row limit'
                             when s.outcome ilike '%still drops%' then 'still drops printed requirements' else left(coalesce(s.outcome, 'refused'), 80) end k, count(*) n
                             from pipeline.aer_read_supersessions s where s.state = 'refused' and s.closed_at >= p_since group by 1) z),
      'downstream', (select count(*) from pipeline.aer_read_supersessions s join pipeline.layer4_review_items n on n.id = s.new_item_id
                      where s.state = 'superseded' and s.closed_at >= p_since),
      'in_progress', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'requested'),
      'recovered', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.recovered_at >= p_since),
      'cap', (select x.refusal is not null from pipeline.aer_schedule_runs x order by x.ran_at desc limit 1),
      'cap_detail', (select x.refusal from pipeline.aer_schedule_runs x order by x.ran_at desc limit 1),
      'parked',$e$],
  [$e$      'last_output_at', (select max(w.recovered_at) from pipeline.work_items w where w.lane = 'aer_technical'),
      'basis', 'work items of lane aer_technical: eligible, attempted, recovered, parked by failure class') into v;$e$,
   $e$      'last_output_at', (select max(s.closed_at) from pipeline.aer_read_supersessions s where s.state = 'superseded'),
      'basis', 'corrected reads of held AER items (job aer-scheduled-read): eligible = items the shared recovery rule allows a corrected read; processed = corrected reads asked; created = reads that replaced the held read; rejected = refused by the reader; parked = lane aer_technical holds by class') into v;$e$]],
  array[1, 1]);

-- 4 the transition's producer
update pipeline.progress_transitions set producer_jobs = '{aer-scheduled-read}'
 where key = 'aer_technical_correction' and producer_jobs = '{work-continuity}';

do $p$
begin
  if (select producer_jobs from pipeline.progress_transitions where key = 'aer_technical_correction') <> '{aer-scheduled-read}' then
    raise exception 'post-check: aer_technical_correction is not produced by aer-scheduled-read'; end if;
end $p$;
