-- CF-247 s1099 (S1-Build; renumbered from s1093 / 20261126001000, which S2-AER's s1093 (Pilot #1585) applied first under the same version, so the
-- earlier file never ran (live history 20261126001000 = cf247_s1093_entry_matrix_requeue_unqualified_route_failures); Platform Admin 24 Nov 2026 23:24 AEDT, AER-FU-11 P0; Admin #1013 and #1015): the entry_matrices route hands the worker its
-- qualified cascade.
-- Found live (rolled back, 24 Nov 2026 23:30 AEDT): pipeline.ai_service_routes 'entry_matrices' has cascade [mistral-small-3.2, qwen3-30b,
-- gpt-4.1-mini], all three qualified (provisional, Platform Admin 24 Nov 2026 15:15) in pipeline.ai_route_qualifications, but migration_state
-- 'routed_single'. security.ai_route_v1 (md5 e06997a2...) gives one model unless migration_state is 'routed' ("one model only unless the worker
-- executes the cascade for this service"), so svc_entry_matrix_next leased runs with models = [Mistral] and worker v1.0.39 (s1085), which now runs
-- the cascade, had nothing to fall through to: in four hours 8 answered and 52 failed Mistral calls, 0 Qwen3 30B or GPT-4.1 mini calls.
-- What changes (live on deploy):
--   1. entry_matrices migration_state routed_single -> routed, the service's own existing route transition, logged with the approval. The worker
--      executes the cascade for this service since v1.0.39. The resolver still lists only models that are allowed in the catalogue AND qualified for
--      this service, so no other model can be sent; every hold (switch, balance, floor, ceiling, the service's US$20 daily cap) is unchanged.
--   2. A rolled-back regression inside this migration proves: three models in order; a model marked unqualified is left out; no other
--      route changes.
--   3. Failed entry_matrices runs since s1085 (time-out or empty answer) are queued again, only where no other run of the same source is queued or
--      leased, leased 10 minutes so the route change is live first.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged. No spending limit changed.
-- Replaces: the single-model entry_matrices route.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1099_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1099_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1099_routes on commit drop as select service_code, migration_state, cascade, enabled, daily_usd_cap from pipeline.ai_service_routes where service_code <> 'entry_matrices';

do $route$
declare v_before text; v_reason text := 'AER-FU-11 (Platform Admin 24 Nov 2026 23:24 AEDT): worker v1.0.39 executes the entry_matrices cascade (s1085); hand it the qualified cascade so a timed-out slice falls through';
begin
  select migration_state into v_before from pipeline.ai_service_routes where service_code = 'entry_matrices' for update;
  if v_before is distinct from 'routed_single' then raise exception 's1099: entry_matrices is %, not routed_single; nothing changed', v_before; end if;
  if (select count(*) from pipeline.ai_route_qualifications q where q.service_code = 'entry_matrices' and q.status = 'qualified'
        and q.model_code = any (select jsonb_array_elements_text(to_jsonb(r.cascade)) from pipeline.ai_service_routes r where r.service_code = 'entry_matrices')) < 2 then
    raise exception 's1099: fewer than two cascade models are qualified for entry_matrices; nothing changed';
  end if;
  update pipeline.ai_service_routes set migration_state = 'routed', reason = v_reason, changed_at = now(), changed_by = null where service_code = 'entry_matrices';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_routes', 'transition', 'entry_matrices', jsonb_build_object('before', v_before, 'after', 'routed', 'reason', v_reason,
          'approved_by', 'Platform Admin (chat, 24 Nov 2026 23:24 AEDT, AER-FU-11)', 'via', 'CF-247 s1099 migration'), null);
end $route$;

-- regression, always rolled back: the cascade is handed out in order, and only qualified models are
do $regression$
begin
  begin
    declare v jsonb; v_codes text[];
    begin
      v := security.ai_route_v1('entry_matrices');
      v_codes := array(select x->>'code' from jsonb_array_elements(v->'models') x);
      if v->>'migration_state' <> 'routed' then raise exception 'route not routed: %', v->>'migration_state'; end if;
      if cardinality(v_codes) < 2 or v_codes[1] <> 'mistral-small-3.2' then raise exception 'cascade not handed out in order: %', v_codes; end if;
      if exists (select 1 from unnest(v_codes) c where not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'entry_matrices' and q.model_code = c and q.status = 'qualified')) then
        raise exception 'an unqualified model is handed out: %', v_codes;
      end if;
      update pipeline.ai_route_qualifications set status = 'unqualified' where service_code = 'entry_matrices' and model_code = 'qwen3-30b';
      v := security.ai_route_v1('entry_matrices');
      if exists (select 1 from jsonb_array_elements(v->'models') x where x->>'code' = 'qwen3-30b') then raise exception 'an unqualified model is still handed out'; end if;
      raise exception 'S1099_REGRESSION_OK';
    end;
  exception when others then
    if sqlerrm <> 'S1099_REGRESSION_OK' then raise exception 's1099 regression failed: %', sqlerrm; end if;
  end;
end $regression$;

-- failed runs since s1085, once each, only where nothing of the same source is already queued or leased
do $rq$
declare v_n int;
begin
  with t as (
    select distinct on (r.source_id) r.id from pipeline.entry_matrix_runs r
     where r.state = 'failed' and r.updated_at > '2026-11-24T11:51:43Z'
       and r.error ~* 'timed out|time budget|without a reply|no answer|unreadable'
       and not exists (select 1 from pipeline.entry_matrix_runs o where o.source_id = r.source_id and o.id <> r.id
                         and (o.state in ('queued', 'running') or coalesce(o.leased_until, '-infinity') > now()))
     order by r.source_id, r.updated_at desc)
  update pipeline.entry_matrix_runs r set state = 'queued', attempts = 0, leased_until = now() + interval '10 minutes', updated_at = now(),  -- fixed: wait for the route change
         error = 'requeued by CF-247 s1099 (AER-FU-11 cascade): ' || left(coalesce(r.error, ''), 300)
    from t where r.id = t.id;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'requeue', 'entry_matrix_runs', jsonb_build_object('runs', v_n, 'reason', 'AER-FU-11: failed since s1085, read again through the cascade',
          'approved_by', 'Platform Admin (chat, 24 Nov 2026 23:24 AEDT)', 'via', 'CF-247 s1099 migration'), null);
  raise notice 's1099: % run(s) queued again', v_n;
end $rq$;

do $c$
declare v_api jsonb;
begin
  if (select migration_state from pipeline.ai_service_routes where service_code = 'entry_matrices') <> 'routed' then raise exception 'post-check: entry_matrices is not routed'; end if;
  if exists (select 1 from pipeline.ai_service_routes r join s1099_routes o using (service_code)
              where r.migration_state is distinct from o.migration_state or r.cascade is distinct from o.cascade or r.enabled is distinct from o.enabled or r.daily_usd_cap is distinct from o.daily_usd_cap) then
    raise exception 'post-check: another route changed';
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1099_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1099_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
