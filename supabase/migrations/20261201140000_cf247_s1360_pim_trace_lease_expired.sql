-- CF-247 s1360 (S2-RM-Design; PC-20261128-CONTINUOUS-BUILD-EXECUTE: "trace terminal/expired states with existing remedy registry"; main-green fix).
-- Context: the account-refusal fix shipped as s1355 (Pilot #1766, S1-Build integrating S2-RM-Design's branch, migration 20261201120000).
-- Pilot #1765 then reused version 20261201120000 for a longer file (s1356) that added the trace edits below, and Deploy on merge
-- correctly refused it as a changed applied migration. This change removes that duplicate file and issues the trace edits as their own migration.
-- What it does: security.pim_record_trace_v1 names a deferred refusal (s1355) as in progress, attempt not counted, until when. It names an expired
-- lease at the attempt cap as an operational failure, cause and recovery cause lease_expired, with the registry remedies that treat
-- lease_orphaned; the next claim settles that lease (s1353). security.pim_failure_cause_v1 reads s1353's settled reason ("lease expired at
-- the attempt cap") as lease_expired, not as the account refusal its earlier reason quoted (27 items on 28 Nov).
-- Read-only diagnostics: no table, job, setting, route or data change. G3: not the consumer API (75/48 asserted). Locks and cron asserted.
-- Replaces: the in-progress and recovery-cause branches of security.pim_record_trace_v1; the first branch of security.pim_failure_cause_v1.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

do $t$
declare v_def text; v_n int; r record; v jsonb;
  v_locks bigint := (select count(*) from pipeline.manual_locks); v_jobs bigint := (select count(*) from cron.job where active);
begin
  for r in select * from (values
    ('security.pim_record_trace_v1(uuid,text,boolean)', 1,
     $o1$    elsif v_last.state in ('waiting', 'ai', 'leased') or v_last.leased_until > now() then
      v_class := 'in_progress'; v_detail := 'attempt ' || v_last.state || coalesce(', leased until ' || v_last.leased_until::text, '');$o1$,
     $n1$    elsif v_last.state = 'leased' and v_last.leased_until <= now() and coalesce(v_last.attempts, 0) >= v_attempts then
      -- s1360: an expired lease at the attempt cap is terminal; the next claim settles it as failed (s1353); registry remedies named
      v_class := 'operational_failure'; v_cause := 'lease_expired';
      v_detail := 'lease expired at the attempt cap; settled as failed by the next claim' || coalesce('; registry remedy ' || (select string_agg(m.code, ', ' order by m.code) from pipeline.ops_remedies m where m.active and 'lease_orphaned' = any(m.treats)), '');
    elsif v_last.state in ('waiting', 'ai', 'leased') or v_last.leased_until > now() then
      v_class := 'in_progress';
      v_detail := case when v_last.reason like 'deferred (account refusal%' and v_last.leased_until > now()
                       then 'deferred after an AI account refusal until ' || v_last.leased_until::text || '; attempt not counted (recovery policy ai_account_refusal)'
                       else 'attempt ' || v_last.state || coalesce(', leased until ' || v_last.leased_until::text, '') end;$n1$),
    ('security.pim_record_trace_v1(uuid,text,boolean)', 2,
     $o2$      when v_last.id is not null and coalesce(v_last.attempts, 0) >= v_attempts and v_last.state in ('failed', 'skipped') then 'repeated_ineffective_extraction'$o2$,
     $n2$      when v_cause = 'lease_expired' then 'lease_expired'  -- s1360: the worker did not return before the lease ran out; not an extraction result
      when v_last.id is not null and coalesce(v_last.attempts, 0) >= v_attempts and v_last.state in ('failed', 'skipped') then 'repeated_ineffective_extraction'$n2$),
    ('security.pim_failure_cause_v1(text)', 3,
     $o3$  select case when coalesce(p_reason, '') = '' then null$o3$,
     $n3$  select case when coalesce(p_reason, '') = '' then null
              when p_reason ilike 'lease expired at the attempt cap%' then 'lease_expired'  -- s1360: s1353's settled reason, written by the claim$n3$)
  ) x(fn, n, old, new) order by n loop
    v_def := pg_get_functiondef(r.fn::regprocedure);
    if position(r.new in v_def) > 0 then raise notice 's1360 trace edit %: already applied', r.n; continue; end if;
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: fragment % of % found % times', r.n, r.fn, v_n; end if;
    execute replace(v_def, r.old, r.new);
  end loop;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> v_locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> v_jobs then raise exception 'post-check: active job count changed'; end if;
end $t$;
