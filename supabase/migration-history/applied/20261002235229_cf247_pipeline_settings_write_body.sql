-- CF-247 (3 Oct 2026, Decision 238). Part 3 of the Settings page functions: the write (Platform Admin). Each key maps
-- to the live object that held the value before — cron job commands, Layer 3 profiles and budgets, the course-page
-- search cap, the admission identities per country — so a change made here is exactly the change a migration made
-- before, with an audit row every time. Numbers apply at once. Prompts are never edited here. The Firecrawl monthly
-- limit and reserve stay on the Layer 2 provider record (Scrapers & fetchers) until that record's control moves here.
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
      update pipeline.layer3_route_budget set credit_floor_usd = v_n, updated_at = now() where task_class in ('provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation');
    when 'identity.attribute' then
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
