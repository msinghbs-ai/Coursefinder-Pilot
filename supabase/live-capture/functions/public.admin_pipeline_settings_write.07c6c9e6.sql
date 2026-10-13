CREATE OR REPLACE FUNCTION public.admin_pipeline_settings_write(p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v int; v_n numeric; v_txt text; v_before jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  v_before := public.admin_pipeline_settings_read();
  case p_key
    -- v2.15.269: job sizes are settings in the register; the job reads them, it is not rewritten
    when 'course_pages.matcher_prepare_universities' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 500 then raise exception 'between 1 and 500'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.ai_match_prepare_universities';
    when 'course_pages.matcher_prepare_courses' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 5000 then raise exception 'between 1 and 5,000'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.ai_match_prepare_courses';
    when 'course_pages.matcher_items_per_minute' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 200 then raise exception 'between 1 and 200'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.ai_match';
    when 'course_pages.matcher_concurrency' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 24 then raise exception 'between 1 and 24'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'concurrency.ai_match';
    when 'course_pages.search_per_minute' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 120 then raise exception 'between 1 and 120'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.link_search_worker';
    when 'course_pages.search_monthly_credit_cap' then
      perform public.admin_course_link_search_settings((p_value#>>'{}')::int);
    when 'reading.read_batch_per_30s' then
      v := (p_value#>>'{}')::int; if v < 10 or v > 200 then raise exception 'between 10 and 200'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.coverage_read';
    -- v2.15.269: the Layer 3 settings are removed (Layer 3 retired 12 Oct 2026; its jobs no longer exist)
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
end $function$
