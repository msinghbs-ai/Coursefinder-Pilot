CREATE OR REPLACE FUNCTION security.admin_layer3_operations_read_v1(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security', 'auth'
AS $function$
declare
  v_days integer := least(greatest(coalesce(nullif(p_args->>'days','')::integer,14),1),60);
  v_today timestamptz := date_trunc('day', now());
  v_profiles jsonb; v_routing jsonb; v_tests jsonb; v_spend jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 3 then
    raise exception 'curator role required' using errcode='42501';
  end if;

  with p as (
    select pr.*, to_jsonb(pr) as j,
           (to_jsonb(pr)->>'retired_at') is not null
             or coalesce((pr.last_validation_result->>'retired')::boolean,false) as is_retired
      from pipeline.layer3_model_profiles pr
  ), usage as (
    select i.profile_id, sum(coalesce(i.external_call_count,0))::bigint calls, coalesce(sum(i.estimated_cost_usd),0) cost
      from pipeline.layer3_interpretations i
     where i.created_at >= v_today and coalesce(i.status,'') <> 'cancelled'
     group by i.profile_id
  ), last_test as (
    select distinct on (b.profile_id) b.profile_id, b.status, b.summary, b.created_at, b.estimated_cost_usd
      from pipeline.layer3_quality_benchmark_runs b
     order by b.profile_id, b.created_at desc
  )
  select coalesce(jsonb_agg(
           (p.j - 'prompt_system' - 'structured_output_schema' - 'deterministic_validators' - 'secret_env_key')
           || jsonb_build_object(
                'is_retired', p.is_retired,
                'qualified', p.enabled and not p.paused and coalesce((p.quality_benchmark->>'pass')::boolean,false) and not p.is_retired,
                'state', case when p.is_retired then 'retired'
                              when p.enabled and not p.paused and coalesce((p.quality_benchmark->>'pass')::boolean,false) then 'active'
                              else 'candidate' end,
                'fallback_code', (select f.code from pipeline.layer3_model_profiles f where f.id = p.fallback_profile_id),
                'calls_today', coalesce(u.calls,0),
                'spend_today_usd', coalesce(u.cost,0),
                'last_test', case when t.profile_id is null then null else jsonb_build_object('status',t.status,'summary',t.summary,'at',t.created_at,'cost_usd',t.estimated_cost_usd) end)
           order by p.is_retired, p.code), '[]'::jsonb)
    into v_profiles
    from p left join usage u on u.profile_id = p.id left join last_test t on t.profile_id = p.id;

  -- Routing: the profile the dispatcher would use for each task class (same rule as layer3_dispatch_headroom_service).
  with p as (
    select pr.*, (to_jsonb(pr)->>'retired_at') is not null
             or coalesce((pr.last_validation_result->>'retired')::boolean,false) as is_retired
      from pipeline.layer3_model_profiles pr
  ), classes as (
    select distinct unnest(allowed_task_classes) task_class from p
    union select distinct task_class from pipeline.layer3_work_items where task_class is not null
  ), active as (
    select c.task_class, a.*
      from classes c
      left join lateral (
        select p.id, p.code, p.model_identifier, p.fallback_profile_id, p.cost_ceiling_usd, p.requests_per_day
          from p
         where c.task_class = any(p.allowed_task_classes) and p.enabled and not p.paused
           and coalesce((p.quality_benchmark->>'pass')::boolean,false) and not p.is_retired
         order by p.updated_at desc, p.id limit 1) a on true
  ), today as (
    select task_class, sum(coalesce(external_call_count,0))::bigint calls, coalesce(sum(estimated_cost_usd),0) cost
      from pipeline.layer3_interpretations
     where created_at >= v_today and coalesce(status,'') <> 'cancelled'
     group by task_class
  ), queue as (
    select task_class,
           count(*) filter (where status in ('pending','reserved','interpreting','validated','admission_pending')) open_items,
           count(*) filter (where status = 'layer4_required') layer4_items
      from pipeline.layer3_work_items group by task_class
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'task_class', a.task_class,
           'status', case when a.id is null then 'no_qualified_model' else 'active' end,
           'active_profile_id', a.id, 'active_code', a.code, 'active_model', a.model_identifier,
           'fallback_code', (select f.code from pipeline.layer3_model_profiles f where f.id = a.fallback_profile_id),
           'fallback_model', (select f.model_identifier from pipeline.layer3_model_profiles f where f.id = a.fallback_profile_id),
           'candidates', (select count(*) from p where a.task_class = any(p.allowed_task_classes) and not p.is_retired),
           'calls_today', coalesce(t.calls,0), 'spend_today_usd', coalesce(t.cost,0),
           'requests_per_day', a.requests_per_day, 'cost_ceiling_usd', a.cost_ceiling_usd,
           'open_items', coalesce(q.open_items,0), 'layer4_items', coalesce(q.layer4_items,0))
           order by (a.id is null), a.task_class), '[]'::jsonb)
    into v_routing
    from active a left join today t on t.task_class = a.task_class left join queue q on q.task_class = a.task_class;

  -- Test results: the latest benchmark runs, scored the same way for every task class.
  with b as (
    select r.*, case when jsonb_typeof(r.provider_case_results)='array' then r.provider_case_results else '[]'::jsonb end pc,
                case when jsonb_typeof(r.control_case_results)='array' then r.control_case_results else '[]'::jsonb end cc
      from pipeline.layer3_quality_benchmark_runs r
     order by r.created_at desc limit 80
  ), scored as (
    select b.*,
      (select count(*) from jsonb_array_elements(b.pc) x) stated_total,
      (select count(*) from jsonb_array_elements(b.pc) x
        where coalesce((x->>'layer3_exact')::boolean, (x->>'semantic_result')::boolean and (x->>'valid')::boolean, false)) stated_exact,
      (select count(*) from jsonb_array_elements(b.pc) x
        where x->>'layer3_status' = 'not_stated' or (x ? 'candidate_value' and jsonb_typeof(x->'candidate_value') = 'null')) withheld,
      (select count(*) from jsonb_array_elements(b.pc) x
        where coalesce((x->>'layer3_valid')::boolean,(x->>'valid')::boolean,false)
          and not coalesce((x->>'layer3_exact')::boolean, (x->>'semantic_result')::boolean and (x->>'valid')::boolean, false)
          and coalesce(x->>'layer3_status','') <> 'not_stated'
          and not (x ? 'candidate_value' and jsonb_typeof(x->'candidate_value') = 'null'))
      + (select count(*) from jsonb_array_elements(b.cc) x
        where (jsonb_typeof(x->'invented_months')='array' and jsonb_array_length(x->'invented_months') > 0)
           or (coalesce(x->>'expected_outcome','') like '%abstention%' and x ? 'candidate_value' and jsonb_typeof(x->'candidate_value') <> 'null')) wrong_admitted,
      (select count(*) from jsonb_array_elements(b.cc) x) control_total
      from b
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'profile_id', s.profile_id,
           'profile_code', (select m.code from pipeline.layer3_model_profiles m where m.id = s.profile_id),
           'model', s.configured_model, 'status', s.status,
           'stated_total', s.stated_total, 'stated_exact', s.stated_exact, 'withheld', s.withheld,
           'wrong_admitted', s.wrong_admitted, 'control_total', s.control_total,
           'calls', s.external_call_count, 'cost_usd', s.estimated_cost_usd,
           'summary', s.summary, 'at', coalesce(s.completed_at, s.created_at))
           order by s.created_at desc), '[]'::jsonb)
    into v_tests from scored s;

  -- Spend per day and profile: live interpretation calls plus test (benchmark) calls.
  with live as (
    select date_trunc('day', created_at)::date d, profile_id, sum(coalesce(external_call_count,0))::bigint calls, coalesce(sum(estimated_cost_usd),0) cost
      from pipeline.layer3_interpretations
     where created_at >= v_today - make_interval(days => v_days - 1) and coalesce(status,'') <> 'cancelled'
     group by 1,2
  ), test as (
    select date_trunc('day', created_at)::date d, profile_id, sum(coalesce(external_call_count,0))::bigint calls, coalesce(sum(estimated_cost_usd),0) cost
      from pipeline.layer3_quality_benchmark_runs
     where created_at >= v_today - make_interval(days => v_days - 1)
     group by 1,2
  ), keys as (select d, profile_id from live union select d, profile_id from test)
  select coalesce(jsonb_agg(jsonb_build_object(
           'day', k.d, 'profile_id', k.profile_id, 'profile_code', m.code, 'model', m.model_identifier,
           'live_calls', coalesce(l.calls,0), 'live_cost_usd', coalesce(l.cost,0),
           'test_calls', coalesce(t.calls,0), 'test_cost_usd', coalesce(t.cost,0),
           'cost_ceiling_usd', m.cost_ceiling_usd, 'requests_per_day', m.requests_per_day)
           order by k.d desc, m.code), '[]'::jsonb)
    into v_spend
    from keys k
    left join live l on l.d = k.d and l.profile_id is not distinct from k.profile_id
    left join test t on t.d = k.d and t.profile_id is not distinct from k.profile_id
    left join pipeline.layer3_model_profiles m on m.id = k.profile_id;

  return jsonb_build_object('generated_at', now(), 'days', v_days,
    'profiles', v_profiles, 'routing', v_routing, 'tests', v_tests, 'spend', v_spend);
end
$function$
