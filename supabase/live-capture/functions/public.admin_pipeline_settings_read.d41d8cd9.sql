CREATE OR REPLACE FUNCTION public.admin_pipeline_settings_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_fc record;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  select billing_config into v_fc from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return jsonb_build_object(
    'can_change', security.current_role_rank() >= 6,
    'course_pages', jsonb_build_object(
      -- v2.15.269: job sizes are in the settings register (Pipeline settings › Job sizes)
      'matcher_prepare_universities', security.pipeline_num_v1('batch.ai_match_prepare_universities', null)::int,
      'matcher_prepare_courses', security.pipeline_num_v1('batch.ai_match_prepare_courses', null)::int,
      'matcher_items_per_minute', security.pipeline_num_v1('batch.ai_match', null)::int,
      'matcher_concurrency', security.pipeline_num_v1('concurrency.ai_match', null)::int,
      'search_per_minute', security.pipeline_num_v1('batch.link_search_worker', null)::int,
      'search_monthly_credit_cap', (select monthly_credit_cap from pipeline.course_link_search_settings limit 1),
      'queued', jsonb_build_object('matcher_ready', (select count(*) from pipeline.coverage_ai_match where state = 'ready'),
                                   'matcher_never_offered', (select count(*) from pipeline.coverage_ai_match where state = 'none'),
                                   'searches_queued', (select count(*) from pipeline.course_link_search where state = 'queued')),
      'priority_countries', (select coalesce(jsonb_agg(k.iso_alpha2 order by p.sort), '[]'::jsonb) from pipeline.priority_pins p join ref.countries k on k.id = p.target_id where p.kind = 'country')),
    'reading', jsonb_build_object(
      'read_batch_per_30s', security.pipeline_num_v1('batch.coverage_read', null)::int,
      'pages_waiting', (select count(*) from pipeline.coverage_course_pages where status = 'bound' and read_status is null)),
    'identity', (select jsonb_object_agg(k.iso_alpha2, jsonb_build_object('active', c.active, 'currency', c.currency_code, 'identities', c.identities, 'approved_ref', c.approved_ref))
                   from pipeline.coverage_admission_countries c join ref.countries k on k.id = c.country_id),
    -- v2.15.269: the Layer 3 block is removed (Layer 3 retired 12 Oct 2026)
    'budgets', jsonb_build_object(
      'firecrawl_monthly_limit', (v_fc.billing_config->>'monthly_vendor_units_limit')::int,
      'firecrawl_stop_at_remaining', (v_fc.billing_config->>'stop_at_vendor_units_remaining')::int,
      'firecrawl_used_this_month', (select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= date_trunc('month', now())),
      'firecrawl_by_purpose', (select jsonb_object_agg(purpose, u) from (select purpose, sum(units) u from pipeline.coverage_vendor_usage where at >= date_trunc('month', now()) group by 1) z),
      'openrouter', (select jsonb_build_object('remaining_usd', remaining_usd, 'observed_at', observed_at) from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1)),
    'recent_changes', (select coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'area', area, 'action', action, 'target', target) order by created_at desc), '[]'::jsonb)
                         from (select * from pipeline.admin_control_events where area in ('settings', 'layer3', 'automations', 'course_link_search', 'requeue') order by created_at desc limit 20) e));
end $function$
