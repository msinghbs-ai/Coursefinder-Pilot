-- Worker release fixtures (migration 20261104110000). Each case raises on failure and prints "<id> ok".
-- W1 the job does nothing while ops.ai_diagnosis_on is 0, and calls the worker only when a request waits with the switch on
do $f$
declare v_cmd text := (select command from cron.job where jobname = 'ops-diagnose'); v_n int;
begin
  create temp table submitted(fn text, body jsonb);
  create or replace function pipeline.svc_pilot_submit_nonce(p_fn text, p_body jsonb) returns bigint language sql as $s$ insert into submitted values (p_fn, p_body); select 1::bigint $s$;
  insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values ('pipeline', 'ops.ai_diagnosis_on', 'switch', 'number', '0');
  insert into pipeline.ops_ai_diagnosis_requests(issue_id, context) values (1, '{"title": "x"}');
  execute v_cmd;
  if (select count(*) from submitted) <> 0 then raise exception 'W1: called with the switch off'; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'ops.ai_diagnosis_on';
  execute v_cmd;
  if (select count(*) from submitted where body->>'mode' = 'ops_diagnose' and (body->>'limit')::int = 5) <> 1 then raise exception 'W1: not called with the switch on'; end if;
  update pipeline.ops_ai_diagnosis_requests set state = 'answered';
  execute v_cmd;
  if (select count(*) from submitted) <> 1 then raise exception 'W1: called with nothing waiting'; end if;
  if (select schedule from cron.job where jobname = 'ops-diagnose') ~ '(^|,)(3[5-9]|4[0-2]|4[78]|0[0-5]|[0-5]) ' then raise exception 'W1: busy minute'; end if;
  raise notice 'W1 ok: off does nothing; on with a waiting request calls ops_diagnose with batch.ops_diagnose; nothing waiting does nothing';
end $f$;

-- W2 an earlier answer for the same query inside ops_cost.repeat_search_hours; never a search still being answered or a failed one
do $f$
declare v jsonb;
begin
  insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values ('pipeline', 'ops_cost.repeat_search_hours', 'window', 'number', '24');
  insert into pipeline.course_link_search(course_id, state, query, results, sent_at) values
   (gen_random_uuid(), 'none',  'Bachelor  of Nursing site:u1.example', '[]', now() - interval '2 hours'),
   (gen_random_uuid(), 'found', 'bachelor of nursing site:u1.example', '["https://u1.example/a"]', now() - interval '1 hour'),
   (gen_random_uuid(), 'sent',  'bachelor of nursing site:u1.example', '["https://u1.example/stale"]', now()),
   (gen_random_uuid(), 'none',  'master of arts site:u1.example', '[]', now() - interval '3 hours'),
   (gen_random_uuid(), 'none',  'old query', '[]', now() - interval '30 hours'),
   (gen_random_uuid(), 'error', 'failed query', '{"http_status": 500, "body": "x"}', now() - interval '1 hour');
  set local request.jwt.claim.role = 'service_role';
  v := public.svc_course_link_search_prior_v1(array['bachelor of nursing site:u1.example', 'master of arts site:u1.example', 'old query', 'failed query', 'never searched']);
  if v <> '{"bachelor of nursing site:u1.example": ["https://u1.example/a"], "master of arts site:u1.example": []}'::jsonb then raise exception 'W2: %', v; end if;
  raise notice 'W2 ok: %', v;
end $f$;

-- W3 only the service role may read it; nothing new ships on
do $f$
begin
  begin
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    set role authenticated;
    perform public.svc_course_link_search_prior_v1(array['x']);
    reset role;
    raise exception 'W3: callable by authenticated';
  exception when insufficient_privilege then reset role;
  end;
  if (select count(*) from pipeline.platform_toolset_settings where key in ('reading.entry_range_lower_bound_on', 'reading.entry_subject_rows_on', 'reading.entry_global_pages_on', 'reading.link_search_share_on')
        and (value #>> '{}')::numeric = 0) <> 4 then raise exception 'W3: shipped on'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'ops-diagnose') then raise exception 'W3: catalogue'; end if;
  raise notice 'W3 ok: service role only; four behaviours ship off; job catalogued';
end $f$;

-- W4 the worker's two answer shapes against A2's recorder (contract ops-diagnose-v1): {error} is recorded with its cost and never handed out
-- again; a contract answer whose quote holds quotation marks is checked against the context's text values and accepted
do $f$
declare v jsonb; v_id1 bigint; v_id2 bigint;
begin
  insert into pipeline.ops_root_causes(code, class, title) values ('statement_timeout', 'transient', 'Statement time-out');
  insert into pipeline.integration_issues(diagnosis) values ('{"root_cause": "statement_timeout", "confidence": 0.3}');
  insert into pipeline.ops_ai_diagnosis_requests(issue_id, state, leased_until, model, context)
  values (currval('pipeline.integration_issues_id_seq'), 'leased', now() + interval '10 minutes', 'openai/gpt-4.1-mini', '{"evidence": {"error": "canceling statement \"refresh\" due to statement timeout"}}')
  returning id into v_id1;
  insert into pipeline.ops_ai_diagnosis_requests(issue_id, state, leased_until, model, context)
  values (currval('pipeline.integration_issues_id_seq'), 'leased', now() + interval '10 minutes', 'openai/gpt-4.1-mini', '{"title": "x"}') returning id into v_id2;
  -- an answer as opsDiagnoseAnswer gives it: only the contract's fields
  v := public.svc_ops_diagnosis_record(v_id1, '{"root_cause": "statement_timeout", "confidence": 0.8, "evidence": ["statement \"refresh\" due to statement timeout"], "reasoning": "The error names it."}', 0.0012);
  if v->>'state' <> 'answered' or not (v->>'applied')::boolean then raise exception 'W4: contract answer %', v; end if;
  -- a worker failure as the worker sends it
  v := public.svc_ops_diagnosis_record(v_id2, '{"error": "output_truncated: reached reading.answer_tokens.ops_diagnosis (800)"}', 0.0007);
  if v->>'state' <> 'refused' or (select cost_usd from pipeline.ops_ai_diagnosis_requests where id = v_id2) <> 0.0007 then raise exception 'W4: error answer %', v; end if;
  if exists (select 1 from pipeline.ops_ai_diagnosis_requests where id = v_id2 and (state in ('queued', 'leased'))) then raise exception 'W4: error request can be handed out again'; end if;
  raise notice 'W4 ok: contract answer applied (quote with quotation marks), {error} refused with its cost and not handed out again';
end $f$;
