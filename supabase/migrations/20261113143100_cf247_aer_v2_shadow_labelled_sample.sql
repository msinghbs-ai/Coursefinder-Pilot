-- CF-247 Decision 276 AER v2 step 1 (Platform Admin 12 Nov 2026 17:20; admin docs/platform/AER-DESIGN-V2-PROPOSAL.md v0.3 §9 amendment: "measure agreement with
-- Layer 4 decisions before any admission"): the shadow sample reads courses with a Layer 4 decision alongside the priority providers, one for one.
-- Guards: G1 (no new job), G2 (no new value: the sample size and tries stay settings), G3 (no consumer API object), Decision 260, nothing admitted.
-- Evidence: the first run (12 Nov 2026 20:38 AEDT) read 20 Canterbury pages; the sample put the 1,020 priority-provider courses first, and those universities have
--   no country table, so none has a decided row: labelled agreement was 0 of 0 and would stay unmeasured for about a day. 971 of the 1,027 courses with a
--   decided row (pipeline.aer_labelled_rows_v1) have a bound, stored course page.
-- What: security.aer_v2_shadow_candidates_v1 (md5-guarded text edit): three lanes, decided-row courses, priority providers, the rest; the first two are taken one
--   for one, then the rest. Rolled-back live check: the next 20 are decided-row courses (the first 20 priority courses are read), 1.7 s.
-- Live definition this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 21:05 AEDT): security.aer_v2_shadow_candidates_v1 145904dd4d74e23314c7ca57198b68d3
-- Replaces: security.aer_v2_shadow_candidates_v1 (same name; md5-guarded text edit). Retires: nothing.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;


select pg_temp.edit_n('security.aer_v2_shadow_candidates_v1(text,integer)', '145904dd4d74e23314c7ca57198b68d3', array[
  array[$o1$  -- the sample: priority providers first (in the setting's order), then a stable spread of the rest
  sample as (select pool.*, row_number() over (order by (pool.priority is null), pool.priority, md5(pool.course_id::text)) sample_rank from pool)$o1$,
        $n1$  -- the sample (12 Nov 2026, AER v2 step 1 measure): courses with a Layer 4 decision (pipeline.aer_labelled_rows_v1) and the priority providers' courses,
  -- one for one, so agreement with decided rows is measured from the first runs; then a stable spread of the rest
  lab as materialized (select distinct l.course_id from pipeline.aer_labelled_rows_v1 l where l.course_id is not null),
  laned as (select pool.*, case when exists (select 1 from lab where lab.course_id = pool.course_id) then 1 when pool.priority is not null then 2 else 3 end lane from pool),
  ranked as (select laned.*, row_number() over (partition by laned.lane order by laned.priority nulls last, md5(laned.course_id::text)) lane_rank from laned),
  sample as (select ranked.*, row_number() over (order by (ranked.lane = 3), ranked.lane_rank, ranked.lane) sample_rank from ranked)$n1$]
], array[1]);
