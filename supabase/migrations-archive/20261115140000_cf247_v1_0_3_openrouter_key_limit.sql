-- CF-247 worker v1.0.3: an OpenRouter key limit refusal is an account stop (Platform Admin 15 Nov 2026 12:53, "go ahead with worker v1.0.3").
-- Found 15 Nov 2026: from 12 Nov 11:17 UTC the OpenRouter key's own weekly limit (US$50, then US$70) refused every AI call with 403 "Key limit
-- exceeded". The worker recorded each refusal as a failure of the item, so 8,775 queued items (8,235 courses) were closed as failed or skipped,
-- the healthy model was put in cooldown, and neither the spend guard nor Health knew the key had a limit (they read only the account balance).
--   1. pipeline.openrouter_key_observations: the key's own limit and the budget over it that blocks first, read every run of job openrouter-balance
--      (worker GET /api/v1/key) and written at once when the worker meets a refusal (public.svc_openrouter_key_record_v1). Only the limit figures
--      are kept: never the key, its label or the account ids.
--   2. security.openrouter_key_room_v1: what the key has left (the reading less the spend recorded since), whether that is at or below the credit
--      floor (openrouter.credit_floor_usd, the same floor as the balance), and the daily ceiling over the key's period.
--   3. security.ai_route_v1 (md5-guarded edit): a key with no room holds every AI service (held_kind key_limit), on-demand included: it is the
--      account's own limit, like the credit floor (operating model 3.3.2). The route also reports the key and room_usd, the lower of the daily
--      ceiling still free and the key's room. security.ai_use_refusal_v1 (md5-guarded edit) refuses the same way, whatever the OpenRouter mode.
--   4. public.svc_ai_key_limit_release_v1: the worker gives the items a refusal stopped back to their queue as waiting, their try given back and
--      the cost of any earlier attempt kept (course fields, entry matrices, fee reader, central pages, scholarship eligibility, course matching).
--   5. public.svc_ai_model_answered_v1 (md5-guarded edit): an attempt the key refused (failure kind key_limit) is kept in the new
--      pipeline.ai_key_limit_attempts, not in pipeline.ai_invocations or pipeline.ai_attempt_times, so job ai-model-health never counts it
--      against the model.
--   6. security.platform_health_check_v1 (md5-guarded edit): Health raises budgets:openrouter_key, critical while the key has no room, a warning
--      when the key's limit is lower than the daily ceiling over its period (weekly: 7 x budgets.ai_daily_ceiling_usd) or it has not been read.
-- Lock rule (#1149): no ALTER of any existing table; nothing written to pipeline.platform_toolset_settings; no route, model, ceiling, switch or
-- mode changes (post-check). The 8,775 closed items are NOT re-queued here: that is an on-demand request the Platform Admin approves first.
-- G1: no new job (job openrouter-balance does the reading). G2: no new value: the floor is openrouter.credit_floor_usd, the reading's age is
-- openrouter.balance_max_age_minutes, the ceiling is budgets.ai_daily_ceiling_usd; only the days of a period are fixed. G3: no consumer API
-- object is read or changed.
-- Replaces: security.ai_route_v1(text), security.ai_use_refusal_v1(text), public.svc_ai_model_answered_v1(text,text,text,jsonb,text) and
--   security.platform_health_check_v1(boolean) (same names and signatures; md5-guarded edits of the live text).
-- Retires: nothing.

set local lock_timeout = '3s';

select set_config('cf247.v103_before', jsonb_build_object(
  'drain', security.pipeline_num_v1('layer4.drain_on', 0), 'md', security.pipeline_num_v1('reading.markdown_input', 0),
  'reorder', security.pipeline_num_v1('health.ai_reorder_on', 0), 'shadow', security.pipeline_num_v1('aer.v2_shadow_on', 0),
  'ceiling', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
  'openrouter', (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'),
  'routes', (select jsonb_agg(jsonb_build_array(r.service_code, r.enabled, r.cascade, r.daily_usd_cap, r.migration_state) order by r.service_code) from pipeline.ai_service_routes r))::text, false);

-- 1. New tables
create table if not exists pipeline.openrouter_key_observations (
  id bigserial primary key,
  observed_at timestamptz not null default now(),
  source text not null check (source in ('poll', 'refusal')),
  http integer,
  remaining_usd numeric,
  limit_usd numeric,
  limit_reset text,
  scope text,
  usage_daily numeric,
  usage_weekly numeric,
  usage_monthly numeric,
  payload jsonb not null default '{}'::jsonb
);
create index if not exists openrouter_key_observations_at_idx on pipeline.openrouter_key_observations (observed_at desc);
comment on table pipeline.openrouter_key_observations is 'CF-247 worker v1.0.3: readings of the OpenRouter key''s own limit and of the budget over it that blocks requests first (GET /api/v1/key, every run of job openrouter-balance; source poll), and refusals the worker met (403/402 "Key limit exceeded"; source refusal, remaining 0). remaining_usd is the lower of the key''s limit_remaining and the blocking budget''s remaining_usd (null: no limit). Read by security.openrouter_key_room_v1 for security.ai_route_v1, security.ai_use_refusal_v1 and Health. Never holds the key, its label or account ids.';
alter table pipeline.openrouter_key_observations enable row level security;

create table if not exists pipeline.ai_key_limit_attempts (
  id bigserial primary key,
  at timestamptz not null default now(),
  service_code text,
  model text not null,
  attempt_no integer not null default 1,
  source text,
  source_id text,
  worker text
);
create index if not exists ai_key_limit_attempts_at_idx on pipeline.ai_key_limit_attempts (at);
comment on table pipeline.ai_key_limit_attempts is 'CF-247 worker v1.0.3: AI call attempts the OpenRouter key refused for its own limit (failure kind key_limit), kept apart from pipeline.ai_invocations so job ai-model-health never counts an account stop against a model. Written by public.svc_ai_model_answered_v1.';
alter table pipeline.ai_key_limit_attempts enable row level security;

-- 2. Recording a reading or a refusal (worker)
create or replace function public.svc_openrouter_key_record_v1(p_source text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare eb jsonb := case when jsonb_typeof(p_payload->'effective_budget') = 'object' then p_payload->'effective_budget' end;
        v_key numeric; v_eb numeric; v_rem numeric; v_lim numeric; v_reset text; v_scope text; v_id bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_source not in ('poll', 'refusal') then raise exception 'source must be poll or refusal'; end if;
  v_key := nullif(p_payload->>'limit_remaining', '')::numeric;
  v_eb := nullif(eb->>'remaining_usd', '')::numeric;
  v_rem := least(v_key, v_eb);  -- least() leaves out a null: no limit on that layer
  if v_eb is not null and (v_key is null or v_eb <= v_key) then  -- the budget blocks first
    v_lim := nullif(eb->>'limit_usd', '')::numeric; v_reset := nullif(eb->>'reset_interval', ''); v_scope := coalesce(nullif(eb->>'scope', ''), 'budget');
  else
    v_lim := coalesce(nullif(p_payload->>'limit', '')::numeric, nullif(p_payload->>'limit_usd', '')::numeric);
    v_reset := coalesce(nullif(p_payload->>'limit_reset', ''), (regexp_match(coalesce(p_payload->>'message', ''), '\((daily|weekly|monthly) limit\)', 'i'))[1]);
    v_scope := 'key_limit';
  end if;
  if p_source = 'refusal' then v_rem := coalesce(v_rem, 0); end if;  -- a refusal is no room, whatever the figures say
  insert into pipeline.openrouter_key_observations (source, http, remaining_usd, limit_usd, limit_reset, scope, usage_daily, usage_weekly, usage_monthly, payload)
  values (p_source, nullif(p_payload->>'http', '')::int, v_rem, v_lim, lower(v_reset), v_scope, nullif(p_payload->>'usage_daily', '')::numeric,
          nullif(p_payload->>'usage_weekly', '')::numeric, nullif(p_payload->>'usage_monthly', '')::numeric,
          p_payload - 'label' - 'creator_user_id' - 'organization_id' - 'workspace_id')
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'source', p_source, 'remaining_usd', v_rem, 'limit_usd', v_lim, 'limit_reset', lower(v_reset), 'scope', v_scope);
end $function$;
revoke all on function public.svc_openrouter_key_record_v1(text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_openrouter_key_record_v1(text, jsonb) to service_role;

-- 3. What the key has left
create or replace function security.openrouter_key_room_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare k pipeline.openrouter_key_observations%rowtype; v_since numeric := 0; v_est numeric; v_days int; v_ceiling numeric;
        v_age int := coalesce((security.toolset_setting('openrouter', 'balance_max_age_minutes'))::text::numeric, 90)::int;
        v_floor numeric := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
begin
  v_ceiling := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14);
  -- the latest reading or refusal younger than openrouter.balance_max_age_minutes; an older one is not used (a refusal stops the call that meets it)
  select * into k from pipeline.openrouter_key_observations o where o.observed_at > now() - make_interval(mins => v_age) order by o.observed_at desc, o.id desc limit 1;
  if k.id is null then
    return jsonb_build_object('reading', false, 'held', false, 'max_age_minutes', v_age, 'floor_usd', v_floor, 'ceiling_usd', v_ceiling,
                              'last_at', (select max(o.observed_at) from pipeline.openrouter_key_observations o));
  end if;
  if k.remaining_usd is not null then
    select coalesce(sum(l.cost_usd), 0) into v_since from pipeline.ai_spend_ledger l where l.at > k.observed_at and l.source <> 'opening';
    v_est := k.remaining_usd - v_since;
  end if;
  v_days := case k.limit_reset when 'daily' then 1 when 'weekly' then 7  -- fixed: days in the key's limit period
                 when 'monthly' then extract(day from date_trunc('month', now()) + interval '1 month' - interval '1 day')::int end;  -- fixed: days in this month
  return jsonb_build_object('reading', true, 'source', k.source, 'observed_at', k.observed_at, 'scope', k.scope, 'limit_usd', k.limit_usd, 'limit_reset', k.limit_reset,
    'remaining_usd', k.remaining_usd, 'spent_since_usd', round(v_since, 4), 'estimated_usd', round(v_est, 4), 'floor_usd', v_floor,
    'held', v_est is not null and v_est <= v_floor, 'usage_weekly', k.usage_weekly, 'period_days', v_days, 'ceiling_usd', v_ceiling,
    'period_ceiling_usd', case when v_days is not null and v_ceiling > 0 then v_ceiling * v_days end, 'max_age_minutes', v_age);
end $function$;
revoke all on function security.openrouter_key_room_v1() from public, anon, authenticated;

-- 4. Giving stopped items back to their queue (worker)
create or replace function public.svc_ai_key_limit_release_v1(p_queue text, p_items jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare n int := 0; v_why text := left(coalesce(nullif(p_reason, ''), 'OpenRouter key limit'), 300);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'p_items must be an array of {id, cost}'; end if;
  -- only an item still leased is given back (one a later worker call already recorded is left as it is); the lease's try is given back and the
  -- cost of any attempt the cascade made before the refusal is added, so the spend ledger keeps it
  if p_queue = 'field_enrich_items' then
    update pipeline.field_enrich_items e set state = 'ai', leased_until = null, attempts = greatest(e.attempts - 1, 0), reason = v_why,
           cost_usd = case when x.cost > 0 then coalesce(e.cost_usd, 0) + x.cost else e.cost_usd end, updated_at = now()
      from (select (i->>'id')::bigint id, max(coalesce(nullif(i->>'cost', '')::numeric, 0)) cost from jsonb_array_elements(p_items) i group by 1) x
     where e.id = x.id and e.state = 'leased';
  elsif p_queue = 'entry_matrix_runs' then
    update pipeline.entry_matrix_runs r set state = 'queued', leased_until = null, attempts = greatest(r.attempts - 1, 0), error = left(v_why, 400),
           cost_usd = case when x.cost > 0 then coalesce(r.cost_usd, 0) + x.cost else r.cost_usd end, updated_at = now()
      from (select (i->>'id')::uuid id, max(coalesce(nullif(i->>'cost', '')::numeric, 0)) cost from jsonb_array_elements(p_items) i group by 1) x
     where r.id = x.id and r.state = 'leased';
  elsif p_queue = 'fee_reader_queue' then
    update pipeline.fee_reader_queue q set state = 'queued', leased_until = null, attempts = greatest(q.attempts - 1, 0), error = left(v_why, 400),
           cost_usd = case when x.cost > 0 then coalesce(q.cost_usd, 0) + x.cost else q.cost_usd end
      from (select (i->>'id')::uuid id, max(coalesce(nullif(i->>'cost', '')::numeric, 0)) cost from jsonb_array_elements(p_items) i group by 1) x
     where q.id = x.id and q.state = 'leased';
  elsif p_queue = 'central_ai_queue' then
    update pipeline.central_ai_queue q set state = 'queued', leased_until = null, attempts = greatest(q.attempts - 1, 0), error = left(v_why, 400),
           cost_usd = case when x.cost > 0 then coalesce(q.cost_usd, 0) + x.cost else q.cost_usd end
      from (select (i->>'id')::bigint id, max(coalesce(nullif(i->>'cost', '')::numeric, 0)) cost from jsonb_array_elements(p_items) i group by 1) x
     where q.id = x.id and q.state = 'leased';
  elsif p_queue = 'scholarship_eligibility_reads' then
    update pipeline.scholarship_eligibility_reads e set state = 'queued', leased_until = null, tries = greatest(e.tries - 1, 0), last_error = left(v_why, 400),
           cost_usd = case when x.cost > 0 then coalesce(e.cost_usd, 0) + x.cost else e.cost_usd end, updated_at = now()
      from (select (i->>'id')::bigint id, max(coalesce(nullif(i->>'cost', '')::numeric, 0)) cost from jsonb_array_elements(p_items) i group by 1) x
     where e.candidate_id = x.id and e.state = 'leased';
  elsif p_queue = 'coverage_ai_match' then
    -- as svc_coverage_ai_match_record does for an HTTP refusal: offered again, no decision recorded
    update pipeline.coverage_ai_match q set state = 'ready', leased_until = null
      from (select distinct (i->>'id')::bigint id from jsonb_array_elements(p_items) i) x
     where q.id = x.id and q.state = 'leased';
  else
    raise exception 'unknown queue %', p_queue;
  end if;
  get diagnostics n = row_count;
  return jsonb_build_object('queue', p_queue, 'released', n, 'asked', jsonb_array_length(p_items));
end $function$;
revoke all on function public.svc_ai_key_limit_release_v1(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_ai_key_limit_release_v1(text, jsonb, text) to service_role;

-- 5. md5-guarded edits of the live text
create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_old text, p_new text) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
end $f$;

-- 5a. security.ai_route_v1: the key with no room holds everything; the key and the room are reported
create or replace function pg_temp.edit_route() returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef('security.ai_route_v1(text)'::regprocedure); v_pairs text[][] := array[
  array[$o$        v_kind text; v_detail text; v_lk text; v_ld text; v_bal numeric; v_at timestamptz; v_floor numeric; v_since numeric := 0; v_est numeric;$o$,
        $n$        v_kind text; v_detail text; v_lk text; v_ld text; v_bal numeric; v_at timestamptz; v_floor numeric; v_since numeric := 0; v_est numeric;
        v_key jsonb := security.openrouter_key_room_v1();  -- v1.0.3: the OpenRouter key's own limit (pipeline.openrouter_key_observations)$n$],
  array[$o$                       round(v_est, 2), round(v_bal, 2), round(v_since, 2), v_floor);
  end if;$o$,
        $n$                       round(v_est, 2), round(v_bal, 2), round(v_since, 2), v_floor);
  -- v1.0.3 (15 Nov 2026): the key's own limit, or a budget over it, is the account's: with no room left everything is held, Run now included
  elsif coalesce((v_key->>'held')::boolean, false) then v_kind := 'key_limit';
    v_detail := format('the OpenRouter key has no room: about US$%s left of its %s limit of US$%s (%s at %s, less US$%s spent since), floor US$%s. All AI work is held, Run now included, until the limit resets or is raised on OpenRouter',
                       round((v_key->>'estimated_usd')::numeric, 2), coalesce(v_key->>'limit_reset', 'total'), coalesce(v_key->>'limit_usd', '?'),
                       case when v_key->>'source' = 'refusal' then 'refused' else 'read' end,
                       to_char((v_key->>'observed_at')::timestamptz at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), round((v_key->>'spent_since_usd')::numeric, 2), v_floor);
  end if;$n$],
  array[$o$'balance', jsonb_build_object('usd', v_bal, 'spent_since_usd', round(v_since, 4), 'estimated_usd', round(v_est, 4), 'floor_usd', v_floor, 'known', v_bal is not null, 'observed_at', v_at, 'max_age_minutes', v_age));$o$,
        $n$'balance', jsonb_build_object('usd', v_bal, 'spent_since_usd', round(v_since, 4), 'estimated_usd', round(v_est, 4), 'floor_usd', v_floor, 'known', v_bal is not null, 'observed_at', v_at, 'max_age_minutes', v_age),
                            -- v1.0.3: the key, and the room left today: the lower of the daily ceiling still free and what the key has above the floor
                            'key', v_key,
                            'room_usd', round(least(case when v_ceiling > 0 then greatest(v_ceiling - v_all, 0) end,
                                                    case when (v_key->>'estimated_usd') is not null then greatest((v_key->>'estimated_usd')::numeric - v_floor, 0) end), 4));$n$]];
  i int; v_c int;
begin
  if md5(v_def) <> '296ea425580568d428c041b09258aa8d' then raise exception 'live security.ai_route_v1 differs from the definition this change edits (md5 %)', md5(v_def); end if;
  for i in 1 .. array_length(v_pairs, 1) loop
    v_c := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    if v_c <> 1 then raise exception 'security.ai_route_v1: edit % must apply exactly once (found %)', i, v_c; end if;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  end loop;
  execute v_def;
end $f$;
select pg_temp.edit_route();

-- 5b. security.ai_use_refusal_v1: the key's limit refuses whatever the mode (as the credit floor does in security.ai_route_v1)
select pg_temp.edit_once('security.ai_use_refusal_v1(text)', '60c782e5aec7eb218c1149a3ad85dde2',
  $o$begin
  select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';$o$,
  $n$begin
  -- v1.0.3 (15 Nov 2026): the OpenRouter key's own limit is the account's: no room refuses every lane, whatever the OpenRouter mode
  if coalesce((security.openrouter_key_room_v1()->>'held')::boolean, false) then
    return format('key limit: the OpenRouter key has no room (about US$%s left of its %s limit), floor US$%s (openrouter.credit_floor_usd)',
                  round((security.openrouter_key_room_v1()->>'estimated_usd')::numeric, 2), coalesce(security.openrouter_key_room_v1()->>'limit_reset', 'total'),
                  coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0));
  end if;
  select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';$n$);

-- 5c. public.svc_ai_model_answered_v1: an attempt the key refused is kept apart (never a model failure)
select pg_temp.edit_once('public.svc_ai_model_answered_v1(text,text,text,jsonb,text)', '5fcf1139ef68495331c663393754cdf9',
  $o$      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null;
    get diagnostics n = row_count;$o$,
  $n$      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null and coalesce(x->>'failure_kind', '') <> 'key_limit';
    get diagnostics n = row_count;
    -- CF-247 worker v1.0.3: attempts the OpenRouter key refused for its own limit: an account stop, kept apart from the model's attempts
    insert into pipeline.ai_key_limit_attempts (service_code, model, attempt_no, source, source_id, worker)
    select nullif(x->>'service', ''), x->>'model', coalesce((x->>'attempt_no')::int, 1), nullif(x->>'source', ''), nullif(x->>'source_id', ''), left(p_worker, 60)
      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null and x->>'failure_kind' = 'key_limit';$n$);
-- the attempt times: a key refusal is not a model's time either
select pg_temp.edit_once('public.svc_ai_model_answered_v1(text,text,text,jsonb,text)',
  md5(pg_get_functiondef('public.svc_ai_model_answered_v1(text,text,text,jsonb,text)'::regprocedure)),
  $o$      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null and coalesce(x->>'ms', '') ~ '^[0-9]{1,9}$';$o$,
  $n$      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null and coalesce(x->>'ms', '') ~ '^[0-9]{1,9}$'
       and coalesce(x->>'failure_kind', '') <> 'key_limit';$n$);

-- 5d. security.platform_health_check_v1: the key's limit on Health
select pg_temp.edit_once('security.platform_health_check_v1(boolean)', '25ff04344e2a940a3132e7ba709f98aa',
  $o$      select count(*) into v_num from pipeline.layer3_interpretations i
       where i.created_at>=now()-interval '30 minutes' and i.validator_result::text ~ 'provider_(401|402|403|429)';$o$,
  $n$      -- CF-247 worker v1.0.3 (15 Nov 2026): the OpenRouter key's own limit (job openrouter-balance reads it; a refusal records it at once)
      declare k jsonb := security.openrouter_key_room_v1();
      begin
        if coalesce((k->>'held')::boolean, false) then
          v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_key','critical','budgets',
            'The OpenRouter key has no room: about US$'||round((k->>'estimated_usd')::numeric,2)||' left of its '||coalesce(k->>'limit_reset','total')||' limit of US$'||coalesce(k->>'limit_usd','?')
            ||'. All AI work is held until the limit resets or is raised on OpenRouter',k);
        elsif (k->>'period_ceiling_usd') is not null and (k->>'limit_usd') is not null and (k->>'limit_usd')::numeric < (k->>'period_ceiling_usd')::numeric then
          v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_key','warning','budgets',
            'The OpenRouter key''s '||(k->>'limit_reset')||' limit of US$'||(k->>'limit_usd')||' is below the daily ceiling over that period (US$'||(k->>'ceiling_usd')||' x '||(k->>'period_days')
            ||' days = US$'||(k->>'period_ceiling_usd')||'): the key will stop AI work before the ceiling does',k);
        elsif not coalesce((k->>'reading')::boolean, false) then
          v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_key','warning','budgets',
            'The OpenRouter key''s limit has not been read in the last '||(k->>'max_age_minutes')||' minutes (job openrouter-balance): a key limit would not be seen before it refuses',k);
        end if;
      end;
      select count(*) into v_num from pipeline.layer3_interpretations i
       where i.created_at>=now()-interval '30 minutes' and i.validator_result::text ~ 'provider_(401|402|403|429)';$n$);

-- 6. The register
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.openrouter_key_observations', 'Layer 2', 'AI', 'Readings and refusals of the OpenRouter key''s own limit', 'active', '{}', '20261115140000'),
 ('table', 'pipeline.ai_key_limit_attempts', 'Layer 2', 'AI', 'AI call attempts the OpenRouter key refused for its own limit', 'active', '{}', '20261115140000'),
 ('function', 'public.svc_openrouter_key_record_v1', 'Layer 2', 'AI', 'Records a key limit reading (job openrouter-balance) or a refusal (worker)', 'active', '{}', '20261115140000'),
 ('function', 'security.openrouter_key_room_v1', 'Layer 2', 'AI', 'What the OpenRouter key has left, for the AI guards and Health', 'active', '{}', '20261115140000'),
 ('function', 'public.svc_ai_key_limit_release_v1', 'Layer 2', 'AI', 'Gives items a key limit refusal stopped back to their queue', 'active', '{}', '20261115140000')
on conflict do nothing;

-- 7. Post-checks: the edits are in; no switch, mode, ceiling or route moved; nothing is held while no key reading exists yet
do $c$
declare v_before jsonb := current_setting('cf247.v103_before')::jsonb; v_rt jsonb;
begin
  if pg_get_functiondef('security.ai_route_v1(text)'::regprocedure) not like '%key_limit%'
     or pg_get_functiondef('security.ai_use_refusal_v1(text)'::regprocedure) not like '%openrouter_key_room_v1%'
     or pg_get_functiondef('public.svc_ai_model_answered_v1(text,text,text,jsonb,text)'::regprocedure) not like '%ai_key_limit_attempts%'
     or pg_get_functiondef('security.platform_health_check_v1(boolean)'::regprocedure) not like '%budgets:openrouter_key%' then
    raise exception 'post-check: every edit is in';
  end if;
  if (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter') is distinct from v_before->>'openrouter'
     or security.pipeline_num_v1('layer4.drain_on', 0) <> (v_before->>'drain')::numeric or security.pipeline_num_v1('reading.markdown_input', 0) <> (v_before->>'md')::numeric
     or security.pipeline_num_v1('health.ai_reorder_on', 0) <> (v_before->>'reorder')::numeric or security.pipeline_num_v1('aer.v2_shadow_on', 0) <> (v_before->>'shadow')::numeric
     or security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) <> (v_before->>'ceiling')::numeric
     or (select jsonb_agg(jsonb_build_array(r.service_code, r.enabled, r.cascade, r.daily_usd_cap, r.migration_state) order by r.service_code) from pipeline.ai_service_routes r)
        is distinct from v_before->'routes' then
    raise exception 'post-check: switches, the OpenRouter mode, the ceiling and every route are unchanged';
  end if;
  v_rt := security.ai_route_v1('course_description');
  if v_rt->>'held_kind' = 'key_limit' and not exists (select 1 from pipeline.openrouter_key_observations) then
    raise exception 'post-check: no key limit hold without a key reading';
  end if;
end $c$;
