-- CF-247 F-CDESC (QA follow-up F1; Platform Admin 11 Nov 2026 13:45 "Do it yourself and deliver outcome"): the job course-description-machine never runs past its statement time-out, whatever its earlier steps took.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 11 Nov 2026 19:12 AEDT post-release check of Pilot #1001). security.course_description_machine_run_v1 runs four steps in ONE statement (pg_cron, statement_timeout 2 min): held recheck,
-- subset recovery (ends by 45 s into the statement), settle (40 s from its OWN start) and the consumer read-back (15 s from its OWN start). The steps' boxes add up to about 120 s. With the first-decision backlog of the 11 Nov replay the runs reached
-- 117 s (18:14, 203 decisions) and 120 s (19:04, 294 decisions). A run that passes 120 s is cancelled (query_canceled) and EVERY decision of the run is rolled back; the next run meets the same backlog.
--
-- What this changes: two lines, one in each of two functions (md5-guarded body replacements); nothing else.
--   - security.course_description_machine_settle_v1(): also stops taking another item once 85 s of the job's statement have passed (statement_timestamp()).
--   - security.course_description_machine_consumer_recheck_v1(): also stops starting another read-back once 100 s of the statement have passed.
-- Worst case now about 102 s (settle's last admission about 5 s, the last read-back about 1.5 s) under the 120 s limit; what is left is taken next run (every 10 minutes), as before. The existing 40 s and 15 s boxes stay. Called from an
-- API request (statement limit 8 s) or by hand, the new bounds are never reached first. Technical safety time boxes, marked fixed (G2).
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 19:15 AEDT), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   security.course_description_machine_settle_v1()   4c40d655a7ff674ce184b598056d835f -> 5fa17251727adbb49cb718be889fce54
--   security.course_description_machine_consumer_recheck_v1()   a6138e39a1ba4a3d1b04cc01994d2848 -> f4b6bc3e45866782c5f694046d07131f
-- Replaces: the bodies of security.course_description_machine_settle_v1 and security.course_description_machine_consumer_recheck_v1 are replaced in place (md5-guarded); time boxes counted from each step's own start are joined by a bound on the whole statement
-- Retires: nothing
-- Nothing is dropped or deleted. No setting, job or table changes. Forward recovery (restores both previous bodies byte for byte): supabase/held/cdesc_run_time_budget_forward_recovery.sql

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_settle_v1()'::regprocedure);
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = '5fa17251727adbb49cb718be889fce54' then raise notice 'security.course_description_machine_settle_v1(): already applied'; return; end if;
  if md5(v_src) <> '4c40d655a7ff674ce184b598056d835f' then raise exception 'live security.course_description_machine_settle_v1() differs from the definition this change replaces (body md5 %)', md5(v_src); end if;
  execute $ddl$
CREATE OR REPLACE FUNCTION security.course_description_machine_settle_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_res jsonb; v_ok int := 0; v_no int := 0; v_err int := 0; v_t0 timestamptz := clock_timestamp(); v_stamp text := security.course_description_machine_policy_stamp_v1();
        v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; -- derived: never more in a run than the platform reads in a day
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in select li.id from pipeline.layer4_review_items li
             left join pipeline.course_description_machine_admissions d on d.review_item_id = li.id and d.outcome = 'declined'
            where li.field_code = 'course_description_first_read' and li.entity_type = 'course' and li.status = 'pending'
              and (d.id is null or d.policy_stamp is distinct from v_stamp or d.retry_after <= now())
            order by (d.id is not null), li.created_at, li.id limit v_cap loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 40) -- fixed: stays well inside the 120 s statement time-out of a job; the rest is taken next run
      or clock_timestamp() - statement_timestamp() > make_interval(secs => 85); -- fixed (11 Nov 2026): and never past 85 s into the job's statement, whatever ran before it, so the read-back and the run end well inside 120 s
    begin
      v_res := security.course_description_machine_admit_v1(r.id, 'settle');
      if coalesce((v_res->>'ok')::boolean, false) then v_ok := v_ok + 1; else v_no := v_no + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('on', true, 'admitted', v_ok, 'left_for_a_person', v_no, 'errors', v_err);
end $function$
$ddl$;
end $g$;

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_consumer_recheck_v1()'::regprocedure);
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = 'f4b6bc3e45866782c5f694046d07131f' then raise notice 'security.course_description_machine_consumer_recheck_v1(): already applied'; return; end if;
  if md5(v_src) <> 'a6138e39a1ba4a3d1b04cc01994d2848' then raise exception 'live security.course_description_machine_consumer_recheck_v1() differs from the definition this change replaces (body md5 %)', md5(v_src); end if;
  execute $ddl$
CREATE OR REPLACE FUNCTION security.course_description_machine_consumer_recheck_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_pub jsonb; v_shown text; v_cc text; v_n int := 0; v_ok int := 0; v_t0 timestamptz := clock_timestamp();
        v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; -- derived
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in select a.id, a.after_description, c.stable_key from pipeline.course_description_machine_admissions a join catalogue.courses c on c.id = a.course_id
            where a.outcome = 'admitted' and a.withdrawn_at is null and a.consumer_check is distinct from 'matched'
              and (a.consumer_checked_at is null or a.consumer_checked_at < now() - case when a.consumer_check = 'not_in_feed' then make_interval(days => v_days) else make_interval(hours => 1) end) -- fixed: a lag is read again after an hour
            order by a.consumer_checked_at nulls first limit v_cap loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 15) -- fixed: a follow-up, not the main work of the run
      or clock_timestamp() - statement_timestamp() > make_interval(secs => 100); -- fixed (11 Nov 2026): and never past 100 s into the job's statement (its limit is 120 s)
    begin v_pub := public.website_v2_course(r.stable_key); exception when others then v_pub := null; end;
    v_shown := v_pub->'item'->>'description';
    v_cc := case when v_pub is null then 'error' when v_pub ? 'error' then 'not_in_feed' when v_shown = r.after_description then 'matched' when nullif(btrim(v_shown), '') is null then 'lag' else 'mismatch' end;
    update pipeline.course_description_machine_admissions set consumer_check = v_cc, consumer_checked_at = now() where id = r.id;
    v_n := v_n + 1; if v_cc = 'matched' then v_ok := v_ok + 1; end if;
  end loop;
  return jsonb_build_object('on', true, 'rechecked', v_n, 'matched', v_ok);
end $function$
$ddl$;
end $g$;

-- post-check: both bodies are the ones this change states
do $p$
begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_settle_v1()'::regprocedure)) <> '5fa17251727adbb49cb718be889fce54' then raise exception 'post-check: security.course_description_machine_settle_v1() is not the body this change states'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_consumer_recheck_v1()'::regprocedure)) <> 'f4b6bc3e45866782c5f694046d07131f' then raise exception 'post-check: security.course_description_machine_consumer_recheck_v1() is not the body this change states'; end if;
end $p$;
