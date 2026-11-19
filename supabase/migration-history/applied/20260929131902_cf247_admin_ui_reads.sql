-- CF-247 admin UI simplification (v2.15.107): two new read-only admin reads.
--   public.admin_layer3_operations(jsonb)      Layer 3 routing, models and profiles, test results and spend.
--   public.admin_source_comparison(text,uuid)  Provider page values next to the government / regulator values
--                                              for one scholarship (Study Australia) or one course (CRICOS).
-- Nothing is written. No existing function is replaced, so no checksum guard is needed; the guard below
-- stops this migration if an object with the same name already exists (for example created by another worker),
-- so it never silently overwrites someone else's definition.
-- Optional profile fields (retired_at, last_validation_result.retired, holdout_qualification) are read through
-- to_jsonb(row), so this read keeps working whether or not those columns exist.

do $guard$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
              where (n.nspname,p.proname) in (('security','admin_layer3_operations_read_v1'),('public','admin_layer3_operations'),
                                               ('security','admin_source_comparison_read_v1'),('public','admin_source_comparison'))) then
    raise exception 'cf247_admin_ui_reads: a function with one of these names already exists; re-read live before applying';
  end if;
end
$guard$;

create function security.admin_layer3_operations_read_v1(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, pipeline, security, auth
as $fn$
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
$fn$;

create function security.admin_source_comparison_read_v1(p_entity_type text, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, catalogue, pipeline, scholarship, security, auth
as $fn$
declare
  v_provider jsonb; v_gov jsonb; v_current jsonb; v_weeks numeric; v_reg jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  if p_entity_type = 'scholarship' then
    if not exists (select 1 from scholarship.scholarships where id = p_id) then return null; end if;

    select jsonb_build_object(
             'url', coalesce(sp.final_url, sp.url), 'read_at', sp.read_at, 'read_status', sp.read_status,
             'url_source', sp.url_source, 'evidence_id', sp.evidence_id, 'heading', sp.facts->>'h1',
             'value', sp.facts->'value', 'deadline', sp.facts->'deadline', 'levels', sp.facts->'levels',
             'international', sp.facts->'international')
      into v_provider
      from pipeline.scholarship_pages sp
     where sp.scholarship_id = p_id
     order by (sp.facts is not null) desc, sp.read_at desc nulls last
     limit 1;
    if v_provider is null then
      select jsonb_build_object('url', i.identifier_value, 'evidence_id', i.evidence_id)
        into v_provider from scholarship.identifiers i
       where i.scholarship_id = p_id and i.scheme = 'first_party_detail_url' and coalesce(i.status,'active') = 'active'
       order by i.is_primary desc, i.created_at desc limit 1;
    end if;

    with urls as (
      select s.source_url u from scholarship.scholarships s where s.id = p_id and s.source_url ilike '%studyaustralia.gov.au%'
      union select c.before_value->>'source_url' from pipeline.scholarship_sweep_changes c
        where c.scholarship_id = p_id and c.before_value->>'source_url' ilike '%studyaustralia.gov.au%'
    ), ids as (
      select i.identifier_value v from scholarship.identifiers i where i.scholarship_id = p_id and i.scheme = 'study_australia_scholarship_id'
    ), rec as (
      select r.* from pipeline.scholarship_source_records r
       where r.source_record_id in (select v from ids) or r.source_record_url in (select u from urls)
       order by r.observed_at desc nulls last limit 1
    )
    select jsonb_build_object(
             'url', coalesce(rec.source_record_url, (select u from urls limit 1)),
             'observed_at', rec.observed_at, 'evidence_id', rec.evidence_id,
             'value_text', rec.payload->>'award_value_text',
             'amount', rec.payload->'cycles'->0->'award_tiers'->0->'amount',
             'currency', rec.payload->'cycles'->0->'award_tiers'->0->>'currency_code',
             'closing_date', coalesce(rec.payload->>'application_close_date', rec.payload->>'close_date', rec.payload->'cycles'->0->'windows'->0->>'closes_at'),
             'closing_text', coalesce(rec.payload->>'application_close_text', rec.payload->'cycles'->0->'metadata'->>'source_closing_text'),
             'levels_text', coalesce(rec.payload->>'level_of_study_text', rec.payload->'cycles'->0->'metadata'->>'source_level_of_study'),
             'study_levels', rec.payload->'study_levels')
      into v_gov
      from (select 1) one left join rec on true
     where rec.id is not null or exists (select 1 from urls);

    select jsonb_build_object('value_text', s.award_value_text, 'source_url', s.source_url,
             'closing_date', (select min(w.closes_at) from scholarship.application_windows w where w.scholarship_id = s.id))
      into v_current from scholarship.scholarships s where s.id = p_id;

    return jsonb_build_object('entity_type','scholarship','id',p_id,
      'provider', v_provider, 'government', v_gov, 'current', v_current);
  end if;

  if p_entity_type = 'course' then
    if not exists (select 1 from catalogue.courses where id = p_id) then return null; end if;
    select case when c.duration_unit = 'weeks' then c.duration_value end into v_weeks from catalogue.courses c where c.id = p_id;

    select jsonb_build_object(
             'cricos_code', (select o.registration_code from catalogue.course_regulatory_observations o
                               where o.course_id = p_id and o.scheme = 'cricos' order by (o.valid_to is null) desc, o.observed_at desc nulls last limit 1),
             'tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'basis', f.basis, 'fee_year', f.fee_year,
                                   'evidence_id', f.evidence_id, 'verified_at', f.last_verified_at,
                                   'per_year_estimate', case when v_weeks > 0 and f.basis = 'registered_total_course' then round(f.amount / (v_weeks / 52.0)) end)
                           from catalogue.course_fees f
                          where f.course_id = p_id and f.fee_type = 'tuition' and coalesce(f.status,'active') = 'active'
                          order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1),
             'duration', (select jsonb_build_object('value', c.duration_value, 'unit', c.duration_unit) from catalogue.courses c where c.id = p_id and c.duration_value is not null),
             'campuses', (select coalesce(jsonb_agg(distinct cp.name order by cp.name), '[]'::jsonb)
                            from catalogue.course_campuses cc join catalogue.campuses cp on cp.id = cc.campus_id where cc.course_id = p_id))
      into v_reg;

    select jsonb_build_object(
             'url', coalesce((select g.url from pipeline.coverage_course_pages g where g.course_id = p_id and g.status = 'bound' limit 1),
                             (select l.url from catalogue.course_links l where l.course_id = p_id and l.link_type = 'official_course' and coalesce(l.status,'active') = 'active'
                               order by (l.audience = 'international') desc, l.last_verified_at desc nulls last limit 1)),
             'read_at', (select g.read_at from pipeline.coverage_course_pages g where g.course_id = p_id and g.status = 'bound' limit 1),
             'tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'basis', f.basis, 'fee_year', f.fee_year,
                                   'evidence_id', f.evidence_id, 'verified_at', f.last_verified_at, 'source_type', s.source_type)
                           from catalogue.course_fees f left join pipeline.sources s on s.id = f.source_id
                          where f.course_id = p_id and f.fee_type = 'provider_current_tuition' and coalesce(f.status,'active') = 'active'
                          order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1),
             'duration', null, 'campuses', null)
      into v_provider;

    return jsonb_build_object('entity_type','course','id',p_id,'provider', v_provider, 'regulator', v_reg);
  end if;

  raise exception 'unsupported entity type %', p_entity_type using errcode='22023';
end
$fn$;

create function public.admin_layer3_operations(p_args jsonb default '{}'::jsonb)
returns jsonb language sql stable security invoker set search_path = pg_catalog, security
as $fn$ select security.admin_layer3_operations_read_v1(coalesce(p_args,'{}'::jsonb)) $fn$;

create function public.admin_source_comparison(p_entity_type text, p_id uuid)
returns jsonb language sql stable security invoker set search_path = pg_catalog, security
as $fn$ select security.admin_source_comparison_read_v1(p_entity_type, p_id) $fn$;

revoke all on function security.admin_layer3_operations_read_v1(jsonb) from public, anon;
revoke all on function security.admin_source_comparison_read_v1(text,uuid) from public, anon;
revoke all on function public.admin_layer3_operations(jsonb) from public, anon;
revoke all on function public.admin_source_comparison(text,uuid) from public, anon;
grant execute on function security.admin_layer3_operations_read_v1(jsonb) to authenticated, service_role;
grant execute on function security.admin_source_comparison_read_v1(text,uuid) to authenticated, service_role;
grant execute on function public.admin_layer3_operations(jsonb) to authenticated, service_role;
grant execute on function public.admin_source_comparison(text,uuid) to authenticated, service_role;
