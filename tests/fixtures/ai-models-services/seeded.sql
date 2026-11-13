-- CF-247 AI models and services, round 4 (Platform Admin review 13 Nov 2026): the state right after the migrations, before the fixture qualifies
-- more models for the older blocks. Each block raises on a failure.
\set ON_ERROR_STOP 1
set client_min_messages = notice;
do $$  -- A qualification: only a qualified model is handed out; what runs today keeps running; the entry readers stay held
declare r jsonb; w jsonb; n0 int;
begin
  assert (select string_agg(service_code || ':' || model_code || ':' || status || case when provisional then ':provisional' else '' end, ' ' order by service_code, model_code) from pipeline.ai_route_qualifications where status = 'qualified')
         = 'adapter_builder:qwen3-30b:qualified calendar_reading:qwen3-30b:qualified:provisional central_english_policy:qwen3-30b:qualified:provisional course_description:qwen3-30b:qualified:provisional course_matching:qwen3-30b:qualified course_other_fields:qwen3-30b:qualified:provisional fee_reader:qwen3-30b:qualified:provisional provider_description:qwen3-30b:qualified:provisional scholarship_eligibility:qwen3-30b:qualified scholarship_extraction:qwen3-30b:qualified',
         (select string_agg(service_code || ':' || model_code || ':' || status, ' ' order by service_code, model_code) from pipeline.ai_route_qualifications);
  assert (select count(*) from pipeline.ai_route_qualifications where status = 'qualified' and (evidence is null or length(evidence) < 20)) = 0, 'every qualification cites its evidence';
  r := security.ai_route_v1('course_entry_requirements');
  -- round 5: a service with no qualified model is seeded switched off
  assert (select string_agg(service_code, ' ' order by service_code) from pipeline.ai_service_routes where not enabled) = 'course_entry_requirements entry_matrices entry_requirements_v2_shadow ops_diagnosis page_identity';
  assert (r->>'held')::boolean and r->>'held_kind' = 'off' and r->>'would_hold_kind' = 'off' and r->'model' = 'null'::jsonb and jsonb_array_length(r->'skipped') = 2 and r#>>'{skipped,0,why}' = 'not qualified for this service', r::text;
  assert (select bool_and(security.ai_route_v1(s)->>'held_kind' = 'off' and security.ai_route_v1(s)->'model' = 'null'::jsonb) from unnest(array['entry_matrices', 'ops_diagnosis', 'entry_requirements_v2_shadow', 'page_identity']) s);
  -- round 5 (second QA, blocker 1): recording a qualification switches nothing on. Before: no entry item is handed out
  perform set_config('fx.role', 'service_role', true);
  w := public.svc_enrich_ai_next(10);
  assert w->'held' ? 'course_entry_requirements' and coalesce(w#>>'{entry,model}', '') = '', w::text;
  n0 := (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements' and state <> 'ai');
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  perform set_config('fx.uid', '00000000-0000-0000-0000-0000000000a1', true); perform set_config('fx.rank', '5', true);
  begin perform public.admin_ai_route_set_v1('course_entry_requirements', array['qwen3-30b', 'mistral-small-3.2'], 5, null, true, 'fixture: switch on'); assert false, 'switched on with no qualified model';
  exception when raise_exception then assert sqlerrm = 'this service cannot be switched on yet: no model in its cascade is qualified for it', sqlerrm; end;
  perform set_config('fx.rank', '6', true);
  perform public.admin_ai_qualification_set_v1('course_entry_requirements', 'qwen3-30b', 'fixture: 48 of 50 on the entry sample', 'fixture run');
  assert not (select enabled from pipeline.ai_service_routes where service_code = 'course_entry_requirements'), 'the qualification left the switch alone';
  r := security.ai_route_v1('course_entry_requirements');
  assert (r->>'held')::boolean and r->>'held_kind' = 'off' and r->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507', r::text;
  w := public.svc_enrich_ai_next(10);
  assert w->'held' ? 'course_entry_requirements', 'qualified, still switched off: still held';
  assert (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements' and state <> 'ai') = 0, 'qualified, still switched off: no entry item is handed out';
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  -- switching on is its own step: rank 5, with a reason, logged
  perform set_config('fx.rank', '5', true);
  perform public.admin_ai_route_set_v1('course_entry_requirements', array['qwen3-30b', 'mistral-small-3.2'], 5, null, true, 'fixture: switch on');
  assert (select detail#>>'{before,enabled}' || '>' || (detail#>>'{after,enabled}') || '|' || (detail->>'reason') from pipeline.admin_control_events where action = 'route_set' and target = 'course_entry_requirements') = 'false>true|fixture: switch on';
  w := public.svc_enrich_ai_next(10);
  assert not (w->'held' ? 'course_entry_requirements') and (select count(*) from pipeline.field_enrich_items where field = 'entry_requirements' and state <> 'ai') > 0, w::text;
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  -- back to the seeded state for the next blocks
  perform set_config('fx.rank', '6', true);
  perform public.admin_ai_qualification_set_v1('course_entry_requirements', 'qwen3-30b', null, 'fixture: back', 'unqualified');
  update pipeline.ai_service_routes set enabled = false, changed_by = null where service_code = 'course_entry_requirements';
  delete from pipeline.admin_control_events where target like 'course_entry_requirements%';
  -- a model that is not qualified for the service cannot be added to its cascade from the page
  perform set_config('fx.rank', '5', true);
  begin perform public.admin_ai_route_set_v1('fee_reader', array['qwen3-30b', 'mistral-small-3.2'], 5, null, null, 'fixture: add a fallback'); assert false, 'an unqualified model was added';
  exception when raise_exception then assert sqlerrm = 'not qualified for this service: mistral-small-3.2 (the Platform Admin records a qualification first)', sqlerrm; end;
  assert (select bool_and(security.ai_route_v1(s)->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507' and not (security.ai_route_v1(s)->>'held')::boolean)
            from unnest(array['course_description', 'course_other_fields', 'fee_reader', 'calendar_reading', 'central_english_policy', 'provider_description', 'scholarship_extraction', 'scholarship_eligibility', 'course_matching', 'adapter_builder']) s), 'what runs today keeps running';
  -- an allowed model added to a cascade is skipped until it is qualified; qualifying it hands it out, in cascade order
  update pipeline.ai_service_routes set cascade = array['mistral-small-3.2', 'qwen3-30b'] where service_code = 'fee_reader';
  r := security.ai_route_v1('fee_reader');
  assert r->>'model' = 'qwen/qwen3-30b-a3b-instruct-2507' and jsonb_array_length(r->'models') = 1 and r->'skipped' = '[{"code": "mistral-small-3.2", "why": "not qualified for this service"}]'::jsonb, r::text;
  perform set_config('fx.uid', '00000000-0000-0000-0000-0000000000a1', true); perform set_config('fx.rank', '5', true);
  begin perform public.admin_ai_qualification_set_v1('fee_reader', 'mistral-small-3.2', 'fixture: 40 of 41 on the fee sample', 'fixture'); assert false, 'rank 5 qualified a model';
  exception when insufficient_privilege then null; end;
  perform set_config('fx.rank', '6', true);
  begin perform public.admin_ai_qualification_set_v1('fee_reader', 'mistral-small-3.2', 'short', 'fixture'); assert false, 'qualified without evidence';
  exception when raise_exception then null; end;
  perform public.admin_ai_qualification_set_v1('fee_reader', 'mistral-small-3.2', 'fixture: 40 of 41 on the fee sample', 'fixture run');
  r := security.ai_route_v1('fee_reader');
  assert r->>'model' = 'mistralai/mistral-small-3.2-24b-instruct' and jsonb_array_length(r->'models') = 2 and r->'skipped' = '[]'::jsonb, r::text;
  assert (select detail->>'after' || '|' || (detail->>'reason') from pipeline.admin_control_events where action = 'route_qualification') = 'qualified|fixture run';
  assert (select enabled from pipeline.ai_service_routes where service_code = 'fee_reader'), 'a qualification switches nothing';
  perform public.admin_ai_qualification_set_v1('fee_reader', 'mistral-small-3.2', null, 'fixture: back', 'unqualified');
  update pipeline.ai_service_routes set cascade = array['qwen3-30b'] where service_code = 'fee_reader';
  -- a service whose call uses one model: one model is handed out and a second cannot be saved
  assert (select string_agg(service_code || '=' || migration_state, ' ' order by service_code) from pipeline.ai_service_routes where migration_state <> 'routed')
         = 'adapter_builder=routed_single entry_matrices=routed_single ops_diagnosis=routed_single page_identity=not_migrated provider_description=routed_single scholarship_eligibility=routed_single';
  begin perform public.admin_ai_route_set_v1('provider_description', array['qwen3-30b', 'mistral-small-3.2'], 1, null, null, 'fixture'); assert false, 'a second model was saved on a single-model service';
  exception when raise_exception then assert sqlerrm = 'this service uses one model: a fallback is not available for it yet', sqlerrm; end;
  raise notice 'ok A only a qualified model is handed out; what runs today keeps running; the entry readers stay held; a single-model service refuses a second model';
end $$;

do $$  -- B the ceiling and the caps follow the existing OpenRouter mode: Observe reports, Stop enforces; the migration changed neither mode nor figures
declare r jsonb; w jsonb;
begin
  assert (select enforcement from pipeline.platform_toolsets where key = 'openrouter') = 'observe', 'the mode is as it was';
  assert (select value from pipeline.platform_toolset_settings where key = 'budgets.ai_daily_ceiling_usd') = '14'::jsonb;
  update pipeline.platform_toolset_settings set value = '0.5' where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd';  -- today's fixture spend is over it
  r := security.ai_route_v1('course_description');
  assert not (r->>'held')::boolean and r->'held_kind' = 'null'::jsonb and (r->>'would_hold')::boolean and r->>'would_hold_kind' = 'ceiling' and not (r->>'enforcing')::boolean and r->>'mode' = 'observe', r::text;
  perform set_config('fx.role', 'service_role', true);
  w := public.svc_enrich_ai_next(10);
  assert jsonb_array_length(w->'pages') > 0 and w->'held' ? 'course_entry_requirements' and not (w->'held' ? 'course_description'), 'Observe only: the ceiling stops no hand-out';
  update pipeline.field_enrich_items set state = 'ai', attempts = 0, leased_until = null;
  update pipeline.platform_toolsets set enforcement = 'stop' where key = 'openrouter';
  r := security.ai_route_v1('course_description');
  assert (r->>'held')::boolean and r->>'held_kind' = 'ceiling' and (r->>'enforcing')::boolean and (r->>'on_demand_exempt')::boolean, r::text;
  assert public.svc_enrich_ai_next(10)->'pages' = '[]'::jsonb, 'Stop at limits: the ceiling holds';
  update pipeline.platform_toolsets set enforcement = 'observe' where key = 'openrouter';
  update pipeline.platform_toolset_settings set value = '14' where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd';
  raise notice 'ok B Observe only: the ceiling and caps are reported (would_hold) and stop nothing; Stop at limits: they hold';
end $$;

do $$  -- C an unknown or stale balance holds everything in both modes, on-demand included; the credit floor too
declare r jsonb; v_since numeric;
begin
  assert (select value from pipeline.platform_toolset_settings where toolset_key = 'openrouter' and key = 'balance_max_age_minutes') = '90'::jsonb;
  insert into pipeline.on_demand_requests (provider_ids, expires_at) values (array['00000000-0000-0000-0000-00000000b001'::uuid], now() + interval '1 hour');
  update pipeline.layer3_openrouter_observations set observed_at = now() - interval '91 minutes' where kind = 'credits';
  r := security.ai_route_v1('course_description');
  assert (r->>'held')::boolean and r->>'held_kind' = 'balance_stale' and r->>'held_reason' like 'the last OpenRouter balance reading is 91 minutes old (limit 90, %' and not (r->>'on_demand_exempt')::boolean and not (r->>'enforcing')::boolean, r::text;
  perform set_config('fx.role', 'service_role', true);
  assert public.svc_enrich_ai_next(10)->'pages' = '[]'::jsonb and public.svc_central_ai_next(6) = '[]'::jsonb and public.svc_coverage_ai_match_next(5) = '[]'::jsonb, 'stale: nothing is handed out, on-demand included, in Observe only';
  update pipeline.layer3_openrouter_observations set observed_at = now() - interval '89 minutes' where kind = 'credits';
  assert not (security.ai_route_v1('course_description')->>'held')::boolean;
  update pipeline.layer3_openrouter_observations set kind = 'fx_hidden' where kind = 'credits';
  r := security.ai_route_v1('course_description');
  assert (r->>'held')::boolean and r->>'held_kind' = 'balance_unknown' and r->>'held_reason' = 'no OpenRouter balance reading: AI work is held until one is recorded', r::text;
  assert public.svc_enrich_ai_next(10)->'pages' = '[]'::jsonb, 'unknown: nothing is handed out';
  update pipeline.layer3_openrouter_observations set kind = 'credits', observed_at = now(), remaining_usd = 0.5 where kind = 'fx_hidden';
  r := security.ai_route_v1('course_description');
  assert r->>'held_kind' = 'credit_floor' and r->>'held_reason' like 'the OpenRouter balance is at or below the credit floor: about US$%' and not (r->>'on_demand_exempt')::boolean, r::text;
  -- round 5: the floor is checked against an estimate, the last reading less the spend recorded since it
  update pipeline.layer3_openrouter_observations set observed_at = now() - interval '30 minutes' where kind = 'credits';
  v_since := (select coalesce(sum(cost_usd), 0) from pipeline.ai_spend_ledger where at > now() - interval '30 minutes');
  assert v_since > 0, 'the fixture has spend after the reading';
  update pipeline.layer3_openrouter_observations set remaining_usd = 0.5 + v_since + 0.1 where kind = 'credits';
  assert not (security.ai_route_v1('course_description')->>'held')::boolean, 'above the floor after the spend since the reading';
  update pipeline.layer3_openrouter_observations set remaining_usd = 0.5 + v_since - 0.01 where kind = 'credits';   -- the reading itself is above the floor
  r := security.ai_route_v1('course_description');
  assert r->>'held_kind' = 'credit_floor' and (r#>>'{balance,usd}')::numeric > 0.5 and (r#>>'{balance,estimated_usd}')::numeric = 0.49 and (r#>>'{balance,spent_since_usd}')::numeric = round(v_since, 4), r::text;
  perform set_config('fx.uid', '00000000-0000-0000-0000-0000000000a1', true); perform set_config('fx.rank', '3', true);
  assert (public.admin_ai_overview_v1()#>>'{openrouter,balance_estimated_usd}')::numeric = 0.49 and (public.admin_ai_overview_v1()#>>'{openrouter,balance_spent_since_usd}')::numeric = round(v_since, 4);
  update pipeline.layer3_openrouter_observations set observed_at = now() where kind = 'credits';
  update pipeline.layer3_openrouter_observations set remaining_usd = 53 where kind = 'credits';
  update pipeline.on_demand_requests set state = 'closed';
  assert not (security.ai_route_v1('course_description')->>'held')::boolean;
  raise notice 'ok C no balance reading, a stale one or the credit floor holds every hand-out in both modes';
end $$;
-- for the older blocks (written before qualification and the mode rule): every allowed model qualified for every service, Stop at limits
insert into pipeline.ai_route_qualifications (service_code, model_code, status, evidence, qualified_at)
select r.service_code, m.code, 'qualified', 'fixture: qualified for the older fixture blocks', now() from pipeline.ai_service_routes r cross join pipeline.ai_model_catalogue m where m.status = 'allowed'
on conflict (service_code, model_code) do update set status = 'qualified', evidence = coalesce(pipeline.ai_route_qualifications.evidence, excluded.evidence);
update pipeline.platform_toolsets set enforcement = 'stop' where key = 'openrouter';
update pipeline.ai_service_routes set enabled = true where not enabled;  -- for the older blocks, written when every route was seeded on
