CREATE OR REPLACE FUNCTION security.link_search_block_v1(p_provider uuid, p_course_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job record; v_flag record; v_on boolean; v_cap numeric; v_used numeric; v_left numeric; v_rc record; v_person boolean; v_memo text := current_setting('cf.link_search_block_totals', true);
        v_bypass boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;
begin
  -- hotfix 3: one query, not one per course
  v_person := p_course_ids is not null and exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running')
                                                     and j.args->>'provider_id' = p_provider::text and j.args->'course_ids' ?| p_course_ids::text[]);
  select j.active into v_job from cron.job j where j.jobname = 'course-link-search-worker';
  select f.flagged_at, f.next_check_at into v_flag from pipeline.enrichment_flags f
   where f.entity = 'job' and f.entity_key = 'course-link-search-worker' and f.reason_code = 'idle_paused' and f.state = 'raised' order by f.flagged_at desc limit 1;
  if v_job.active is distinct from true and v_flag.flagged_at is null then
    return jsonb_build_object('code', 'lane_paused', 'words', 'The course page search lane is switched off', 'fix', 'Scheduled jobs › Automations › Find course pages (search): Resume');
  end if;
  if v_flag.flagged_at is not null then
    return jsonb_build_object('code', 'lane_idle_paused', 'words', 'The course page search lane is paused by the idle guard until ' || to_char(v_flag.next_check_at at time zone 'Australia/Melbourne', 'HH24:MI'), 'fix', 'It wakes by itself when work waits; nothing to do');
  end if;
  select s.enabled, s.monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings s where s.id = 1;
  if not coalesce(v_on, false) then return jsonb_build_object('code', 'search_off', 'words', 'Course page search is switched off', 'fix', 'Models & services › Toolsets & limits › Firecrawl › course search'); end if;
  -- hotfix 3: the month and day totals are the same for every task in one request; worked out once per statement and reused
  if v_memo is not null and split_part(v_memo, '|', 1) = statement_timestamp()::text then
    v_used := split_part(v_memo, '|', 2)::numeric; v_left := split_part(v_memo, '|', 3)::numeric;
  else
    select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now());
    v_left := security.fc_budget_left_v1('course_link_search');
    perform set_config('cf.link_search_block_totals', statement_timestamp()::text || '|' || v_used || '|' || v_left, true);
  end if;
  if v_used + 2 > v_cap then return jsonb_build_object('code', 'month_cap', 'words', 'This month''s course search credits are used (' || v_used::int || ' of ' || v_cap::int || ')', 'fix', 'Waits for next month, or raise the monthly cap'); end if;
  if v_left < 2 then return jsonb_build_object('code', 'day_budget', 'words', 'Today''s Firecrawl share for course search is used', 'fix', 'Waits for tomorrow''s share'); end if;
  -- R2: the day's picked-courses cap (a person's running task is not held by it)
  if not (v_bypass and v_person) and (select count(*) from pipeline.course_link_search s where s.sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))
       >= security.pipeline_num_v1('search.daily_picked_cap', 100) then
    return jsonb_build_object('code', 'daily_cap', 'words', 'Today''s course search cap (' || security.pipeline_num_v1('search.daily_picked_cap', 100)::int || ' courses) is reached; searching resumes at 00:00 UTC', 'fix', 'Settings › Pipeline settings › Course search: courses a day');
  end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider) then
    return jsonb_build_object('code', 'provider_hidden', 'words', 'The university is unpublished or archived; its searches wait', 'fix', 'Publish the university');
  end if;
  -- hotfix 3: the stop for this one university (fc_search_stopped_v1 works it out for every university)
  if security.search_stop_gate_v1(p_provider, null, null, v_person) = 'search_stopped' then  -- S1: the one stop gate
    return jsonb_build_object('code', 'search_stopped', 'words', 'The automatic search stopped for this university (wrong pages in a row, or too many searches with no page)' || case when not v_bypass then '; a person''s task waits too (search.person_task_bypass is off)' else '' end, 'fix', 'Adapter builder › Find course pages › Search again, or a person''s Find course pages task');
  end if;
  if coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
     and not exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = p_provider and tc.included) then
    return jsonb_build_object('code', 'not_target', 'words', 'Firecrawl is for target universities only and this one is not a target', 'fix', 'Models & services › Toolsets & limits › Firecrawl targets');
  end if;
  select rc.search_domain into v_rc from pipeline.course_link_recipes rc where rc.provider_id = p_provider and rc.active limit 1;
  if v_rc.search_domain is null then return jsonb_build_object('code', 'no_site', 'words', 'No website is recorded to search', 'fix', 'Adapter builder step 1: the website'); end if;
  if security.third_party_host_v1('https://' || v_rc.search_domain) then return jsonb_build_object('code', 'directory_site', 'words', 'The recorded website is a course directory, not the university''s own', 'fix', 'Adapter builder step 1: change the website'); end if;
  if exists (select 1 from catalogue.providers px, pipeline.platform_toolset_settings sk
              where px.id = p_provider and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key) then
    return jsonb_build_object('code', 'skipped_provider', 'words', 'This university is on the search skip list', 'fix', 'Settings › Pipeline settings › search.skip_providers');
  end if;
  return null;
end $function$
