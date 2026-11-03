CREATE OR REPLACE FUNCTION security.course_entry_programme_v1(p_can_batch boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cost numeric := security.course_entry_cost_v1(); v_rows jsonb; v_bal numeric; v_floor numeric;
begin
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  with el as (select * from security.course_entry_eligible_v1()),
  scope as (select (e.v)::uuid pid, e.o from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_providers'), '[]'::jsonb)) with ordinality e(v, o)),
  it as (select f.course_id, bool_or(f.state in ('queued', 'waiting', 'ai', 'leased')) waiting, bool_or(f.state = 'review') review,
                bool_or(f.state = 'filled') filled, bool_or(f.state = 'skipped') skipped, sum(coalesce(f.cost_usd, 0)) cost
           from pipeline.field_enrich_items f where f.field = 'entry_requirements' group by f.course_id),
  rq as (select x.course_id, count(*) filter (where x.status = 'proposed') proposed, count(*) filter (where x.status = 'active') active,
                count(*) filter (where x.status in ('inactive', 'unverified')) held from catalogue.course_entry_requirements x group by x.course_id),
  per as (select scope.pid, scope.o, coalesce(p.display_name, p.canonical_name) provider_name, k.iso_alpha2 country,
                 count(el.course_id) eligible,
                 count(el.course_id) filter (where it.course_id is not null and not it.waiting) read,
                 count(el.course_id) filter (where it.waiting) waiting,
                 count(el.course_id) filter (where coalesce(rq.proposed, 0) > 0) in_layer4,
                 coalesce(sum(rq.proposed), 0) proposed_rows,
                 count(el.course_id) filter (where coalesce(rq.active, 0) > 0) admitted,
                 coalesce(sum(rq.active), 0) active_rows,
                 count(el.course_id) filter (where it.course_id is not null and not it.waiting and coalesce(rq.proposed, 0) = 0 and coalesce(rq.active, 0) = 0) no_rows,
                 count(el.course_id) filter (where it.course_id is null) remaining,
                 coalesce(sum(it.cost), 0) spent
            from scope join catalogue.providers p on p.id = scope.pid left join ref.countries k on k.id = p.country_id
            left join el on el.provider_id = scope.pid left join it on it.course_id = el.course_id left join rq on rq.course_id = el.course_id
           group by scope.pid, scope.o, p.display_name, p.canonical_name, k.iso_alpha2)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', pid, 'provider_name', provider_name, 'country', country, 'eligible', eligible, 'read', read, 'waiting', waiting,
           'in_layer4', in_layer4, 'proposed_rows', proposed_rows, 'admitted', admitted, 'active_rows', active_rows, 'no_rows', no_rows, 'remaining', remaining,
           'spent_usd', round(spent, 4), 'estimate_remaining_usd', round(remaining * v_cost, 2)) order by o), '[]'::jsonb) into v_rows from per;
  return jsonb_build_object('providers', v_rows, 'cost_per_course_usd', round(v_cost, 5),
    'cost_basis', case when (select count(*) from pipeline.field_enrich_items f where f.field = 'entry_requirements' and coalesce(f.cost_usd, 0) > 0) >= 20 then 'measured' else 'setting' end,
    'batch_size', security.pipeline_num_v1('entry.course_batch_size', 50)::int, 'balance_usd', v_bal, 'floor_usd', v_floor,
    'countries', coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '["AU"]'::jsonb),
    'ai_allowed', security.ai_use_allowed_v1('enrich_fields'),
    'waiting', (select count(*) from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')),
    'can_batch', p_can_batch);
end $function$
