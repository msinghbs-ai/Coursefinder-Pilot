-- CF-247 AI models and services: the behaviour of migrations 20261113380000 and 20261113390000 on the fixture rows (data.sql, data2.sql).
-- Each block raises on a failure.
\set ON_ERROR_STOP 1
set client_min_messages = notice;
create function pg_temp.expect_error(p_sql text, p_like text) returns void language plpgsql as $$
begin
  begin execute p_sql; exception when others then
    if sqlerrm not like p_like then raise exception 'expected an error like "%", got "%"', p_like, sqlerrm; end if; return;
  end;
  raise exception 'expected an error like "%" from: %', p_like, p_sql;
end $$;

do $$  -- 1 route resolution, cascade order, the backfilled spend
declare r jsonb;
begin
  r := security.ai_route_v1('course_entry_requirements');
  assert r->'models' = '[{"code":"qwen3-30b","model_identifier":"qwen/qwen3-30b-a3b-instruct-2507"},{"code":"mistral-small-3.2","model_identifier":"mistralai/mistral-small-3.2-24b-instruct"}]'::jsonb, r::text;
  assert r->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507' and (r->>'held')::boolean = false and r->'held_reason' = 'null'::jsonb, r::text;
  assert (r#>>'{spent_today,usd}')::numeric = 0.30 and (r#>>'{cap,usd}')::numeric = 5, r::text;  -- item 2 is the entry requirements item
  assert (security.ai_route_v1('course_description')#>>'{spent_today,usd}')::numeric = 0.20;
  assert (security.ai_route_v1('course_other_fields')#>>'{spent_today,usd}')::numeric = 0.01;
  assert (security.ai_route_v1('scholarship_extraction')#>>'{spent_today,usd}')::numeric = 0.05 and (security.ai_route_v1('scholarship_eligibility')#>>'{spent_today,usd}')::numeric = 0.02;
  assert (security.ai_route_v1('calendar_reading')#>>'{spent_today,usd}')::numeric = 0.04 and (security.ai_route_v1('entry_requirements_v2_shadow')#>>'{spent_today,usd}')::numeric = 0.03;
  assert (select count(*) from pipeline.ai_spend_ledger where service_code is null) = 0 and (select count(*) from pipeline.ai_spend_ledger where model is not null) = 0, 'backfill: every row a service, no model';
  assert (security.ai_route_v1('entry_matrices')#>>'{cap,usd}')::numeric = 20 and (security.ai_route_v1('ops_diagnosis')#>>'{cap,calls}')::int = 20, 'caps seeded from the settings';
  r := security.ai_route_v1('nothing');
  assert (r->>'held')::boolean and r->>'held_reason' like 'unknown service%' and r->'models' = '[]'::jsonb;
  raise notice 'ok 1 route resolution, cascade order, caps from settings, backfilled spend by service';
end $$;

do $$  -- 2 a model that is not allowed is skipped; none left holds the route
declare r jsonb;
begin
  update pipeline.ai_model_catalogue set status = 'not_allowed' where code = 'qwen3-30b';
  r := security.ai_route_v1('course_entry_requirements');
  assert r->>'model' = 'mistralai/mistral-small-3.2-24b-instruct' and jsonb_array_length(r->'models') = 1 and not (r->>'held')::boolean, r::text;
  r := security.ai_route_v1('course_description');
  assert (r->>'held')::boolean and r->>'held_reason' = 'no allowed model in the cascade' and r->'model' = 'null'::jsonb, r::text;
  update pipeline.ai_model_catalogue set status = 'allowed' where code = 'qwen3-30b';
  update pipeline.ai_service_routes set enabled = false where service_code = 'entry_matrices';
  assert security.ai_route_v1('entry_matrices')->>'held_reason' = 'switched off (Models & services)';
  update pipeline.ai_service_routes set enabled = true where service_code = 'entry_matrices';
  insert into pipeline.ai_model_catalogue (code, family, label, model_identifier) values ('fx-odd', 'somefamily', 'Odd', 'odd/odd-1');
  assert (select family || ':' || status from pipeline.ai_model_catalogue where code = 'fx-odd') = 'other:not_allowed';
  assert (select count(*) from pipeline.ai_model_catalogue where model_identifier ~ '^(openai|anthropic)/' and (status <> 'not_allowed' or family <> 'other')) = 0;
  raise notice 'ok 2 not_allowed skipped, no model left holds, switched off holds, unknown family stored as other';
end $$;

do $$  -- 3 a service cap holds its field only; the other fields still flow
declare w jsonb; r jsonb; v_fields text[];
begin
  update pipeline.ai_service_routes set daily_usd_cap = 1 where service_code = 'course_description';
  update pipeline.field_enrich_items set cost_usd = 0.9 where id = 4;  -- a description: the trigger records it with its service and model
  assert (select service_code || '|' || model from pipeline.ai_spend_ledger order by id desc limit 1) = 'course_description|qwen/qwen3-30b-a3b-instruct-2507';
  r := security.ai_route_v1('course_description');
  assert (r->>'held')::boolean and r->>'held_reason' = 'service cap: US$1.10 spent today (UTC), cap US$1', r::text;
  w := public.svc_enrich_ai_next(10);
  select array_agg(i->>'field' order by i->>'field') into v_fields from jsonb_array_elements(w->'pages') p, jsonb_array_elements(p->'items') i;
  assert v_fields = array['deadline', 'entry_requirements', 'intakes'], v_fields::text;
  assert w->'held' ? 'course_description' and not (w->'held' ? 'course_other_fields'), (w->'held')::text;
  assert (select count(*) from pipeline.field_enrich_items where field = 'description' and state = 'ai' and attempts = 0) = 2, 'held description items are untouched';
  assert w->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507' and w->>'model_code' = 'qwen3-30b' and w#>>'{entry,model}' = 'qwen/qwen3-30b-a3b-instruct-2507', w::text;
  assert w#>'{entry,models}' = security.ai_route_v1('course_entry_requirements')->'models' and w#>>'{routes,course_description,held}' = 'true';
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  -- a calls cap, and the rest route (where_not): every field but description and entry requirements is held
  update pipeline.ai_service_routes set daily_usd_cap = 100 where service_code = 'course_description';
  update pipeline.ai_service_routes set daily_calls_cap = 1 where service_code = 'course_other_fields';
  assert security.ai_route_v1('course_other_fields')->>'held_reason' = 'service cap: 1 calls today (UTC), cap 1';
  w := public.svc_enrich_ai_next(10);
  select array_agg(i->>'field' order by i->>'field') into v_fields from jsonb_array_elements(w->'pages') p, jsonb_array_elements(p->'items') i;
  assert v_fields = array['description', 'description', 'entry_requirements'], v_fields::text;
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  update pipeline.ai_service_routes set daily_calls_cap = null where service_code = 'course_other_fields';
  raise notice 'ok 3 a cap holds its fields only, the others flow; the ledger carries service and model';
end $$;

do $$  -- 4 the daily ceiling holds every route, whatever the OpenRouter mode
declare w jsonb;
begin
  assert (select enforcement from pipeline.platform_toolsets where key = 'openrouter') = 'observe';
  update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd';
  assert (select bool_and((security.ai_route_v1(service_code)->>'held')::boolean and security.ai_route_v1(service_code)->>'held_reason' like 'daily ceiling: US$1.56 spent today (UTC) across all AI services, ceiling US$1 %') from pipeline.ai_service_routes);
  w := public.svc_enrich_ai_next(10);
  assert w->'pages' = '[]'::jsonb and w->'titles' = '[]'::jsonb and jsonb_typeof(w->'model') = 'string' and w->>'model' <> '' and (select count(*) from jsonb_object_keys(w->'held')) = 3, w::text;
  assert public.svc_entry_matrix_next(4) = '[]'::jsonb;
  assert public.svc_ops_diagnosis_next(1)->>'held' like 'daily ceiling:%' and public.svc_ops_diagnosis_next(1)->'items' = '[]'::jsonb;
  assert (select count(*) from pipeline.field_enrich_items where state <> 'ai') = 0 and (select count(*) from pipeline.entry_matrix_runs where state <> 'queued') = 0;
  -- on-demand work is not held by a limit (operating model 3.3.2): an open request for the provider lets its items through; switched off still holds
  insert into pipeline.on_demand_requests (provider_ids, expires_at) values (array['00000000-0000-0000-0000-00000000b001'::uuid], now() + interval '1 hour');
  assert security.ai_route_v1('course_description')->>'held_kind' = 'limit';
  w := public.svc_enrich_ai_next(10);
  assert (select count(*) from jsonb_array_elements(w->'pages') p, jsonb_array_elements(p->'items') i) = 5 and w->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507', w::text;
  assert jsonb_array_length(public.svc_entry_matrix_next(4)) = 1;
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  update pipeline.entry_matrix_runs set state = 'queued', attempts = 0, leased_until = null, model_code = null;
  update pipeline.ai_service_routes set enabled = false where service_code in ('course_description', 'entry_matrices');
  assert security.ai_route_v1('course_description')->>'held_kind' = 'off';
  w := public.svc_enrich_ai_next(10);
  assert (select array_agg(i->>'field' order by i->>'field') from jsonb_array_elements(w->'pages') p, jsonb_array_elements(p->'items') i) = array['deadline', 'entry_requirements', 'intakes'], w::text;
  assert public.svc_entry_matrix_next(4) = '[]'::jsonb;
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  update pipeline.ai_service_routes set enabled = true where service_code in ('course_description', 'entry_matrices');
  update pipeline.on_demand_requests set state = 'closed';
  update pipeline.platform_toolset_settings set value = '14' where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd';
  raise notice 'ok 4 the daily ceiling holds every route and the three readers hand out nothing; an on-demand provider is not held by a limit, but is by a switch';
end $$;

do $$  -- 5 the writes: role, reason, refusals, the log; the central readers keep one model
declare o jsonb; v_n int;
begin
  perform pg_temp.expect_error($q$select public.admin_ai_overview_v1()$q$, 'Pipeline Operator role or above required');
  perform set_config('fx.uid', '00000000-0000-0000-0000-0000000000a1', false); perform set_config('fx.rank', '4', false);
  assert (public.admin_ai_overview_v1()->>'can_control')::boolean = false;
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b'], 5, null, null, 'a reason')$q$, 'PIM Operator role or above required');
  perform pg_temp.expect_error($q$select public.admin_ai_model_set_v1('qwen3-30b', 'not_allowed', 'a reason')$q$, 'PIM Operator role or above required');
  perform set_config('fx.rank', '5', false);
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b'], 5, null, null, '')$q$, 'give a reason%');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array[]::text[], 5, null, null, 'a reason')$q$, 'the cascade is empty%');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', null, 5, null, null, 'a reason')$q$, 'the cascade is empty%');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b', 'gpt-4.1-mini'], 5, null, null, 'a reason')$q$, 'not an allowed model: gpt-4.1-mini%');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['claude-haiku-4.5'], 5, null, null, 'a reason')$q$, 'not an allowed model: claude-haiku-4.5%');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['no-such-model'], 5, null, null, 'a reason')$q$, 'unknown model in the cascade: no-such-model');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b', 'qwen3-30b'], 5, null, null, 'a reason')$q$, 'the cascade names a model twice');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b', 'qwen3-235b', 'mimo-v2.6-pro', 'kimi-k2-0905', 'llama-4-scout'], 5, null, null, 'a reason')$q$, 'a cascade holds 4 models at most');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b'], -1, null, null, 'a reason')$q$, 'a cap cannot be negative%');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b'], null, null, null, 'a reason')$q$, 'give a daily US$ cap%');
  perform pg_temp.expect_error($q$select public.admin_ai_route_set_v1('no_such', array['qwen3-30b'], 5, null, null, 'a reason')$q$, 'service no_such is not in the list');
  perform pg_temp.expect_error($q$select public.admin_ai_model_set_v1('qwen3-30b', 'maybe', 'a reason')$q$, 'status must be allowed or not_allowed');
  assert (select count(*) from pipeline.admin_control_events where area = 'ai_models' and action in ('route_set', 'model_status')) = 0, 'a refused write logs nothing';
  -- a wired route
  o := public.admin_ai_route_set_v1('course_entry_requirements', array['deepseek-v3.2', 'qwen3-30b'], 3, 500, null, 'fixture: cheaper first');
  assert security.ai_route_v1('course_entry_requirements')->>'model' = 'deepseek/deepseek-v3.2' and (security.ai_route_v1('course_entry_requirements')#>>'{cap,usd}')::numeric = 3;
  assert (select detail#>>'{before,cascade}' || ' > ' || (detail#>>'{after,cascade}') || ' | ' || (detail->>'reason') || ' | ' || actor from pipeline.admin_control_events where action = 'route_set')
         = '["qwen3-30b", "mistral-small-3.2"] > ["deepseek-v3.2", "qwen3-30b"] | fixture: cheaper first | 00000000-0000-0000-0000-0000000000a1';
  assert public.svc_enrich_ai_next(10)#>>'{entry,model}' = 'deepseek/deepseek-v3.2';
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  -- each central service has its own cascade now; pipeline.central_ai_settings is a copy of the intake calendar route and cannot be set directly
  o := public.admin_ai_route_set_v1('fee_reader', array['mistral-small-3.2', 'qwen3-30b'], 5, null, true, 'fixture: fees on another model');
  assert (select model_code from pipeline.central_ai_settings where id = 1) = 'qwen3-30b', 'the fee route does not move the copy';
  assert (select count(*) from pipeline.ai_service_routes where cascade = array['mistral-small-3.2', 'qwen3-30b']) = 1, 'no other route follows';
  assert security.ai_service_model_v1('fee_reader') = 'mistralai/mistral-small-3.2-24b-instruct' and security.ai_service_model_v1('provider_description') = 'qwen/qwen3-30b-a3b-instruct-2507';
  o := public.admin_ai_route_set_v1('calendar_reading', array['mimo-v2.6-flash', 'qwen3-30b'], 5, null, true, 'fixture: calendars');
  assert (select model_code || '|' || model_identifier from pipeline.central_ai_settings where id = 1) = 'mimo-v2.6-flash|xiaomi/mimo-v2.6-flash';
  perform pg_temp.expect_error($q$update pipeline.central_ai_settings set model_code = 'gpt-4.1-mini', model_identifier = 'openai/gpt-4.1-mini' where id = 1$q$, 'the model is chosen on Models & services%');
  perform pg_temp.expect_error($q$update pipeline.central_ai_settings set model_code = 'qwen3-30b', model_identifier = 'qwen/qwen3-30b-a3b-instruct-2507' where id = 1$q$, 'the model is chosen on Models & services%');
  update pipeline.central_ai_settings set calls_at_once = 3 where id = 1;  -- the other columns are still set there
  -- a model switched off: the copy moves to the next allowed one; back on, it returns
  o := public.admin_ai_model_set_v1('mimo-v2.6-flash', 'not_allowed', 'fixture: off');
  assert (select model_code from pipeline.central_ai_settings where id = 1) = 'qwen3-30b';
  assert (select jsonb_array_length(detail->'services') from pipeline.admin_control_events where action = 'model_status' order by id desc limit 1) = 1;
  o := public.admin_ai_model_set_v1('mimo-v2.6-flash', 'allowed', 'fixture: on again');
  assert (select model_code from pipeline.central_ai_settings where id = 1) = 'mimo-v2.6-flash';
  o := public.admin_ai_route_set_v1('calendar_reading', array['qwen3-30b'], 5, null, true, 'fixture: back');
  o := public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b'], 5, null, true, 'fixture: back');
  raise notice 'ok 5 writes: role, reason, every refusal, the log; each central service has its own cascade and the old copy cannot be set';
end $$;

do $$  -- 6 the ledger: service and model going forward
begin
  update pipeline.central_ai_queue set cost_usd = 0.01;
  update pipeline.entry_matrix_runs set model_code = 'qwen/qwen3-30b-a3b-instruct-2507', cost_usd = 0.02;
  update pipeline.field_enrich_items set cost_usd = coalesce(cost_usd, 0) + 0.001 where id in (2, 3);
  assert (select string_agg(service_code || '=' || model, ', ' order by service_code) from (select * from pipeline.ai_spend_ledger order by id desc limit 5) x)
         = 'calendar_reading=qwen/qwen3-30b-a3b-instruct-2507, central_english_policy=qwen/qwen3-30b-a3b-instruct-2507, course_entry_requirements=deepseek/deepseek-v3.2, course_other_fields=qwen/qwen3-30b-a3b-instruct-2507, entry_matrices=qwen/qwen3-30b-a3b-instruct-2507',
         (select string_agg(service_code || '=' || coalesce(model, '-'), ', ' order by service_code) from (select * from pipeline.ai_spend_ledger order by id desc limit 5) x);
  raise notice 'ok 6 new costs carry their service and model';
end $$;

do $$  -- 7 the page read
declare o jsonb := public.admin_ai_overview_v1(); s jsonb;
begin
  assert (select array_agg(k order by k) from jsonb_object_keys(o) k) = array['can_control', 'day_start', 'events', 'guard', 'legacy', 'legacy_controls', 'models', 'openrouter', 'services', 'usage'];
  assert (select array_agg(k order by k) from jsonb_object_keys(o->'openrouter') k)
         = array['balance_observed_at', 'balance_usd', 'daily_ceiling_usd', 'floor_usd', 'key_present', 'key_secret_name', 'low_warn_usd', 'mode', 'settings', 'spent_today_usd', 'total_credits_usd'];
  assert (o#>>'{openrouter,key_present}')::boolean and (o#>>'{openrouter,balance_usd}')::numeric = 53 and (o#>>'{openrouter,daily_ceiling_usd}')::numeric = 14 and (o#>>'{openrouter,floor_usd}')::numeric = 0.5;
  assert o::text !~* 'sk-or-|bearer', 'no key in the read';
  assert jsonb_array_length(o->'services') = 15 and jsonb_array_length(o->'models') = 18;
  assert (select count(*) from jsonb_array_elements(o#>'{openrouter,settings}') x where x->>'key' in ('credit_floor_usd', 'budgets.ai_daily_ceiling_usd')) = 2;
  select x into s from jsonb_array_elements(o->'services') x where x->>'service_code' = 'entry_matrices';
  assert (select array_agg(k order by k) from jsonb_object_keys(s) k) = array['area', 'cascade', 'cascade_detail', 'changed_at', 'changed_by', 'daily_calls_cap', 'daily_usd_cap', 'enabled', 'enforced', 'field', 'held', 'held_kind', 'held_reason',
         'label', 'lane', 'ledger_match', 'model', 'model_in_effect', 'models', 'note', 'prompt', 'reason', 'resolver', 'service_code', 'settings', 'spent_today', 'wired'], (select string_agg(k, ',' order by k) from jsonb_object_keys(s) k);
  assert (s->>'wired')::boolean and s#>>'{prompt,source}' = 'worker code' and s#>>'{prompt,version}' = 'entry-matrix-v0.1.4' and s#>'{prompt,text}' = 'null'::jsonb;
  assert (select array_agg(x->>'key' order by x->>'key') from jsonb_array_elements(s->'settings') x) = array['entry.matrix_enabled', 'entry.matrix_model'];
  select x into s from jsonb_array_elements(o->'services') x where x->>'service_code' = 'provider_description';
  assert s#>>'{prompt,version}' = '4' and s#>>'{prompt,text}' = 'You write a provider description.' and (s->>'enforced')::boolean and s->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507';
  select x into s from jsonb_array_elements(o->'services') x where x->>'service_code' = 'scholarship_extraction';
  assert s#>>'{prompt,version}' = '3' and s->>'resolver' = 'route' and s->'cascade' = '["qwen3-30b"]'::jsonb;
  assert o#>'{legacy_controls,scholarship_chain,chain}' = '["qwen3-30b"]'::jsonb, 'GPT-4.1 mini left the scholarship chain';
  assert (select x->'used_by' from jsonb_array_elements(o->'models') x where x->>'code' = 'gpt-4.1-mini') = '[]'::jsonb;
  assert (select count(*) from jsonb_array_elements(o#>'{usage,by_day_14d}') x where x->>'service_code' = 'course_description' and x->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507') = 1;
  assert jsonb_array_length(o#>'{usage,by_hour_24h}') > 0 and jsonb_array_length(o->'events') >= 5;
  assert (select count(*) from pipeline.platform_toolset_settings where home = 'models_services') = 27 and (select home from pipeline.platform_toolset_settings where key = 'batch.coverage_read') is null;
  assert (select used_by from pipeline.platform_toolset_settings where key = 'entry.matrix_model') like 'not read since migration 20261113380000%Was: public.svc_entry_matrix_next';
  assert (select value from pipeline.platform_toolset_settings where key = 'entry.matrix_model') = '"openai/gpt-4.1-mini"'::jsonb, 'the old setting keeps its value';
  raise notice 'ok 7 the page read: OpenRouter pane, models, services with prompt and settings, usage, log';
end $$;

do $$  -- 8 phase 2: every service is resolved by its route and capped; the central and course-matching readers hand out the route's model and hold with it
declare o jsonb; w jsonb;
begin
  assert (select count(*) from pipeline.ai_service_routes where resolver <> 'route' or daily_usd_cap is null) = 0;
  assert (select string_agg(service_code || '=' || daily_usd_cap, ', ' order by service_code) from pipeline.ai_service_routes where service_code in ('course_description', 'course_other_fields', 'scholarship_eligibility', 'central_english_policy', 'page_identity'))
         = 'central_english_policy=2, course_description=100, course_other_fields=2, page_identity=1, scholarship_eligibility=2';
  assert (select bool_and((x->>'enforced')::boolean and x->>'model' is not null and x->'prompt' ? 'source') from jsonb_array_elements(public.admin_ai_overview_v1()->'services') x);
  perform set_config('fx.role', 'service_role', false);
  update pipeline.ai_service_routes set cascade = array['mistral-small-3.2', 'qwen3-30b'] where service_code = 'central_english_policy';
  update pipeline.ai_service_routes set enabled = false where service_code = 'calendar_reading';
  w := public.svc_central_ai_next(6);
  assert jsonb_array_length(w) = 1 and w#>>'{0,kind}' = 'english_policy' and w#>>'{0,model}' = 'mistralai/mistral-small-3.2-24b-instruct' and w#>>'{0,model_code}' = 'mistral-small-3.2'
     and jsonb_array_length(w#>'{0,models}') = 2, w::text;   -- the calendar item waits: its route is switched off
  update pipeline.central_ai_queue set state = 'queued', attempts = 0, leased_until = null;
  update pipeline.ai_service_routes set enabled = true where service_code = 'calendar_reading';
  update pipeline.ai_service_routes set daily_usd_cap = 0.01 where service_code = 'central_english_policy';   -- today's spend is over it
  w := public.svc_central_ai_next(6);
  assert jsonb_array_length(w) = 1 and w#>>'{0,kind}' = 'intake_calendar' and w#>>'{0,model}' = 'qwen/qwen3-30b-a3b-instruct-2507', w::text;
  update pipeline.central_ai_queue set state = 'queued', attempts = 0, leased_until = null;
  update pipeline.ai_service_routes set daily_usd_cap = 2, cascade = array['qwen3-30b'] where service_code = 'central_english_policy';
  w := public.svc_coverage_ai_match_next(5);
  assert jsonb_array_length(w) = 1 and w#>>'{0,model}' = 'qwen/qwen3-30b-a3b-instruct-2507' and w#>'{0,models}' = security.ai_route_v1('course_matching')->'models', w::text;
  update pipeline.coverage_ai_match set state = 'ready', leased_until = null;
  update pipeline.ai_service_routes set enabled = false where service_code = 'course_matching';
  assert public.svc_coverage_ai_match_next(5) = '[]'::jsonb;
  update pipeline.ai_service_routes set enabled = true where service_code = 'course_matching';
  raise notice 'ok 8 every service is route-resolved and capped; central pages and course-page matching hand out and hold by their own routes';
end $$;

do $$  -- 9 phase 2: scholarship chain, adapter proposals, entry requirements v2, pinned-ok, the copies
declare a record; j jsonb;
begin
  select * into a from security.scholarship_ai_active_v1();
  assert a.model_code = 'qwen3-30b' and a.model_identifier = 'qwen/qwen3-30b-a3b-instruct-2507' and a.prompt_version = 3;
  assert security.scholarship_ai_next_model_v1('qwen3-30b') is null and security.scholarship_ai_next_model_v1('gpt-4.1-mini') is null, 'after the last model, and for a model no longer in the cascade, a person decides';
  update pipeline.ai_service_routes set cascade = array['qwen3-30b', 'kimi-k2-0905', 'gpt-4.1-mini'] where service_code = 'scholarship_extraction';  -- a not_allowed model put in by hand is skipped
  assert security.scholarship_ai_next_model_v1('qwen3-30b') = 'kimi-k2-0905' and security.scholarship_ai_next_model_v1('kimi-k2-0905') is null;
  assert (select chain from pipeline.scholarship_ai_extract_settings where id = 1) = array['qwen3-30b', 'kimi-k2-0905'], 'the chain is a copy of the allowed cascade';
  perform pg_temp.expect_error($q$update pipeline.scholarship_ai_extract_settings set chain = array['gpt-4.1-mini'] where id = 1$q$, 'the model is chosen on Models & services%');
  assert (security.ai_route_guard_v1()->'cascades') = '[{"model": "gpt-4.1-mini", "status": "not_allowed", "service": "scholarship_extraction"}]'::jsonb;
  update pipeline.ai_service_routes set cascade = array['qwen3-30b'] where service_code = 'scholarship_extraction';
  -- adapter proposals: the route's model; a provider's own choice of a model outside the cascade (Claude here) is not used
  j := security.adapter_builder_model_for_v1('00000000-0000-0000-0000-00000000b001');
  assert j->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507' and j->>'code' = 'openrouter-intake-l3c-qwen3-30b-a3b-2507-v1' and (j->>'chosen')::boolean = false, j::text;
  update pipeline.uni_adapter_models set profile_code = 'openrouter-intake-l3c-kimi-k2-0905-v1';
  update pipeline.ai_service_routes set cascade = array['qwen3-30b', 'kimi-k2-0905'] where service_code = 'adapter_builder';
  j := security.adapter_builder_model_for_v1('00000000-0000-0000-0000-00000000b001');
  assert j->>'model' = 'moonshotai/kimi-k2-0905' and (j->>'chosen')::boolean, j::text;
  assert (select array_agg(x->>'model' order by x->>'model') from jsonb_array_elements(security.adapter_builder_models_v1()) x) = array['moonshotai/kimi-k2-0905', 'qwen/qwen3-30b-a3b-instruct-2507'], 'no Claude in the choices';
  j := security.adapter_builder_budget();
  assert (j->>'limit_usd')::numeric = 5 and (j->>'limit_proposals')::int = 1000 and j->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507', j::text;
  update pipeline.ai_service_routes set enabled = false where service_code = 'adapter_builder';
  assert (security.adapter_builder_budget()->>'limit_usd')::numeric = 0 and (security.adapter_builder_budget()->>'limit_proposals')::int = 0;
  update pipeline.ai_service_routes set enabled = true, cascade = array['qwen3-30b'] where service_code = 'adapter_builder';
  -- entry requirements v2: the model is the route's, the prompt version keeps its text; the route's switch holds it
  j := security.aer_v2_shadow_hold_v1();
  assert j->'held' = 'null'::jsonb and j#>>'{version,model}' = 'qwen/qwen3-30b-a3b-instruct-2507' and j#>>'{version,system_text}' = 'You read entry requirements.' and jsonb_array_length(j#>'{version,models}') = 2, j::text;
  assert (select model from pipeline.aer_prompt_versions) = 'openai/gpt-4.1-mini', 'the prompt version row is not rewritten';
  update pipeline.ai_service_routes set enabled = false where service_code = 'entry_requirements_v2_shadow';
  assert security.aer_v2_shadow_hold_v1()->>'held' = 'switched off (Models & services)';
  update pipeline.ai_service_routes set enabled = true where service_code = 'entry_requirements_v2_shadow';
  assert security.ai_model_pinned_ok_v1('qwen/qwen3-30b-a3b-instruct-2507') and not security.ai_model_pinned_ok_v1('openai/gpt-4.1-mini') and not security.ai_model_pinned_ok_v1('openrouter/auto');
  raise notice 'ok 9 scholarship chain from the route, adapter proposals, entry requirements v2 and pinned-ok follow the routes; the copies cannot be set';
end $$;

do $$  -- 10 phase 2: the guard, the Layer 3 report, the real model in the ledger
declare g jsonb := security.ai_route_guard_v1(); o jsonb := public.admin_ai_overview_v1(); n int;
begin
  assert g->'functions' @> '[{"function": "public.fx_pins_a_model", "model": "openai/gpt-4.1-mini", "status": "not_allowed"}]'::jsonb, (g->'functions')::text;
  assert not (g->'functions' @> '[{"function": "public.fx_allowed_default"}]'::jsonb), 'an allowed model as a coalesce default is not reported';
  assert not exists (select 1 from jsonb_array_elements(g->'functions') x where x->>'function' ~ 'svc_(enrich_ai|entry_matrix|ops_diagnosis|fee_ai|central_ai|coverage_ai_match)_next|aer_v2_shadow_hold_v1'), (g->'functions')::text;
  assert g->'settings' @> '[{"setting": "pipeline.entry.matrix_model", "model": "openai/gpt-4.1-mini", "status": "not_allowed"}, {"setting": "firecrawl.builder_model", "status": "allowed"}]'::jsonb, (g->'settings')::text;
  assert g->'cascades' = '[]'::jsonb and (g->>'not_allowed_named')::int >= 3 and o->'guard' = g->'not_allowed_named';
  assert o#>>'{legacy,layer3,last_call_at}' like '2026-10-11%' and o#>'{legacy,layer3,jobs}' = '[]'::jsonb and jsonb_array_length(o#>'{legacy,layer3,profiles_switched_on}') = 4;
  assert o#>'{legacy,layer3,profiles_switched_on}' @> '[{"code": "openrouter-english-l3r-claude-sonnet-4-6-v1", "in_active_tier": false, "catalogue_status": "not_allowed"}]'::jsonb;
  -- the course field reader's item keeps the model that answered; the ledger row carries it
  update pipeline.field_enrich_items set model = 'mistralai/mistral-small-3.2-24b-instruct', cost_usd = coalesce(cost_usd, 0) + 0.002 where id = 1;
  assert (select model from pipeline.ai_spend_ledger order by id desc limit 1) = 'mistralai/mistral-small-3.2-24b-instruct';
  -- a later model of the cascade answered a central page: the worker corrects the latest ledger row of that queue row
  update pipeline.central_ai_queue set cost_usd = coalesce(cost_usd, 0) + 0.003 where id = 1;
  n := public.svc_ai_model_answered_v1('central_ai_queue', '1', 'mistralai/mistral-small-3.2-24b-instruct');
  assert n = 1 and (select model from pipeline.ai_spend_ledger where source = 'central_ai_queue' and source_id = '1' order by id desc limit 1) = 'mistralai/mistral-small-3.2-24b-instruct';
  assert public.svc_ai_model_answered_v1('central_ai_queue', '1', 'not/a-model') = 0;
  raise notice 'ok 10 the guard names what pins a model outside the routes; Layer 3 is reported, not wired; the ledger carries the model that answered';
end $$;
