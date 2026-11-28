-- CF-247 s1355 (S2-RM-Design; Platform Admin 28 Nov 2026 18:10 AEDT: "move from diagnostic reporting to implementation-ready changes";
-- DR-19 source fix for the s1277 class, under PC-20261128-ONE-COMMAND-RUNTIME-CLOSURE "qualified remedies").
-- Cause (measured 26 to 28 Nov): an AI account refusal (OpenRouter weekly key limit, HTTP 401 unknown key) was recorded by
-- public.svc_enrich_ai_record like any error, so it used one of the item's 3 attempts. During one outage 554 items reached the cap and stopped
-- (s1277 handed them back once). The recovery policy pipeline.work_recovery_policies 'ai_account_refusal' (s1282: defer_recheck,
-- counts_attempt false) said this should not happen, but the worker did not read it.
-- Fix (runtime-first, no new table, job, queue or route): in the record function's error and retry branches, when the reason is an account
-- refusal (security.pim_failure_cause_v1, which reads the configurable recovery_error_classes rows with root_cause_class 'service_limit') and
-- the policy says the attempt does not count, the attempt is refunded and the item waits pim.refusal_defer_minutes before the existing claim
-- takes it again (state 'leased' with a future lease; the s1353 claim reclaims it once the lease expires, as attempts stay under the cap).
-- Every other error keeps today's behaviour exactly. Turning the policy's counts_attempt back on restores the old behaviour without a release
-- (rollback by configuration).
-- G1: no job. G2: pim.refusal_defer_minutes is a setting. G3: not the consumer API (75/48 asserted). Locks and cron asserted. Nothing dropped.
-- Replaces: the error and retry branches of public.svc_enrich_ai_record for account refusals.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pim.refusal_defer_minutes', 'AI account refusal: wait before reading again',
  'When the AI service refuses a call for the account (key limit or unknown key) and the recovery policy ai_account_refusal does not count the attempt, the item waits this long before the worker takes it again.',
  'number', '60'::jsonb, 5, 1440, 'minutes', 1607, 'PIM', 'public.svc_enrich_ai_record (s1355)', 'CF-247 s1355 DR-19 account-refusal source fix')
on conflict (toolset_key, key) do nothing;

do $e$
declare
  v jsonb := security.consumer_api_check_v1(); v_def text; v_n int; r record;
  v_locks bigint := (select count(*) from pipeline.manual_locks); v_jobs bigint := (select count(*) from cron.job where active);
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  for r in select * from (values
    (1, $o1$      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'reason', 300) where id = i.id;$o1$,
        $n1$      if security.pim_failure_cause_v1(r->>'reason') = 'account_refusal'
         and coalesce((select not p.counts_attempt from pipeline.work_recovery_policies p where p.failure_class = 'ai_account_refusal'), false) then
        -- s1355: an account refusal does not use an attempt; the item waits, then the existing claim takes it again
        update pipeline.field_enrich_items set state = 'leased', attempts = greatest(attempts - 1, 0),
               leased_until = now() + make_interval(mins => security.pipeline_num_v1('pim.refusal_defer_minutes', 60)::int),
               reason = left('deferred (account refusal, attempt not counted): ' || coalesce(r->>'reason', ''), 300) where id = i.id;
      else
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'reason', 300) where id = i.id;
      end if;$n1$),
    (2, $o2$      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'error', 300) where id = i.id;$o2$,
        $n2$      if security.pim_failure_cause_v1(r->>'error') = 'account_refusal'
         and coalesce((select not p.counts_attempt from pipeline.work_recovery_policies p where p.failure_class = 'ai_account_refusal'), false) then
        -- s1355: an account refusal does not use an attempt; the item waits, then the existing claim takes it again
        update pipeline.field_enrich_items set state = 'leased', attempts = greatest(attempts - 1, 0),
               leased_until = now() + make_interval(mins => security.pipeline_num_v1('pim.refusal_defer_minutes', 60)::int),
               reason = left('deferred (account refusal, attempt not counted): ' || coalesce(r->>'error', ''), 300) where id = i.id;
      else
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'error', 300) where id = i.id;
      end if;$n2$)
  ) x(n, old, new) order by n loop
    v_def := pg_get_functiondef('public.svc_enrich_ai_record(jsonb)'::regprocedure);
    if position(r.new in v_def) > 0 then raise notice 's1355 edit %: already applied', r.n; continue; end if;
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: fragment % of svc_enrich_ai_record found % times', r.n, v_n; end if;
    execute replace(v_def, r.old, r.new);
  end loop;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> v_locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> v_jobs then raise exception 'post-check: active job count changed'; end if;
end $e$;
