-- CF-247 s1198 (S1-Build / Release Controller): the lean-md-v3 live check (s1197) has recorded its one case, so the existing job lean-sections-eval is
-- switched off again, as before s1197. Nothing else changes.
-- G1: no job created. G2: no new value. G3: no consumer object changed (checked). Locks checked unchanged; active cron at most 140.
-- Replaces: s1197's job switch.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
begin
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label = 's1197-lean-md-v3-holmesglen-2026-11-26' and state = 'pending') then
    raise exception 'guard: the s1197 case is not recorded yet';
  end if;
  if not exists (select 1 from pipeline.lean_section_eval_cases where run_label = 's1197-lean-md-v3-holmesglen-2026-11-26') then raise exception 'guard: s1197 is not applied'; end if;
end $g$;
create temp table s1198_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1198_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none

do $off$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'lean-sections-eval';
  perform cron.alter_job(job_id := v_job, active := false);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'job_off', 'lean-sections-eval', jsonb_build_object('reason', 'The s1197 lean-md-v3 live check is recorded; the recall job is off again', 'by', 'migration 20261129131500 (CF-247 s1198)',
          'result', (select jsonb_build_object('state', state, 'worker', worker, 'converter', converter, 'gold_in_page', gold_in_page, 'gold_in_lean', gold_in_lean)
                       from pipeline.lean_section_eval_cases where run_label = 's1197-lean-md-v3-holmesglen-2026-11-26' limit 1)), null);
end $off$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from cron.job j where not exists (select 1 from s1198_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select active from cron.job where jobname = 'lean-sections-eval') then raise exception 'post-check: lean-sections-eval is still on'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1198_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
