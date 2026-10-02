-- CF-247 (3 Oct 2026, Decision 238). Part 2 of the Settings page functions: the read (Pipeline Operator and above).
-- Every number the Settings page shows, taken from the live object that holds it: cron job commands, Layer 3 profiles
-- and budgets, the Firecrawl provider's billing config (limits only, never a key), the course-page search cap, the
-- admission identities per country, and the last 20 recorded changes.
create or replace function public.admin_pipeline_settings_read()
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_fc record;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  select billing_config into v_fc from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return jsonb_build_object(
    'can_change', security.current_role_rank() >= 6,
    'course_pages', jsonb_build_object(
      'matcher_prepare_universities', (select (regexp_match(command, 'prepare_v1\((\d+),'))[1]::int from cron.job where jobname = 'coverage-ai-match-prepare'),
      'matcher_prepare_courses', (select (regexp_match(command, 'prepare_v1\(\d+,\s*(\d+)\)'))[1]::int from cron.job where jobname = 'coverage-ai-match-prepare'),
      'matcher_items_per_minute', (select (substring(command from ',''(\{.*\})''::jsonb')::jsonb->>'limit')::int from cron.job where jobname = 'coverage-ai-match'),
      'matcher_concurrency', (select (substring(command from ',''(\{.*\})''::jsonb')::jsonb->>'concurrency')::int from cron.job where jobname = 'coverage-ai-match'),
      'search_per_minute', (select (substring(command from ',''(\{.*\})''::jsonb')::jsonb->>'limit')::int from cron.job where jobname = 'course-link-search-worker'),
      'search_monthly_credit_cap', (select monthly_credit_cap from pipeline.course_link_search_settings limit 1),
      'queued', jsonb_build_object('matcher_ready', (select count(*) from pipeline.coverage_ai_match where state = 'ready'),
                                   'matcher_never_offered', (select count(*) from pipeline.coverage_ai_match where state = 'none'),
                                   'searches_queued', (select count(*) from pipeline.course_link_search where state = 'queued')),
      'priority_countries', (select coalesce(jsonb_agg(k.iso_alpha2 order by p.sort), '[]'::jsonb) from pipeline.priority_pins p join ref.countries k on k.id = p.target_id where p.kind = 'country')),
    'reading', jsonb_build_object(
      'read_batch_per_30s', (select (substring(command from ',''(\{.*\})''::jsonb')::jsonb->>'limit')::int from cron.job where jobname = 'coverage-read'),
      'pages_waiting', (select count(*) from pipeline.coverage_course_pages where status = 'bound' and read_status is null)),
    'identity', (select jsonb_object_agg(k.iso_alpha2, jsonb_build_object('active', c.active, 'currency', c.currency_code, 'identities', c.identities, 'approved_ref', c.approved_ref))
                   from pipeline.coverage_admission_countries c join ref.countries k on k.id = c.country_id),
    'layer3', jsonb_build_object(
      'budgets', (select jsonb_agg(jsonb_build_object('task_class', task_class, 'daily_usd_max', daily_usd_max, 'credit_floor_usd', credit_floor_usd, 'route_mode', route_mode) order by task_class) from pipeline.layer3_route_budget),
      'route_limit', (select (substring(command from ',''(\{.*\})''::jsonb')::jsonb->>'limit')::int from cron.job where jobname = 'layer3-intake-route'),
      'route_concurrency', (select (substring(command from ',''(\{.*\})''::jsonb')::jsonb->>'concurrency')::int from cron.job where jobname = 'layer3-intake-route'),
      'requests_per_day', (select min(requests_per_day) from pipeline.layer3_model_profiles where enabled and retired_at is null and code ~ '^openrouter-(intake|english)-l3[cr]-'),
      'profiles', (select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'model', p.model_identifier, 'tasks', p.allowed_task_classes, 'prompt_version', p.prompt_profile_version,
                       'prompt_hash', md5(coalesce(p.prompt_system, '')), 'prompt_chars', length(coalesce(p.prompt_system, '')), 'requests_per_day', p.requests_per_day,
                       'enabled', p.enabled, 'paused', p.paused, 'holdout', p.holdout_qualification,
                       'tiers', (select jsonb_agg(jsonb_build_object('task', t.task_class, 'tier', t.tier_no, 'active', t.active, 'final', t.is_final) order by t.task_class, t.tier_no) from pipeline.layer3_route_tiers t where t.profile_id = p.id)) order by p.code), '[]'::jsonb)
                     from pipeline.layer3_model_profiles p where p.retired_at is null),
      'spent_today_usd', (select jsonb_object_agg(task_class, round(usd, 3)) from (select task_class, sum(estimated_cost_usd) usd from pipeline.layer3_interpretations where created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' group by 1) z)),
    'budgets', jsonb_build_object(
      'firecrawl_monthly_limit', (v_fc.billing_config->>'monthly_vendor_units_limit')::int,
      'firecrawl_stop_at_remaining', (v_fc.billing_config->>'stop_at_vendor_units_remaining')::int,
      'firecrawl_used_this_month', (select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= date_trunc('month', now())),
      'firecrawl_by_purpose', (select jsonb_object_agg(purpose, u) from (select purpose, sum(units) u from pipeline.coverage_vendor_usage where at >= date_trunc('month', now()) group by 1) z),
      'openrouter', (select jsonb_build_object('remaining_usd', remaining_usd, 'observed_at', observed_at) from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1)),
    'recent_changes', (select coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'area', area, 'action', action, 'target', target) order by created_at desc), '[]'::jsonb)
                         from (select * from pipeline.admin_control_events where area in ('settings', 'layer3', 'automations', 'course_link_search', 'requeue') order by created_at desc limit 20) e));
end $f$;
revoke all on function public.admin_pipeline_settings_read() from public, anon;
grant execute on function public.admin_pipeline_settings_read() to authenticated;
