-- CF-247 P0 workstream A follow-ups (Integration Controller, 3 Nov 2026 18:20; branch cf247-ops-a2, builds on v2.15.433): (1) a closed integration
-- issue reopens only on evidence observed after it closed; (2) the AI-assisted diagnosis contract for workstream B's worker mode ops_diagnose.
-- Why (production, read-only, 3 Nov 2026 18:16-18:17 AEDT):
--   (1) IQ-00067 was closed with verified evidence at 16:44:22. At 16:51 integration-validate reopened it as a regression ("failed 5 of 6 run(s) in
--       the last hour; 18 failure(s) in the last 24 hours"), although its last failed run was at 16:33 and every run from 16:43 to 18:13 succeeded.
--       Cause: step 0 of security.integration_validate_v1 feeds the open Platform health issue cron:failed:coverage-admit into the queue each run,
--       and that health issue stays open on a 24-hour failure count; security.integration_issue_upsert_v1 reopened any closed issue on any repeat,
--       with no time on the evidence. The controller then read regression_count > 0 as a recurrence and blocked it as needs_release. After the
--       Integration Controller closed it again at 18:15 the same health issue was still open (last seen 18:08, "17 failure(s) in the last 24 hours"),
--       so it would be reopened again at each :21 and :51 until about 16:33 on 4 Nov; IQ-00067 also kept ops_state needs_release and its blocker
--       while closed. Every regression reopening on record: IQ-00067 (16:51, false) and IQ-00028 (the Integration Controller's synthetic self-test,
--       intended). No other closed issue had an open health issue behind it.
--   (2) The AI diagnosis lane, if switched on, would spend outside the daily AI ceiling: pipeline.ops_ai_diagnosis_requests had no spend capture,
--       and security.ai_spend_today_v1 sums only its listed lanes (live md5 0a8e30c2d38c37071474fdd23fa31cfc). The quote check compared quotes with
--       the JSON text of the context, where quotation marks are escaped.
-- What:
--   1 security.integration_issue_upsert_v1: a caller may give observed_at (when its evidence was observed; default now, as before). A closed issue
--     whose new evidence was observed at or before closed_at is left closed and unchanged (action closed_evidence_before_close); a reopening records
--     observed_at and closed_at in its history line.
--   2 security.integration_validate_v1: a scheduler-failure health issue passes the start time of the job's last failed run as observed_at (its
--     first_seen when no failed run is among the runs looked at); other health issues pass their last_seen; the failed-run check passes its
--     newest failure. Nothing else changes.
--   3 security.ops_recurrence_v1 (new) and security.ops_issue_signals_v1: "recurred" uses the same rule: the evidence time recorded with the
--     reopening, or for a job issue a failed run that started after the close. A reopening without evidence after the close is a stale reopening.
--   4 root cause reopened_on_stale_evidence and auto remedy reclose_stale_reopen: the controller records the evidence, verifies on a later run that
--     still nothing failed after the close, and closes the issue again through security.integration_issue_close_v1 with that evidence.
--   5 security.ops_controller_tick_v1: a closed issue keeps no open controller state (ops_state needs_release, needs_decision, remedying, verifying
--     or diagnosed becomes verified; the blocker and next action are cleared), with a history line; an issue reopened since its last diagnosis is
--     looked at on the next run, whatever its next look was (IQ-00067, reopened again at 18:21 after being blocked at 16:54 with its next look
--     at 22:54). Together with 4, this is the reconciliation of IQ-00067.
--   6 AI-assisted diagnosis (still OFF, ops.ai_diagnosis_on 0): spend capture on pipeline.ops_ai_diagnosis_requests (lane ops_diagnose, the existing
--     security.ai_spend_capture_v1); the picker holds while the lane is not counted by security.ai_spend_today_v1, while security.ai_use_refusal_v1
--     refuses (credit floor, daily ceiling, lane guard) and at the lane's own daily cap (new setting ops.ai_diagnosis_usd_per_day); each item carries
--     the contract version, the instructions and the answer schema; the recorder takes a worker error, and checks quotes against the context's text.
-- Replaces: security.integration_issue_upsert_v1, security.integration_validate_v1, security.ops_issue_signals_v1, security.ops_controller_tick_v1, public.svc_ops_diagnosis_next, public.svc_ops_diagnosis_record (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. Nothing is switched on. No Firecrawl or AI spend. Consumer API untouched (G3).
-- md5 (pg_get_functiondef) before -> after:
--   security.integration_issue_upsert_v1(jsonb,text)                  f292f65689a35e213a3d12a539c11b1d -> c5ce0cb9c431a337789d67bc1878be62
--   security.integration_validate_v1()                                5d88b7c14f4db3b26e7b2650364602db -> 9ad0f6380ec74ef7e5260bf43ff297fd
--   security.ops_issue_signals_v1(bigint,jsonb)                       a966f2b39a734f05c045c53e274d0863 -> e6b69bb75a5f6bd087e560c657f1455c
--   security.ops_controller_tick_v1()                                 24793664aa99d3d97da1dcb2e63fb28c -> b4df5f8106fcbaca1bfcd933f532a55f
--   public.svc_ops_diagnosis_next(integer)                            ade1ae9613bbdfd6f45bd6408e20d880 -> adc209ebf9196c613e3dd82fa76fed61
--   public.svc_ops_diagnosis_record(bigint,jsonb,numeric)             1ac0cc3359af6bca9c0e28e74ed49bcd -> 6f1fd77189ea85610a57c6feef16a130

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

-- 0. the definitions the new code calls are the ones it was written against (not changed here)
do $g$
declare r record;
begin
  for r in select * from (values ('security.integration_issue_close_v1(bigint,text,jsonb)', '4cae8eaee7444e0aa942b2702eb10bc6'),
                                 ('security.ai_spend_capture_v1()', '5b78fa074a9480d4f127ecc4fe93dcf3'),
                                 ('security.ai_use_refusal_v1(text)', '60c782e5aec7eb218c1149a3ad85dde2')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $g$;

-- 1. setting (G2) --------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ops.ai_diagnosis_usd_per_day', 'Operations controller: AI diagnosis spend a day',
  'The AI-assisted diagnosis lane (ops_diagnose) hands out no request once its recorded spend today (UTC) reaches this. It is part of, never above, the daily AI ceiling.',
  'number', to_jsonb(0.5), 0, 5, 'US$', 1124, 'Operations controller', 'public.svc_ops_diagnosis_next', 'Integration Controller 3 Nov 2026 18:20: AI-assisted diagnosis switch-on conditions (cap)')
on conflict do nothing;

-- 2. a closed issue reopens only on evidence observed after it closed ------------------------------------------------------------------------
select pg_temp.edit_once('security.integration_issue_upsert_v1(jsonb,text)', 'f292f65689a35e213a3d12a539c11b1d', 'c5ce0cb9c431a337789d67bc1878be62', array[
  array[$o$  if r.status = 'closed' then
$o$, $n$  if r.status = 'closed' and coalesce((p->>'observed_at')::timestamptz, now()) <= r.closed_at then
    -- P0 IQ-00067 (3 Nov 2026 16:51): evidence observed at or before the close (a trailing 24-hour count, an old failed run) is not a
    -- recurrence: the issue stays closed and unchanged
    return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', 'closed_evidence_before_close', 'status', r.status,
                              'observed_at', coalesce((p->>'observed_at')::timestamptz, now()), 'closed_at', r.closed_at);
  end if;
  if r.status = 'closed' then
$n$],
  array[$o$jsonb_build_object('regression_count', r.regression_count, 'evidence', coalesce(p->'evidence', '{}'::jsonb), 'new_providers', cardinality(v_new_prov), 'new_courses', cardinality(v_new_course)));$o$,
        $n$jsonb_build_object('regression_count', r.regression_count, 'evidence', coalesce(p->'evidence', '{}'::jsonb), 'new_providers', cardinality(v_new_prov), 'new_courses', cardinality(v_new_course),
                               'observed_at', coalesce((p->>'observed_at')::timestamptz, now()), 'closed_at', r.closed_at));$n$]
]::text[][], array[1, 1]);

select pg_temp.edit_once('security.integration_validate_v1()', '5d88b7c14f4db3b26e7b2650364602db', '9ad0f6380ec74ef7e5260bf43ff297fd', array[
  array[$o$    for r in select p.check_key, p.severity, p.area, p.title, p.detail, p.first_seen from pipeline.platform_issues p$o$,
        $n$    -- P0 IQ-00067: when the evidence was observed: a scheduler failure by its job's last failed run (a 24-hour count stays open long after);
    -- other health issues by their last observation
    for r in select p.check_key, p.severity, p.area, p.title, p.detail, p.first_seen,
                    case when p.check_key like 'cron:failed:%'
                         then coalesce((select max(x.start_time) from (select d.jobid, d.status, d.start_time from cron.job_run_details d order by d.runid desc limit v_scan) x
                                          join cron.job j on j.jobid = x.jobid where j.jobname = substr(p.check_key, 13) and x.status = 'failed'), p.first_seen)
                         else p.last_seen end observed_at
               from pipeline.platform_issues p$n$],
  array[$o$        'evidence', jsonb_build_object('platform_issue', r.check_key, 'first_seen', r.first_seen, 'detail', r.detail),$o$,
        $n$        'evidence', jsonb_build_object('platform_issue', r.check_key, 'first_seen', r.first_seen, 'detail', r.detail), 'observed_at', r.observed_at,$n$],
  array[$o$'evidence', jsonb_build_object('failed_runs', r.n, 'last_runid', r.last_runid, 'last_at', r.last_at, 'message', r.msg), 'severity', 'P1',$o$,
        $n$'evidence', jsonb_build_object('failed_runs', r.n, 'last_runid', r.last_runid, 'last_at', r.last_at, 'message', r.msg), 'observed_at', r.last_at, 'severity', 'P1',$n$]
]::text[][], array[1, 1, 1]);

-- 3. the controller's recurrence uses the same rule ---------------------------------------------------------------------------------------------
create or replace function security.ops_recurrence_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- P0 IQ-00067: whether a reopened issue really recurred: evidence observed after the close that preceded the reopening. The evidence time is the
-- one recorded with the reopening (security.integration_issue_upsert_v1 records it from 3 Nov 2026); for an earlier reopening of a job issue,
-- a failed run of the job that started after the close (among the newest ops.runs_scan scheduler runs). Without either, a reopening by its own
-- check counts as a recurrence.
declare r pipeline.integration_issues; v_reopen timestamptz; v_obs timestamptz; v_closed timestamptz; v_job text; v_fail timestamptz; v_runs int; v_failed int;
        v_scan int := security.pipeline_num_v1('ops.runs_scan', 20000)::int;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  if not found or (r.regression_count = 0 and r.status <> 'reopened') then return jsonb_build_object('recurred', false, 'stale_reopen', false, 'basis', 'never reopened'); end if;
  select e.at, (e.detail->>'observed_at')::timestamptz into v_reopen, v_obs from pipeline.integration_issue_events e
   where e.issue_id = p_issue and e.kind = 'reopened_regression' order by e.at desc, e.id desc limit 1;
  select max(c.at) into v_closed from pipeline.integration_issue_events c where c.issue_id = p_issue and c.kind = 'closed' and c.at < coalesce(v_reopen, 'infinity');
  v_closed := coalesce(v_closed, r.closed_at);
  if r.status = 'closed' or v_closed is null then
    return jsonb_build_object('recurred', false, 'stale_reopen', false, 'basis', case when r.status = 'closed' then 'closed' else 'no close on record' end);
  end if;
  if v_obs is not null then
    return jsonb_build_object('recurred', v_obs > v_closed, 'stale_reopen', v_obs <= v_closed, 'basis', 'the evidence time recorded with the reopening',
                              'observed_at', v_obs, 'closed_at', v_closed, 'reopened_at', v_reopen);
  end if;
  v_job := case when r.fingerprint like 'job_failed:%' then substr(r.fingerprint, 12) when r.fingerprint like 'job:%' then split_part(r.fingerprint, ':', 2) end;
  if v_job is not null and exists (select 1 from cron.job j where j.jobname = v_job) then
    select min(x.start_time) filter (where x.status = 'failed'), count(*), count(*) filter (where x.status = 'failed') into v_fail, v_runs, v_failed
      from (select d.jobid, d.status, d.start_time from cron.job_run_details d where d.runid > (select coalesce(max(y.runid), 0) from cron.job_run_details y) - v_scan) x
      join cron.job j on j.jobid = x.jobid where j.jobname = v_job and x.start_time > v_closed;
    return jsonb_build_object('recurred', v_fail is not null, 'stale_reopen', v_fail is null, 'basis', 'the job''s runs after the close',
                              'job', v_job, 'closed_at', v_closed, 'reopened_at', v_reopen, 'runs_after_close', v_runs, 'failed_after_close', v_failed, 'first_failure_after_close', v_fail);
  end if;
  return jsonb_build_object('recurred', true, 'stale_reopen', false, 'basis', 'reopened by its own check; no evidence time to compare', 'closed_at', v_closed, 'reopened_at', v_reopen);
end $function$;
revoke all on function security.ops_recurrence_v1(bigint) from public, anon, authenticated;

select pg_temp.edit_once('security.ops_issue_signals_v1(bigint,jsonb)', 'a966f2b39a734f05c045c53e274d0863', 'e6b69bb75a5f6bd087e560c657f1455c', array[
  array[$o$        v_share numeric; v_material int; v_clear numeric;$o$,
        $n$        v_share numeric; v_material int; v_clear numeric; v_rec jsonb := security.ops_recurrence_v1(p_issue);$n$],
  array[$o$    'recurred', r.regression_count > 0 or r.status = 'reopened',$o$,
        $n$    'recurred', coalesce((v_rec->>'recurred')::boolean, false), 'stale_reopen', coalesce((v_rec->>'stale_reopen')::boolean, false), 'recurrence', v_rec,$n$]
]::text[][], array[1, 1]);

-- 4. a stale reopening is closed again on its evidence ----------------------------------------------------------------------------------------
create or replace function security.ops_remedy_reclose_record_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Action of remedy reclose_stale_reopen: records why the reopening was not a recurrence. Changes nothing.
declare v jsonb := security.ops_recurrence_v1(p_issue);
begin
  return jsonb_build_object('ok', coalesce((v->>'stale_reopen')::boolean, false), 'changed', false, 'evidence', v);
end $function$;
revoke all on function security.ops_remedy_reclose_record_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_verify_stale_reopen_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Verification (a later controller run): still no evidence observed after the close. Passed: the issue is closed again with this evidence.
declare v jsonb := security.ops_recurrence_v1(p_issue); v_ok boolean := coalesce((v->>'stale_reopen')::boolean, false);
begin
  return jsonb_build_object('passed', v_ok, 'measure', v || jsonb_build_object('condition_cleared', v_ok),
    'evidence', case when v_ok then format('Reopened at %s on evidence observed before the close at %s (%s); nothing observed since the close%s. The verification of the close stands.',
                                          v->>'reopened_at', v->>'closed_at', v->>'basis',
                                          case when v ? 'runs_after_close' then format(': %s run(s) of %s since, %s failed', v->>'runs_after_close', v->>'job', v->>'failed_after_close') else '' end)
                     else 'evidence observed after the close: ' || coalesce(v->>'basis', '') end);
end $function$;
revoke all on function security.ops_verify_stale_reopen_v1(bigint) from public, anon, authenticated;

select security.ops_root_cause_register_v1('reopened_on_stale_evidence', '{"class": "data", "title": "Reopened on evidence from before the close", "description": "The issue was reopened as a regression, but nothing was observed after it closed (a trailing count or an old failed run): it is not a recurrence and is closed again on that evidence.", "detect": {"priority": 8, "confidence": 0.9, "all": [{"signal": "stale_reopen"}]}}'::jsonb);
select security.ops_remedy_register_v1('reclose_stale_reopen', '{"title": "Close again: the reopening had no evidence after the close", "treats": ["reopened_on_stale_evidence"], "authority": "auto", "action_fn": "security.ops_remedy_reclose_record_v1(bigint)", "verify_fn": "security.ops_verify_stale_reopen_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes", "notes": "Changes nothing; verified on a later run (still no failed run or observation after the close) and closed through integration_issue_close_v1."}'::jsonb);

-- 5. a closed issue keeps no open controller state ------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.ops_controller_tick_v1()', '24793664aa99d3d97da1dcb2e63fb28c', 'b4df5f8106fcbaca1bfcd933f532a55f', array[
  array[$o$  -- 2 Correlate ---$o$,
        $n$  -- 1b A closed issue keeps no open controller state (closed elsewhere, for example by the Integration Controller): reconciled, with a history line
  for r in select x.id, x.ops_state from pipeline.integration_issues x
            where x.status = 'closed' and x.ops_state in ('needs_release', 'needs_decision', 'remedying', 'verifying', 'diagnosed') loop
    update pipeline.integration_issues set ops_state = 'verified', blocker = null, next_action_at = null where id = r.id;
    insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
    values (r.id, 'updated', 'closed', 'closed', 'ops-controller', 'Closed with verified evidence; the controller''s open record (' || r.ops_state || ') is cleared',
            jsonb_build_object('from_ops_state', r.ops_state));
    v_n := v_n || jsonb_build_object('reconciled_closed', coalesce((v_n->>'reconciled_closed')::int, 0) + 1);
  end loop;

  -- 2 Correlate ---$n$],
  array[$o$            where x.status <> 'closed' and coalesce(x.next_action_at, '-infinity') <= v_t0$o$,
        $n$            -- due, or reopened since its last diagnosis (a reopening is new evidence, whatever its next look was)
            where x.status <> 'closed' and (coalesce(x.next_action_at, '-infinity') <= v_t0 or x.reopened_at > coalesce((x.diagnosis->>'at')::timestamptz, '-infinity'))$n$]
]::text[][], array[1, 1]);

-- 6. AI-assisted diagnosis: spend inside the daily ceiling, the guards, the contract (still off) ----------------------------------------------------
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'ai_spend_capture' and tgrelid = 'pipeline.ops_ai_diagnosis_requests'::regclass) then
    create trigger ai_spend_capture after insert or update of cost_usd on pipeline.ops_ai_diagnosis_requests
      for each row execute function security.ai_spend_capture_v1('ops_diagnose', 'delta', '{cost_usd}');
  end if;
end $t$;

select pg_temp.edit_once('public.svc_ops_diagnosis_next(integer)', 'ade1ae9613bbdfd6f45bd6408e20d880', 'adc209ebf9196c613e3dd82fa76fed61', array[
  array[$o$declare v jsonb; v_today int; v_room int; v_tz text := 'Australia/Melbourne';  -- fixed: the platform's reporting time zone$o$,
        $n$declare v jsonb; v_today int; v_room int; v_ref text; v_tz text := 'Australia/Melbourne';  -- fixed: the platform's reporting time zone$n$],
  array[$o$    return jsonb_build_object('items', '[]'::jsonb, 'held', 'daily AI ceiling reached');
  end if;
$o$, $n$    return jsonb_build_object('items', '[]'::jsonb, 'held', 'daily AI ceiling reached');
  end if;
  -- the lane's spend must count in the daily ceiling (security.ai_spend_today_v1 lists the lanes it sums)
  if not exists (select 1 from security.ai_spend_today_v1() t where t.use = 'ops_diagnose') then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'the ops_diagnose lane is not counted in the daily AI ceiling yet (security.ai_spend_today_v1)');
  end if;
  v_ref := security.ai_use_refusal_v1('ops_diagnose');  -- the existing guard: credit floor, daily ceiling, lane guard (stop mode)
  if v_ref is not null then return jsonb_build_object('items', '[]'::jsonb, 'held', v_ref); end if;
  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'ops_diagnose' and l.at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))  -- fixed: the UTC day the AI guards count
     >= security.pipeline_num_v1('ops.ai_diagnosis_usd_per_day', 0.5) then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'ops.ai_diagnosis_usd_per_day reached');
  end if;
$n$],
  array[$o$  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'model', q.model, 'context', q.context)), '[]'::jsonb) into v$o$,
        $n$  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'model', q.model, 'lease_until', q.leased_until, 'contract', 'ops-diagnose-v1', 'context', q.context,
           'instructions', 'You diagnose one StudySearch integration issue from the context only. Choose exactly one root_cause from the codes in context.root_causes. '
                           || 'Give confidence from 0 to 1. Give evidence as short quotes copied exactly, character for character, from text values in the context (not paraphrased). '
                           || 'Do not propose actions, settings or code changes. Answer with one JSON object that matches response_schema and nothing else.',
           'response_schema', jsonb_build_object('type', 'object', 'required', jsonb_build_array('root_cause', 'confidence', 'evidence'), 'additionalProperties', false,
             'properties', jsonb_build_object(
               'root_cause', jsonb_build_object('type', 'string', 'enum', (select jsonb_agg(c.code order by c.code) from pipeline.ops_root_causes c)),
               'confidence', jsonb_build_object('type', 'number', 'minimum', 0, 'maximum', 1),
               'evidence', jsonb_build_object('type', 'array', 'minItems', 1, 'items', jsonb_build_object('type', 'string')),
               'reasoning', jsonb_build_object('type', 'string'))))), '[]'::jsonb) into v$n$],
  array[$o$  return jsonb_build_object('items', v);$o$, $n$  return jsonb_build_object('items', v, 'contract', 'ops-diagnose-v1');$n$]
]::text[][], array[1, 1, 1, 1]);

select pg_temp.edit_once('public.svc_ops_diagnosis_record(bigint,jsonb,numeric)', '1ac0cc3359af6bca9c0e28e74ed49bcd', '6f1fd77189ea85610a57c6feef16a130', array[
  array[$o$  v_ctx := q.context::text;$o$,
        $n$  -- a worker error is recorded (with any cost spent) and the request is not retried
  if p_answer ? 'error' then
    update pipeline.ops_ai_diagnosis_requests set state = 'refused', answer = p_answer, cost_usd = p_cost_usd, answered_at = now(),
           note = left('worker error: ' || (p_answer->>'error'), 300) where id = p_id;
    return jsonb_build_object('id', p_id, 'state', 'refused', 'reason', 'worker error');
  end if;
  -- quotes are checked against the context's text values (not its JSON text, where quotation marks are escaped)
  v_ctx := (select string_agg(x #>> '{}', E'\n') from jsonb_path_query(q.context, 'strict $.** ? (@.type() == "string")') x);$n$]
]::text[][], array[1]);

-- 7. component register ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.ops_recurrence_v1', 'Platform', 'CF-247 P0: a reopening is a recurrence only on evidence observed after the close', 'active', '{}', '20261104100000'),
 ('function', 'security.ops_remedy_reclose_record_v1', 'Platform', 'CF-247 P0: remedy reclose_stale_reopen (action)', 'active', '{}', '20261104100000'),
 ('function', 'security.ops_verify_stale_reopen_v1', 'Platform', 'CF-247 P0: remedy reclose_stale_reopen (verification)', 'active', '{}', '20261104100000')
on conflict do nothing;
