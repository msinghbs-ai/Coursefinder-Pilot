-- CF-247 IQ-00053 (P1, reopened 8 Nov 2026 06:51 UTC; Platform Admin follow-up 8 Nov 2026 18:27 Melbourne, item 1): enrich_ai answers that fail with
-- HTTP 546 WORKER_RESOURCE_LIMIT, and the items those calls took are never read again.
-- Guards: G2 (no operational value in code: the one setting changed is in pipeline.platform_toolset_settings with a reason and an audit event; the one
--   number left in code is marked "fixed:"), G3 (no consumer API object is touched), Decision 260 (housekeeping), "a passing job is not a processed item"
--   (the job's own progress now shows how the worker's answers went).
-- Why (production, read-only, 8 Nov 2026 18:43-19:20 Melbourne; the evidence is request-level, not the issue's headline):
--   1 The platform's own ledger (pipeline.integration_yield_buckets, key coverage-sweep:enrich_ai) holds 189 enrich_ai calls in total since 5 Nov, 24 of them
--     failed, in two bursts only: 7 Nov 06:00 UTC hour 11 of 63, and 8 Nov 06:25 UTC 13 of 41. Every other hour is clean. The issue's headline ("189 of 360
--     failed") is the text recorded when the issue was first opened on 2-3 Nov; it is not refreshed when the issue reopens, so it is not today's rate.
--   2 Edge logs (function_edge_logs, 8 Nov 06:25-06:30 UTC): all 13 status-546 answers are in one five-minute bucket (86 coverage-sweep requests), the
--     function log shows "CPU Time exceeded" at 06:25:50 and six new workers booted within 30 ms at 06:25:42 and 06:26:06. Before and after, the same function
--     answered 40 to 50 requests per five minutes with no error. The failures come from a burst of many AI calls started in the same second.
--   3 That burst is the standing enrich task starting (task created 06:23 UTC): security.enrich_ai_fire_v1 sends up to enrich.ai_calls_at_once calls in one
--     tick; the setting is 20 (Platform Admin load test 23 Oct) with 10 pages each in parallel.
--   4 The 13 failed calls had leased 390 items (13 x 30 = enrich.ai_items_per_call) at 06:25:44-46. Their leases ended at 06:29. 74 minutes later all 390 are
--     still state "leased" with attempts 1 and the task is still "running", because security.enrich_fields_slice_v1 asks the worker again ONLY when an item of
--     the task is in state "ai": a "leased" item whose lease has run out is picked up by public.svc_enrich_ai_next (state ai OR an expired lease, attempts < 3) but
--     nothing fires the call that would pick it up. A failed call therefore strands its items until a person restarts the task.
-- What:
--   1 security.enrich_fields_slice_v1 (md5-guarded edit): it now also asks the worker again when the task holds an item with an expired lease and fewer than 3 tries
--     (the same rule svc_enrich_ai_next uses; an item that has used its 3 tries is still settled "failed" by the first statement of the function).
--   2 security.enrich_worker_health_v1 (new, read-only): the enrich_ai calls of the last integration.hidden_error_window_minutes minutes (existing setting)
--     counted as answered ok, answered with an error, in flight, or with no recorded answer, by the same test the integration yield check applies. The task's
--     progress (admin_jobs.progress.worker) carries it, so a task that is "running" shows how its worker calls went and is not read as success because the
--     scheduler's call succeeded.
--   3 enrich.ai_calls_at_once 20 -> 8 (existing setting, range 1 to 40; the Platform Admin's own load test passed 10 calls at once with 6 pages): the proven cause is
--     the number of calls started together. One variable is changed so the effect can be attributed; pages at once (10) and items per call (30) are not touched.
-- Production acceptance (not this migration's claim): the 390 stranded items are asked again by the next tick at 8 calls at once; at least two unattended
--   cycles of the standing task run with no 546/503 answer, items reach filled / review / skipped, and the task's progress.worker shows the answers.
-- Rollback: set enrich.ai_calls_at_once back to 20 (Settings > Pipeline settings, with a reason). The function edit is reversed by re-applying the previous
--   definition (md5 c385d9c3a9fd33614f189773e45683f3); the new function is read-only and unused elsewhere.
-- Replaces: security.enrich_fields_slice_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing is dropped or deleted. No job is added.

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

-- 1 the read-only worker read-out (created first: the edited function calls it) --------------------------------------------------------------------
create or replace function security.enrich_worker_health_v1() returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
           'window_minutes', security.pipeline_num_v1('integration.hidden_error_window_minutes', 120)::int,
           'calls', count(*),
           'ok', count(*) filter (where r.id is not null and not coalesce(f.failed, false)),
           'failed', count(*) filter (where r.id is not null and coalesce(f.failed, false)),
           'in_flight', count(*) filter (where r.id is null and l.created_at >= now() - interval '3 minutes'),   -- fixed: the open-call window security.enrich_ai_fire_v1 uses
           'no_answer_recorded', count(*) filter (where r.id is null and l.created_at < now() - interval '3 minutes'))
    from pipeline.edge_request_log l
    left join net._http_response r on r.id = l.request_id
    left join lateral (select (coalesce(r.status_code, 0) >= 400 or r.timed_out is true or r.error_msg is not null
                               or (coalesce(r.status_code, 0) < 300 and left(r.content, 2000) ~ '"ok"\s*:\s*false')) failed) f on true   -- the integration yield check's test
   where l.function_name = 'coverage-sweep' and l.mode = 'enrich_ai'
     and l.created_at > now() - make_interval(mins => security.pipeline_num_v1('integration.hidden_error_window_minutes', 120)::int) $f$;
comment on function security.enrich_worker_health_v1() is 'CF-247 IQ-00053: the enrich_ai worker calls of the last integration.hidden_error_window_minutes minutes: ok, failed, in flight, no recorded answer. Read-only; shown in the Enrich task progress.';
revoke all on function security.enrich_worker_health_v1() from public, anon, authenticated;

-- 2 the md5-guarded edit of the slice -------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', 'c385d9c3a9fd33614f189773e45683f3', 'd68665cb163bb99f7cca088d39cf595b', array[
  [$o$if exists (select 1 from pipeline.field_enrich_items where job_id = p_id and state = 'ai') then perform security.enrich_ai_fire_v1(); end if;$o$,
   $n$if exists (select 1 from pipeline.field_enrich_items where job_id = p_id and (state = 'ai' or (state = 'leased' and leased_until < now() and attempts < 3))) then perform security.enrich_ai_fire_v1(); end if;  -- CF-247 IQ-00053: an expired lease is fired again$n$],
  [$o$'phase', case when v_left = 0 then 'finishing'$o$,
   $n$'worker', security.enrich_worker_health_v1(), 'phase', case when v_left = 0 then 'finishing'$n$]], array[1, 1]);

-- 3 the one setting (existing, governed, with a reason and an audit event) --------------------------------------------------------------------------
do $apply$
declare v_before jsonb; v_n int;
begin
  select to_jsonb(s) - 'help' into v_before from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'enrich.ai_calls_at_once';
  if v_before is null then return; end if;                                   -- a fixture without the setting: nothing to change
  if v_before->'value' = to_jsonb(8) then return; end if;                    -- already applied
  if v_before->'value' <> to_jsonb(20) then
    raise exception 'enrich.ai_calls_at_once is %, not the 20 this change was written against; nothing changed', v_before->'value';
  end if;
  update pipeline.platform_toolset_settings
     set value = to_jsonb(8), updated_at = now(),
         reason = 'CF-247 IQ-00053 (Platform Admin follow-up 8 Nov 2026 18:27, item 1): 13 AI calls started in the same second returned 546 WORKER_RESOURCE_LIMIT at 06:25 UTC; 8 at once (the 23 Oct load test passed 10). Roll back to 20 here if it does not help'
   where toolset_key = 'pipeline' and key = 'enrich.ai_calls_at_once' and value = to_jsonb(20);
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'updated %, expected 1', v_n; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline/enrich.ai_calls_at_once',
          jsonb_build_object('from', 20, 'to', 8, 'actor', 'Integration Controller (Claude)', 'issue', 'IQ-00053', 'migration', '20261108190000',
                             'reason', 'calls started together returned 546 (CPU time exceeded, 6 workers booted within 30 ms); one variable changed; rollback is a setting change'), null);
end $apply$;
