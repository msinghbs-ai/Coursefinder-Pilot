-- CF-247 (3 Oct 2026, 10:00 AEST). Platform Admin, 09:26: "All these hardcoded values requested multiple times need to be
-- reflected in UI; UI needs to provide complete control … Plan what step in data pipeline or admin menu these settings
-- and variables, throttling etc belong to and reflect them asap." Decision 238.
-- One read and one write for the Settings page (Platform Admin writes; Pipeline Operator and above read). Each key
-- maps to the live object that holds the value today — cron job commands, Layer 3 profiles and budgets, the Firecrawl
-- provider's billing config, the course-page search cap, the admission identities per country — so a change made
-- here is exactly the change a migration made before, with an audit row (pipeline.admin_control_events) every time.
-- Numbers apply at once. Prompts and rules are listed with their version and hash and are not edited here (they
-- change as versions, tested on the holdout, switched on separately — Decision 238).
create or replace function security.pipeline_setting_cron_arg(p_jobname text, p_key text, p_value int)
returns void language plpgsql security definer set search_path to '' as $f$
declare v_cmd text; v_json text; v_new text; v_jobid bigint;
begin
  select jobid, command into v_jobid, v_cmd from cron.job where jobname = p_jobname;
  if v_jobid is null then raise exception 'job % not found', p_jobname; end if;
  -- the command is: select pipeline.svc_pilot_submit_nonce('<fn>','{...}'::jsonb)
  v_json := substring(v_cmd from ',''(\{.*\})''::jsonb');
  if v_json is null then raise exception 'job % has no JSON body', p_jobname; end if;
  v_new := jsonb_set(v_json::jsonb, array[p_key], to_jsonb(p_value), true)::text;
  perform cron.alter_job(job_id := v_jobid, command := replace(v_cmd, '''' || v_json || '''', '''' || v_new || ''''));
end $f$;
revoke all on function security.pipeline_setting_cron_arg(text, text, int) from public, anon, authenticated;

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

create or replace function public.admin_pipeline_settings_write(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v int; v_n numeric; v_txt text; v_before jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  v_before := public.admin_pipeline_settings_read();
  case p_key
    when 'course_pages.matcher_prepare_universities' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 500 then raise exception 'between 1 and 500'; end if;
      perform cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-ai-match-prepare'),
        command := format('select security.coverage_ai_match_prepare_v1(%s, %s)', v, coalesce((v_before#>>'{course_pages,matcher_prepare_courses}')::int, 1000)));
    when 'course_pages.matcher_prepare_courses' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 5000 then raise exception 'between 1 and 5,000'; end if;
      perform cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-ai-match-prepare'),
        command := format('select security.coverage_ai_match_prepare_v1(%s, %s)', coalesce((v_before#>>'{course_pages,matcher_prepare_universities}')::int, 200), v));
    when 'course_pages.matcher_items_per_minute' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 200 then raise exception 'between 1 and 200'; end if;
      perform security.pipeline_setting_cron_arg('coverage-ai-match', 'limit', v);
    when 'course_pages.matcher_concurrency' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 24 then raise exception 'between 1 and 24'; end if;
      perform security.pipeline_setting_cron_arg('coverage-ai-match', 'concurrency', v);
    when 'course_pages.search_per_minute' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 120 then raise exception 'between 1 and 120'; end if;
      perform security.pipeline_setting_cron_arg('course-link-search-worker', 'limit', v);
    when 'course_pages.search_monthly_credit_cap' then
      perform public.admin_course_link_search_settings((p_value#>>'{}')::int);
    when 'reading.read_batch_per_30s' then
      v := (p_value#>>'{}')::int; if v < 10 or v > 200 then raise exception 'between 10 and 200'; end if;
      perform security.pipeline_setting_cron_arg('coverage-read', 'limit', v);
    when 'layer3.route_limit' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 200 then raise exception 'between 1 and 200'; end if;
      perform security.pipeline_setting_cron_arg('layer3-intake-route', 'limit', v);
      perform security.pipeline_setting_cron_arg('layer3-english-route', 'limit', v);
    when 'layer3.route_concurrency' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 16 then raise exception 'between 1 and 16'; end if;
      perform security.pipeline_setting_cron_arg('layer3-intake-route', 'concurrency', v);
      perform security.pipeline_setting_cron_arg('layer3-english-route', 'concurrency', v);
    when 'layer3.requests_per_day' then
      v := (p_value#>>'{}')::int; if v < 1000 or v > 100000 then raise exception 'between 1,000 and 100,000'; end if;
      update pipeline.layer3_model_profiles set requests_per_day = v, updated_at = now()
       where enabled and retired_at is null and code ~ '^openrouter-(intake|english)-l3[cr]-';
    when 'layer3.daily_usd_max' then
      v_txt := p_value->>'task_class'; v_n := (p_value->>'value')::numeric;
      if v_n < 0 or v_n > 200 then raise exception 'between 0 and 200 USD'; end if;
      update pipeline.layer3_route_budget set daily_usd_max = v_n, updated_at = now() where task_class = v_txt;
      if not found then raise exception 'task % not found', v_txt; end if;
    when 'layer3.credit_floor_usd' then
      v_n := (p_value#>>'{}')::numeric; if v_n < 0 or v_n > 100 then raise exception 'between 0 and 100 USD'; end if;
      update pipeline.layer3_route_budget set credit_floor_usd = v_n, updated_at = now();
    when 'budgets.firecrawl_monthly_limit' then
      v := (p_value#>>'{}')::int; if v < 1000 or v > 2000000 then raise exception 'between 1,000 and 2,000,000 credits'; end if;
      update pipeline.layer2_acquisition_providers set billing_config = billing_config || jsonb_build_object('monthly_vendor_units_limit', v), updated_at = now() where provider_key = 'firecrawl';
    when 'budgets.firecrawl_stop_at_remaining' then
      v := (p_value#>>'{}')::int; if v < 0 or v > 100000 then raise exception 'between 0 and 100,000 credits'; end if;
      update pipeline.layer2_acquisition_providers set billing_config = billing_config || jsonb_build_object('stop_at_vendor_units_remaining', v), updated_at = now() where provider_key = 'firecrawl';
    when 'identity.attribute' then
      -- {"country":"NZ","attribute":"english","identities":["exact_title", ...]}: which page identities admit the attribute
      if not (p_value->>'attribute') in ('official_url', 'english', 'intakes', 'tuition') then raise exception 'attribute must be official_url, english, intakes or tuition'; end if;
      if exists (select 1 from jsonb_array_elements_text(p_value->'identities') x where x not in ('cricos_code', 'nzqa_code', 'exact_title', 'title_level', 'field_award', 'degree_name')) then raise exception 'unknown identity'; end if;
      update pipeline.coverage_admission_countries c
         set identities = jsonb_set(c.identities, array[p_value->>'attribute'], coalesce(p_value->'identities', '[]'::jsonb), true), updated_at = now(),
             approved_ref = c.approved_ref || format('; Settings page, Platform Admin %s (%s: %s)', to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), p_value->>'attribute', p_value->'identities')
        from ref.countries k where k.id = c.country_id and k.iso_alpha2 = p_value->>'country';
      if not found then raise exception 'country % not found', p_value->>'country'; end if;
    else raise exception 'unknown setting %', p_key;
  end case;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('settings', 'change', p_key, jsonb_build_object('value', p_value, 'before', v_before #> string_to_array(p_key, '.')), auth.uid());
  return public.admin_pipeline_settings_read();
end $f$;
revoke all on function public.admin_pipeline_settings_write(text, jsonb) from public, anon;
grant execute on function public.admin_pipeline_settings_write(text, jsonb) to authenticated;
