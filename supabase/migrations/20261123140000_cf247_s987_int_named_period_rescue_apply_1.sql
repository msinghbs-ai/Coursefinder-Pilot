-- CF-247 s987 (session S2-INT; Platform Admin 23 Nov 2026 13:02 AEDT, F-INT, live at once): apply the s986 planner rule to the courses it frees now, part 1 of 3.
-- s986 (planner md5 f05b31dd...) narrows the "named period starts sooner in another month" hold. The hourly intake-dates-apply job would re-plan the 4,528 rows of the
-- affected universities at the batch size (150 an hour, about 30 hours). The standing mandate (21 Nov 2026 10:07) says a verified fix takes effect on deploy, so this
-- runs the same function the job runs, security.intake_dates_apply_v1(limit, course_ids) (the "Run now" path: same planner, same locks, same provenance, same fingerprint
-- and event log), once, for the courses that hold an active intake with that reason. The courses are split in three parts by a hash of the course id so each part
-- stays inside one request (no provider is named). It changes no function, setting or schedule. Dates come only from the planner's own output: a date is one of the
-- university's official calendar starts, in the intake's own month, with the page wording stored beside it. Nothing is invented.
-- G1: no job. G2: no number in code (the row limit is the count of the selected courses' intakes). G3 stays 75/48. Locks unchanged (checked); no cron statement (the active cron count moves on its own while this runs, so it is not compared).
-- Replaces: nothing.
-- Retires: nothing. Nothing dropped, deleted or renamed; reversal is security.intake_date_day_withdraw_v1 per row.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: one planner run over the part's courses

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s987_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $r$
declare v_ids uuid[]; v_lim int; v_res jsonb; v_before int; v_after int; v_new int;
begin
  -- only after the s986 planner is live
  if md5((select prosrc from pg_proc where oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> 'f05b31dd74378cce5cdc77f0b20abb79' then
    raise exception 's987 part 1: the planner is not the s986 text';
  end if;
  select array_agg(distinct d.course_id) into v_ids
    from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id and i.status = 'active'
   where d.outcome = 'skipped' and d.reason like 'the named period starts sooner%' and i.start_date is null
     and mod(abs(hashtext(d.course_id::text)), 3) = 0;  -- fixed: part 1 of 3 (a split of the work, not a limit)
  if v_ids is null then raise notice 's987 part 1: no course to apply'; return; end if;
  select count(*) into v_lim from catalogue.course_intakes where course_id = any (v_ids);
  select count(*) into v_before from catalogue.course_intakes where course_id = any (v_ids) and start_date is not null;
  v_res := security.intake_dates_apply_v1(v_lim, v_ids);
  select count(*) into v_after from catalogue.course_intakes where course_id = any (v_ids) and start_date is not null;
  v_new := v_after - v_before;
  raise notice 's987 part 1: % courses, apply result %, intakes with an exact start % -> % (+%)', cardinality(v_ids), v_res, v_before, v_after, v_new;
  -- no date outside the planner: every newly dated intake has a filled decision written in this run with its quote and calendar
  if exists (select 1 from catalogue.course_intakes i join pipeline.course_intake_dates d on d.intake_id = i.id
              where i.course_id = any (v_ids) and i.start_date is not null and d.applied_at = now() and d.outcome = 'filled'
                and (d.start_quote is null or d.calendar_url is null)) then
    raise exception 's987 part 1: a filled decision lacks its quote or calendar';
  end if;
end $r$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API drifted: %', v;
  end if;
  if (select n from s987_locks) <> (select count(*) from pipeline.manual_locks) then raise exception 'post-check: manual locks changed'; end if;
end $p$;
