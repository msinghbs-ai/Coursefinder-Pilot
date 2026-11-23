-- CF-247 s1013 (S1-Build; Platform Admin 23 Nov 2026 22:10 AEDT, Deployed UAT recovery): four covering indexes for two admin reads that
-- time out at the signed-in statement limit (8 s) and answer HTTP 500, which fails the deployed acceptance run. Root cause read from the
-- production logs and timed against live data in rolled-back runs (23 Nov 2026 22:15 to 22:30 AEDT); no function is changed.
-- 1. public.admin_toolsets_read (Services & limits, Models & services; live md5 df2380c6): 25 timeouts in 24 hours, before and after s1011.
--    Its slow parts were the 14-day AI spend reads and the plan status:
--      pipeline.scholarship_ai_extractions (at > now() - 14 days; 39,309 of 74,684 wide rows read from the heap)        2.0 s
--      pipeline.coverage_ai_match (created_at > now() - 14 days, cost > 0; no created_at index, 125 MB scanned)           1.8 s
--      security.toolset_plan_status -> pipeline.coverage_vendor_usage by acquisition_provider_id (no index, 251,678 rows)  1.2 s
--    With the three indexes below: 133 ms, 14 ms and 18 ms; the whole function 163 ms.
-- 2. public.admin_course_audit (Course detail › evidence overlay; live md5 f22497a1): reads a course's evidence by metadata->>'course_id',
--    which no index serves (236,106 rows, 497 MB): over 15 s for RMIT DP020. With the partial expression index below: 2 ms; the whole
--    function 173 ms. The index is 10 MB and built in 0.8 s.
-- Each index is built inside a short lock retry so a busy writer never queues behind this change. Nothing else changes.
-- G1: no job. G2: no operational value (the lock waits are fixed technical values). G3: no consumer object changed (checked before and after).
-- Manual locks and active cron jobs checked unchanged. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1013_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1013_cron on commit drop as select count(*) n from cron.job where active;

do $i$
declare v_sql text; v_try int;
begin
  foreach v_sql in array array[
    'create index if not exists scholarship_ai_extractions_at_cost_idx on pipeline.scholarship_ai_extractions (at) include (cost_usd)',
    'create index if not exists coverage_ai_match_created_cost_idx on pipeline.coverage_ai_match (created_at) include (cost_usd, decided_at) where coalesce(cost_usd, 0) > 0',
    'create index if not exists coverage_vendor_usage_acq_provider_at_idx on pipeline.coverage_vendor_usage (acquisition_provider_id, at) include (units)',
    'create index if not exists evidence_artifacts_course_captured_idx on pipeline.evidence_artifacts ((metadata->>''course_id''), captured_at desc) where (metadata->>''course_id'') is not null'] loop
    v_try := 0;
    loop
      begin
        perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
        execute v_sql;
        exit;
      exception when lock_not_available then
        v_try := v_try + 1;
        if v_try >= 5 then raise exception 'could not take the lock for: %', v_sql; end if;  -- fixed: tries before giving up
        perform pg_sleep(2);  -- fixed: pause between tries
      end;
    end loop;
  end loop;
end $i$;

analyze pipeline.scholarship_ai_extractions;
analyze pipeline.coverage_ai_match;
analyze pipeline.coverage_vendor_usage;
analyze pipeline.evidence_artifacts;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1013_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1013_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if to_regclass('pipeline.scholarship_ai_extractions_at_cost_idx') is null or to_regclass('pipeline.coverage_ai_match_created_cost_idx') is null
     or to_regclass('pipeline.coverage_vendor_usage_acq_provider_at_idx') is null or to_regclass('pipeline.evidence_artifacts_course_captured_idx') is null then
    raise exception 'post-check: an index is missing';
  end if;
end $post$;
