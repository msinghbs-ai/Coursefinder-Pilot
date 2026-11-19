CREATE OR REPLACE FUNCTION security.admission_rule_run_v1(p_code text, p_lane text, p_tick timestamp with time zone, p_due timestamp with time zone, p_due_minutes integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r pipeline.admission_rules; v_t0 timestamptz := clock_timestamp(); v_ms int; v_err text; v_out text; v_sql text; v_after int; v_back int; v_max int; v_until timestamptz;
begin
  select * into v_r from pipeline.admission_rules where rule_code = p_code for update skip locked;
  if not found then return 'locked'; end if;  -- another lane holds it
  if v_r.last_due_at is not null and v_r.last_due_at >= p_due then return 'already'; end if;  -- another lane ran it since this lane looked
  if md5(v_r.call_sql) <> v_r.call_md5 then
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, status, error)
    values (p_tick, p_lane, p_code, v_r.mode, p_due, p_due_minutes, v_t0, clock_timestamp(), 'refused', 'call_sql changed since registration (md5)');
    update pipeline.admission_rules set last_status = 'refused', last_error = 'call_sql changed since registration (md5)', updated_at = now() where rule_code = p_code;
    return 'refused';
  end if;
  if v_r.mode = 'shadow' then
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status)
    values (p_tick, p_lane, p_code, 'shadow', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'shadow_due');
    update pipeline.admission_rules set last_due_at = p_due, last_status = 'shadow_due', updated_at = now() where rule_code = p_code;
    return 'shadow_due';
  end if;
  if v_r.open_until is not null and v_r.open_until > now() then
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, error)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'skipped_open', 'breaker open until ' || v_r.open_until);
    update pipeline.admission_rules set last_due_at = p_due, last_status = 'skipped_open', updated_at = now() where rule_code = p_code;
    return 'skipped_open';
  end if;
  -- a single statement keeps its answer as telemetry; a command of several statements runs as one
  v_sql := rtrim(v_r.call_sql, E'; \n\t');
  begin
    if position(';' in v_sql) = 0 then execute v_sql into v_out; else execute v_r.call_sql; end if;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, over_budget, result)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'succeeded', v_ms > coalesce(v_r.budget_ms, v_ms), left(v_out, 2000));
    update pipeline.admission_rules set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'succeeded',
           last_result = left(v_out, 2000), last_error = null, last_ms = v_ms, consecutive_failures = 0, open_until = null, updated_at = now()
     where rule_code = p_code;
    if v_r.consecutive_failures > 0 then
      update pipeline.platform_issues set resolved_at = now(), last_seen = now()
       where check_key = 'admission_rule_breaker:' || p_code and resolved_at is null;
    end if;
    return 'succeeded';
  exception when others then
    get stacked diagnostics v_err = message_text;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    v_after := security.pipeline_num_v1('admission_runner.breaker_after_failures', 3)::int;
    v_back := security.pipeline_num_v1('admission_runner.breaker_backoff_minutes', 15)::int;
    v_max := security.pipeline_num_v1('admission_runner.breaker_backoff_max_minutes', 240)::int;
    if v_r.consecutive_failures + 1 >= v_after then
      v_until := now() + make_interval(mins => least(v_max, v_back * power(2, greatest(0, v_r.consecutive_failures + 1 - v_after)))::int);
    end if;
    insert into pipeline.admission_rule_runs(tick_at, lane, rule_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, over_budget, error)
    values (p_tick, p_lane, p_code, 'live', p_due, p_due_minutes, v_t0, clock_timestamp(), v_ms, 'failed', v_ms > coalesce(v_r.budget_ms, v_ms), left(v_err, 1000));
    -- a failed run counts as run (as a failed cron run does): the next run is at the next scheduled minute, or after the back-off
    update pipeline.admission_rules set last_due_at = p_due, last_started_at = v_t0, last_finished_at = clock_timestamp(), last_status = 'failed',
           last_error = left(v_err, 1000), last_ms = v_ms, consecutive_failures = consecutive_failures + 1, open_until = coalesce(v_until, open_until), updated_at = now()
     where rule_code = p_code;
    if v_until is not null then
      if exists (select 1 from pipeline.platform_issues where check_key = 'admission_rule_breaker:' || p_code and resolved_at is null) then
        update pipeline.platform_issues set last_seen = now(), occurrences = occurrences + 1,
               detail = jsonb_build_object('rule', p_code, 'failures_in_a_row', v_r.consecutive_failures + 1, 'skipped_until', v_until, 'last_error', left(v_err, 300))
         where check_key = 'admission_rule_breaker:' || p_code and resolved_at is null;
      else
        insert into pipeline.platform_issues(check_key, severity, area, title, detail)
        values ('admission_rule_breaker:' || p_code, 'warning', 'admission',  -- an area platform_issues allows (platform_issues_area_check)
                'Admission rule ' || p_code || ' failed ' || (v_r.consecutive_failures + 1) || ' times in a row: skipped until ' || to_char(v_until at time zone 'UTC', 'HH24:MI') || ' UTC',
                jsonb_build_object('rule', p_code, 'failures_in_a_row', v_r.consecutive_failures + 1, 'skipped_until', v_until, 'last_error', left(v_err, 300)));
      end if;
    end if;
    return 'failed';
  end;
end $function$
