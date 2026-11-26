-- CF-247 s1197 (S1-Build / Release Controller; SS-Programme-Control 26 Nov 2026 15:09 AEDT, P0 item 3: "First applicable live production verification of
-- Holmesglen lean-md-v3").
-- No course entry read runs unattended (the course entry route's scheduled cap is US$0, Platform Admin 25 Nov 2026 18:26 AEDT), so the first live check of
-- the converter is made on the stored Holmesglen page through the existing recall check (job lean-sections-eval, worker mode lean_sections_eval), which
-- runs worker v1.0.47 (lean-md-v3, s1195) on the stored copy and records whether the labelled line is in the lean text. Stored copies only: no AI, no
-- Firecrawl, $0; nothing is admitted and no selection, prompt or reader changes.
-- What this does: seeds one case, run s1197-lean-md-v3-holmesglen-2026-11-26, from the s1152 Holmesglen case (the line lost under lean-md-v2), and
-- switches the existing job lean-sections-eval on. s1198 switches it off once the case is recorded.
-- G1: the job is catalogued already; none created. G2: no new value. G3: no consumer object changed (checked). Locks checked unchanged; active cron at most 140.
-- Replaces: nothing.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if not exists (select 1 from cron.job where jobname = 'lean-sections-eval') then raise exception 'guard: job lean-sections-eval is not there'; end if;
end $g$;
create temp table s1197_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1197_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none

do $seed$
declare v_run constant text := 's1197-lean-md-v3-holmesglen-2026-11-26'; v_from constant text := 's1152-entry-miss-detail-2026-11-25'; v_n int; v_job bigint;
  v_reason constant text := 'SS-Programme-Control 26 Nov 2026 15:09 AEDT: first live check of lean-md-v3 on the stored Holmesglen page (recall check only, $0)';
begin
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
  select v_run, x.field, x.gold_source, x.source_ref, x.course_id, x.evidence_id, x.storage_path, x.gold
    from pipeline.lean_section_eval_cases x
   where x.run_label = v_from and x.state = 'done' and x.miss_detail is not null
     and exists (select 1 from jsonb_array_elements(x.miss_detail) d where (d->>'raw') ~* '&lt;br')
  on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 's1197: % Holmesglen cases, not the one recorded by s1152', v_n; end if;  -- fixed: the check's size
  select jobid into v_job from cron.job where jobname = 'lean-sections-eval';
  perform cron.alter_job(job_id := v_job, active := true);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'seed', 'pipeline.lean_section_eval_cases', jsonb_build_object('reason', v_reason, 'by', 'migration 20261129124500 (CF-247 s1197)', 'run', v_run, 'from_run', v_from, 'cases', v_n,
          'job', 'lean-sections-eval', 'job_active', true, 'switched_off_by', 's1198'), null);
end $seed$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from cron.job j where not exists (select 1 from s1197_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1197_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
