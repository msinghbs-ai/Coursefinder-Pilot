CREATE OR REPLACE FUNCTION public.admin_provider_description_prompt_v1(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 F-PDESC (20261112010000): read (rank 3 and above, as Fill) and save (Platform Admin, with a reason). A save is a new active version.
declare v_text text := btrim(coalesce(p_args->>'system_prompt', '')); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_ver int;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'not allowed' using errcode = '42501'; end if; -- the same rank as Fill and the Enrich fields tab
  if p_action = 'read' then
    return jsonb_build_object(
      'prompt_on', security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1,
      'can_edit', coalesce(security.current_role_rank(), 0) >= 6,
      'active', (select to_jsonb(x) from (select version, system_prompt, reason, created_at, activated_at from pipeline.provider_description_prompts where status = 'active') x),
      'history', (select coalesce(jsonb_agg(to_jsonb(x) order by x.version desc), '[]'::jsonb) from (select version, status, reason, created_at, activated_at, left(system_prompt, 160) preview from pipeline.provider_description_prompts order by version desc limit 20) x),
      'refused_words', security.toolset_setting('pipeline', 'pdesc.prompt_refused_words'),
      'length', jsonb_build_object('min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2), 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5),
                                   'min_chars', security.pipeline_num_v1('pdesc.min_chars', 150), 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)),
      -- AI spend, Firecrawl use, controls and progress for the screens (Platform Admin 11 Nov 2026 06:11: "should be visible on UI")
      'status', jsonb_build_object(
        'ai_spent_usd', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening'),
        'ai_ceiling_usd', security.pipeline_num_v1('pdesc.ai_usd_max', 1),
        'ai_today_usd', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening' and l.at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'),
        'ai_daily_guard_usd', coalesce((security.toolset_setting('openrouter', 'guard_provider_description') #>> '{}')::numeric, 1),
        'firecrawl_used_window', (select coalesce(sum(x.firecrawl_reads), 0) from pipeline.provider_description_reads x where x.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int)),
        'firecrawl_allowance', security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0), 'firecrawl_window_hours', security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24),
        'firecrawl_share_left_today', security.fc_budget_left_v1('provider_description'), 'firecrawl_share_day', security.fc_setting_num_v1('daily_share_pdesc', 0),
        'reader_every_minutes', security.pipeline_num_v1('pdesc.every_minutes', 10), 'batch', security.pipeline_num_v1('batch.provider_description', 3),
        'admitted_24h', (select count(*) from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.created_at > now() - interval '24 hours'), -- fixed: a display window
        'described', (select count(*) from catalogue.providers p where nullif(btrim(p.description), '') is not null and p.lifecycle_status = 'active' and p.publication_status = 'published'),
        'queued', (select count(*) from pipeline.provider_description_reads x where x.state = 'queued'),
        'on_demand_waiting', (select count(*) from pipeline.provider_description_reads x where x.state in ('queued', 'reading') and security.pdesc_on_demand_live_v1(x.checks)),
        'held', (select count(*) from pipeline.provider_description_reads x where x.state = 'held'),
        'manual', (select count(*) from pipeline.manual_locks l where l.entity = 'provider' and l.field in ('description', 'p_description')),
        'self_heal_last', (select jsonb_build_object('at', d.start_time, 'status', d.status) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'provider-description-self-heal' order by d.start_time desc limit 1),
        'reader_last', (select jsonb_build_object('at', d.start_time, 'status', d.status) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'provider-description-read' order by d.start_time desc limit 1)));
  elsif p_action = 'save' then
    if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'a reason is required'; end if;
    if length(v_text) < 200 then raise exception 'the prompt is too short (200 characters or more)'; end if; -- fixed: the table's own check (a prompt is never empty)
    if v_text = (select system_prompt from pipeline.provider_description_prompts where status = 'active') then raise exception 'the prompt is unchanged'; end if;
    perform pg_advisory_xact_lock(hashtext('cf247 provider description prompt'));
    select coalesce(max(version), 2) + 1 into v_ver from pipeline.provider_description_prompts;
    update pipeline.provider_description_prompts set status = 'retired' where status = 'active';
    insert into pipeline.provider_description_prompts(version, system_prompt, status, reason, created_by, activated_at, activated_by)
    values (v_ver, v_text, 'active', v_reason, auth.uid(), now(), auth.uid());
    return jsonb_build_object('ok', true, 'version', v_ver);
  end if;
  raise exception 'unknown action %', p_action;
end $function$
