-- CF-247 settings tidy-up, Phase 1 (Platform Admin 16 Nov 2026 05:12 and 05:23, approving claude/ui-ux-settings-audit-2026-11-15.md §5 Phase 1 and
-- decisions 1 to 4). Settings metadata only: no value changes, no new setting, no new job.
--   1. Retiring settings (control_class 'retiring', a component register row of the new kind 'setting' with replaced_by and
--      retire_after = today + hygiene.retire_after_days). Nothing is deleted here: docs/paste/PASTE-20261116-retired-settings-drop.sql removes
--      them after the retirement period, once the components that still name them are gone. 46 settings:
--      a. the 39 Serper (23) and ScrapingBee (16) settings: both services were dropped on 4 Oct 2026 (Firecrawl only). Read only by functions that
--         are already retiring (public.admin_search_pass_start, public.admin_toolset_sample_write, public.admin_toolset_samples_read,
--         security.toolset_pass_backlog), the retiring edge function toolset-runner, security.toolset_plan_status (any toolset; a missing setting
--         gives no plan) and security.toolset_sample_notices_v1 (see 3);
--      b. 4 of the 11 settings tied to retiring or retired components (audit §2.3), whose only readers are retiring:
--         calendar.university_levels (security.calendar_default_intakes_apply_v1, retiring), batch.course_link_reverse (the switched-off job
--         course-link-reverse, retiring), worker.outcome_failed_runs (security.worker_outcome_check_v1 through the switched-off job
--         worker-outcome-check, retiring), batch.evidence_purge_check (no reader; job evidence-purge-prepare is gone);
--      c. 3 model pins the platform already reports as not read since the AI routes (13 Nov 2026): pipeline.entry.matrix_model,
--         pipeline.ops.ai_diagnosis_model (20261113380000) and firecrawl.builder_model (20261113390000). Each model is chosen on Models & services.
--   2. used_by: the other 7 of the 11 are still read by the components that replaced the retiring ones and are re-pointed, not retired
--      (calendar.countries, alerts.max_attempts, alerts.retry_minutes, alerts.delivery_enabled, intake_dates.name_period_lists,
--      intake_dates.deadline_max_days_before, batch.calendar_reread). The 53 firecrawl, openrouter, edge_functions and scheduled_jobs settings
--      with no used_by get their readers (found 16 Nov 2026 in the live function source and the coverage-sweep worker). A used_by that is
--      already set is never overwritten, except the 7 re-pointed ones.
--   3. security.toolset_sample_notices_v1() returns an empty list: both of its notices were for Serper and ScrapingBee (sample runs in the
--      retiring table pipeline.toolset_sample_runs, and their plans at reserve). Its callers (security.admin_read_snapshot_build_v1,
--      security.platform_notices_cached_v1) keep working when that table and these settings go. md5-guarded against the live definition.
--   4. unit: every setting that is not retiring and is outside the consumer API sections (Website API, Zoho API; read-only, decision 4) gets a
--      unit (numbers: their measure; switches 'on/off'; lists and text: what they hold). An existing unit is never overwritten.
--   5. Sections that overlap are merged (labels only, pipeline toolset; no key changes; no function filters on these names, checked live):
--      Re-reads and retries > Re-read and retry; Storage, Retention > Storage & retention; Admission > Admission checks; Enrich fields,
--      Enrichment lanes > Enrichment; Layer 4 readiness > Layer 4; Provider descriptions › built-in prompt only > Provider descriptions;
--      Scholarship details, Scholarship discovery, Scholarship coverage recovery, Scholarship flow guard, Scholarship eligibility reader > Scholarships.
--   6. Change log (audit §7.5): every change above is written to pipeline.admin_control_events (area 'settings', action 'migration', target
--      'toolset.key', detail: migration, field, before, after, reason), the same log the settings screens write with their reason.
--      updated_by and updated_at are not touched (no value changed; "changed by a person" stays true to people).
-- G1: no job. G2: no number is written into a job or function. G3: no consumer API object, table shape or value is changed; the Website API and
--   Zoho API settings are left as they are; security.consumer_api_check_v1() is run before and after (no drift).
-- Replaces: security.toolset_sample_notices_v1() (same name and signature; md5-guarded). The component_register kind check gains 'setting'.
-- Retires: 46 settings (control_class 'retiring'; component register kind 'setting', status 'retiring'). Nothing is dropped or deleted here.

set local lock_timeout = '5s';

-- 0. What this change expects to find ------------------------------------------------------------------------------------------------------
do $$
declare v_def text; v_n int;
begin
  if to_regclass('pipeline.platform_toolset_settings') is null or to_regclass('pipeline.component_register') is null
     or to_regclass('pipeline.admin_control_events') is null then
    raise exception 'required settings, component register or control events table is missing';
  end if;
  v_def := pg_get_functiondef('security.toolset_sample_notices_v1()'::regprocedure);
  if md5(v_def) <> 'eaed45914ee054cfc147981c1eace5e3' and position('settings tidy-up Phase 1' in v_def) = 0 then
    raise exception 'live security.toolset_sample_notices_v1 differs from the definition this change replaces (md5 %)', md5(v_def);
  end if;
  select count(*) into v_n from pipeline.platform_toolset_settings where toolset_key in ('serper', 'scrapingbee');
  if v_n <> 39 then raise exception 'expected 39 Serper and ScrapingBee settings, found %', v_n; end if;
end $$;

-- 1. The component register can hold settings ----------------------------------------------------------------------------------------------
do $$
begin
  if pg_get_constraintdef((select c.oid from pg_constraint c where c.conrelid = 'pipeline.component_register'::regclass
                                                             and c.conname = 'component_register_kind_check')) not like '%''setting''%' then
    alter table pipeline.component_register drop constraint component_register_kind_check;
    alter table pipeline.component_register add constraint component_register_kind_check
      check (kind = any (array['job', 'table', 'view', 'edge_function', 'screen', 'function', 'setting']));
  end if;
end $$;
comment on column pipeline.component_register.kind is 'job, table, view, edge_function, screen, function or setting (a row of pipeline.platform_toolset_settings, named toolset.key; since 20261116010000).';

-- 2. The changes, worked out first so each is logged with its before value -----------------------------------------------------------------
create temp table cf_p1_changes (toolset_key text, key text, field text, after text, reason text, fill_only boolean default false,
                                 before text, skip boolean default false) on commit drop;

-- 2a. retiring
insert into cf_p1_changes(toolset_key, key, field, after, reason)
select toolset_key, key, 'control_class', 'retiring', initcap(toolset_key) || ' was dropped on 4 Oct 2026 (Firecrawl only); read only by retiring components'
  from pipeline.platform_toolset_settings where toolset_key in ('serper', 'scrapingbee');
insert into cf_p1_changes(toolset_key, key, field, after, reason) values
  ('pipeline', 'calendar.university_levels', 'control_class', 'retiring', 'read only by security.calendar_default_intakes_apply_v1 (retiring)'),
  ('pipeline', 'batch.course_link_reverse', 'control_class', 'retiring', 'read only by the switched-off job course-link-reverse (retiring)'),
  ('pipeline', 'worker.outcome_failed_runs', 'control_class', 'retiring', 'read only by security.worker_outcome_check_v1 through the switched-off job worker-outcome-check (retiring)'),
  ('pipeline', 'batch.evidence_purge_check', 'control_class', 'retiring', 'no reader: job evidence-purge-prepare is gone'),
  ('pipeline', 'entry.matrix_model', 'control_class', 'retiring', 'not read since 20261113380000: the model is the AI route on Models & services'),
  ('pipeline', 'ops.ai_diagnosis_model', 'control_class', 'retiring', 'not read since 20261113380000: the model is the AI route on Models & services'),
  ('firecrawl', 'builder_model', 'control_class', 'retiring', 'not read since 20261113390000: the model is the AI route adapter_builder on Models & services');

-- 2b. used_by: the 7 re-pointed (overwrite)
insert into cf_p1_changes(toolset_key, key, field, after, reason) values
  ('pipeline', 'calendar.countries', 'used_by', 'security.calendar_reread_relevant_v2 (job calendar-reread)', 're-pointed: security.calendar_default_intakes_apply_v1 is retiring'),
  ('pipeline', 'alerts.max_attempts', 'used_by', 'security.alert_delivery_take_v1, security.alert_delivery_status_v1, security.platform_alerts_evaluate_v1, security.platform_alerts_webhook_v1', 're-pointed: security.platform_alerts_confirm_v1 is retiring'),
  ('pipeline', 'alerts.retry_minutes', 'used_by', 'security.alert_delivery_take_v1, security.platform_alerts_evaluate_v1, security.platform_alerts_webhook_v1', 're-pointed: security.platform_alerts_confirm_v1 is retiring'),
  ('pipeline', 'alerts.delivery_enabled', 'used_by', 'security.platform_alerts_evaluate_v1, security.platform_alerts_add_v1, security.platform_health_check_v1, security.platform_watchdog_v1 (job platform-alerts)', 're-pointed: security.platform_alerts_take_v1 is retiring'),
  ('pipeline', 'intake_dates.name_period_lists', 'used_by', 'security.intake_dates_plan_v3, security.intake_period_text_v1 (job intake-dates-apply)', 're-pointed: security.intake_dates_plan_v2 is retiring'),
  ('pipeline', 'intake_dates.deadline_max_days_before', 'used_by', 'security.intake_dates_plan_v3 (job intake-dates-apply); security.enrich_course_text_record_v1 (course page deadlines)', 're-pointed: security.intake_dates_plan_v1 is retiring'),
  ('pipeline', 'batch.calendar_reread', 'used_by', 'job calendar-reread (coverage-sweep mode calendar_reread); public.admin_calendar_status_read', 're-pointed: public.svc_calendar_reread_next is retiring');

-- 2c. used_by: readers for settings that had none (fill only)
insert into cf_p1_changes(toolset_key, key, field, after, reason, fill_only)
select t, k, 'used_by', u, 'reader recorded (G2: every setting has used_by)', true from (values
  ('edge_functions', 'min_timeouts', 'security.platform_notices_v1 (edge function time-out notices)'),
  ('edge_functions', 'notice_window_hours', 'security.platform_notices_v1 (edge function time-out notices)'),
  ('scheduled_jobs', 'min_failures', 'security.platform_notices_v1 (scheduled job failure notices)'),
  ('scheduled_jobs', 'notice_window_hours', 'security.platform_notices_v1 (scheduled job failure notices)'),
  ('openrouter', 'balance_stale_minutes', 'security.platform_notices_v1; public.admin_ai_overview_v1'),
  ('openrouter', 'guard_central_ai', 'security.ai_spend_today_v1 (daily guard per AI lane, guard_<lane>_ai)'),
  ('openrouter', 'guard_scholarship_ai', 'security.ai_spend_today_v1 (daily guard per AI lane); security.scholarship_pilot_stop_v1'),
  ('openrouter', 'low_balance_warn_usd', 'security.platform_notices_v1; public.admin_ai_overview_v1'),
  ('openrouter', 'notice_window_hours', 'security.platform_notices_v1 (OpenRouter refusal notices)'),
  ('firecrawl', 'autobuild_credits', 'public.admin_adapter_autobuild'),
  ('firecrawl', 'autobuild_per_day', 'public.admin_adapter_autobuild'),
  ('firecrawl', 'builder_ai_daily_usd', 'security.adapter_builder_budget'),
  ('firecrawl', 'builder_model_profile', 'security.adapter_builder_model_for_v1; public.admin_ai_config_read'),
  ('firecrawl', 'builder_proposals_per_day', 'security.adapter_builder_budget'),
  ('firecrawl', 'builder_samples', 'public.admin_adapter_builder'),
  ('firecrawl', 'central_refresh_days', 'public.svc_central_find_record; public.svc_fc_spend'),
  ('firecrawl', 'daily_budget_on', 'security.fc_budget_left_v1, security.fc_budget_status_v1, public.svc_fc_spend, security.fc_sch_held_v1, security.aer_discovery_spare_room_v1, security.scholarship_discovery_hold_reason_v1'),
  ('firecrawl', 'daily_budget_total', 'security.fc_budget_left_v1, security.fc_budget_status_v1, public.svc_fc_spend, security.aer_discovery_spare_room_v1, security.ops_cost_report_v1'),
  ('firecrawl', 'daily_share_central', 'security.fc_budget_left_v1, security.fc_budget_status_v1 (purpose central: daily_share_<purpose>)'),
  ('firecrawl', 'daily_share_course_search', 'security.fc_budget_left_v1, security.fc_budget_status_v1 (purpose course_search: daily_share_<purpose>)'),
  ('firecrawl', 'daily_share_other', 'security.fc_budget_left_v1, security.fc_budget_status_v1 (purpose other: daily_share_<purpose>)'),
  ('firecrawl', 'daily_share_reads', 'security.fc_budget_left_v1, security.fc_budget_status_v1 (purpose reads: daily_share_<purpose>)'),
  ('firecrawl', 'daily_share_scholarships', 'security.fc_budget_left_v1, security.fc_budget_status_v1 (purpose scholarships); public.svc_scholarship_fc_budget; security.scholarship_pilot_stop_v1'),
  ('firecrawl', 'eval_field_share', 'security.adapter_build_fields_v1; security.provider_onboarding_step_v1; public.admin_adapter_evaluation'),
  ('firecrawl', 'eval_no_page_share', 'public.admin_adapter_evaluation'),
  ('firecrawl', 'eval_unreadable_share', 'public.admin_adapter_evaluation'),
  ('firecrawl', 'find_credits_per_run', 'public.admin_firecrawl_write (a Find pages run)'),
  ('firecrawl', 'find_min_title_match', 'worker coverage-sweep (Firecrawl runs: Find pages)'),
  ('firecrawl', 'find_query', 'security.firecrawl_upgrade_run_v1'),
  ('firecrawl', 'find_results', 'worker coverage-sweep (Firecrawl search)'),
  ('firecrawl', 'find_retry_refused', 'security.firecrawl_backlog_v1'),
  ('firecrawl', 'low_balance_warn_units', 'security.platform_notices_v1; public.admin_credit_notices'),
  ('firecrawl', 'qualify_agree_share', 'security.adapter_build_fields_v1; security.provider_onboarding_step_v1'),
  ('firecrawl', 'read_credits_per_run', 'public.admin_firecrawl_write (a Read pages run)'),
  ('firecrawl', 'read_formats', 'worker coverage-sweep (Firecrawl runs: Read pages)'),
  ('firecrawl', 'read_location', 'worker coverage-sweep (Firecrawl runs: Read pages)'),
  ('firecrawl', 'read_skip_url_pattern', 'security.firecrawl_backlog_v1'),
  ('firecrawl', 'read_statuses', 'security.firecrawl_backlog_v1'),
  ('firecrawl', 'read_timeout_ms', 'worker coverage-sweep (Firecrawl runs: Read pages)'),
  ('firecrawl', 'read_url_pattern', 'security.firecrawl_backlog_v1'),
  ('firecrawl', 'read_wait_ms', 'worker coverage-sweep (Firecrawl runs: Read pages)'),
  ('firecrawl', 'refused_host_pattern', 'security.refused_host'),
  ('firecrawl', 'run_auto_continue', 'security.firecrawl_runs_tick_v1'),
  ('firecrawl', 'run_batch_per_call', 'worker coverage-sweep (Firecrawl runs)'),
  ('firecrawl', 'run_concurrency', 'worker coverage-sweep (Firecrawl runs)'),
  ('firecrawl', 'scholarship_cap_per_uni', 'security.fc_sch_held_v1; public.svc_fc_spend'),
  ('firecrawl', 'scholarship_min_courses', 'security.fc_sch_eligible_v1'),
  ('firecrawl', 'search_stop_after', 'security.fc_search_stopped_v1, security.fc_search_stopped_for_v1; security.platform_notices_v1'),
  ('firecrawl', 'target_countries', 'security.firecrawl_targets_v1, security.firecrawl_target_rule_reasons_v1'),
  ('firecrawl', 'target_exclude_pattern', 'security.firecrawl_targets_v1, security.firecrawl_target_rule_reasons_v1'),
  ('firecrawl', 'target_min_courses', 'security.firecrawl_targets_v1, security.firecrawl_target_rule_reasons_v1'),
  ('firecrawl', 'target_name_pattern', 'security.firecrawl_targets_v1, security.firecrawl_target_rule_reasons_v1, security.admin_jobs_resolve_adapters_v1'),
  ('firecrawl', 'target_only', 'security.course_link_search_eligible_v1, public.svc_course_link_search_next, public.svc_fc_targets, security.link_search_block_v1, security.provider_task_prepare_v1, security.worker_mode_waiting_v1'),
  ('firecrawl', 'target_registers', 'security.firecrawl_targets_v1, security.firecrawl_target_rule_reasons_v1')
) x(t, k, u);

-- 2d. unit (fill only): switches are 'on/off'; lists and text say what they hold
insert into cf_p1_changes(toolset_key, key, field, after, reason, fill_only)
select s.toolset_key, s.key, 'unit', coalesce(x.u, case s.kind when 'boolean' then 'on/off' end), 'unit recorded (G2: every setting has a unit)', true
  from pipeline.platform_toolset_settings s
  left join (values
    ('firecrawl', 'builder_model_profile', 'model profile'), ('firecrawl', 'find_min_title_match', 'share'), ('firecrawl', 'find_query', 'search wording'),
    ('firecrawl', 'read_formats', 'page formats'), ('firecrawl', 'read_proxy', 'proxy'), ('firecrawl', 'read_skip_url_pattern', 'pattern'),
    ('firecrawl', 'read_statuses', 'page states'), ('firecrawl', 'read_url_pattern', 'pattern'), ('firecrawl', 'refused_host_pattern', 'pattern'),
    ('firecrawl', 'target_countries', 'countries'), ('firecrawl', 'target_exclude_pattern', 'pattern'), ('firecrawl', 'target_min_courses', 'country:courses'),
    ('firecrawl', 'target_name_pattern', 'pattern'), ('firecrawl', 'target_registers', 'registers'),
    ('pipeline', 'aer.baseline_eligible', 'country:providers'), ('pipeline', 'aer.eligible_countries', 'countries'),
    ('pipeline', 'aer.not_applicable_provider_types', 'provider types'), ('pipeline', 'aer.postgraduate_levels', 'study levels'),
    ('pipeline', 'aer.priority_provider_types', 'provider types'), ('pipeline', 'har.ai_escalation_model', 'model'),
    ('pipeline', 'scholarship.external_award_patterns', 'patterns'), ('pipeline', 'scholarship.non_university_types', 'provider types'),
    ('pipeline', 'scholarship.pilot_provider_ids', 'providers')
  ) x(t, k, u) on x.t = s.toolset_key and x.k = s.key
 where nullif(btrim(s.unit), '') is null
   and s.section not in ('Website API', 'Zoho API')
   and s.toolset_key not in ('serper', 'scrapingbee')
   and not exists (select 1 from cf_p1_changes r where r.field = 'control_class' and r.toolset_key = s.toolset_key and r.key = s.key);
-- the responsibility a Human-assisted recovery case is assigned to
update cf_p1_changes set after = 'role' where field = 'unit' and after is null and toolset_key = 'pipeline' and key like 'har.%.assigned_to';

-- 2e. sections that overlap (labels only)
insert into cf_p1_changes(toolset_key, key, field, after, reason)
select s.toolset_key, s.key, 'section', m.to_s, 'sections that overlap merged (audit §2.2): ' || m.from_s || ' > ' || m.to_s
  from pipeline.platform_toolset_settings s
  join (values ('Re-reads and retries', 'Re-read and retry'), ('Storage', 'Storage & retention'), ('Retention', 'Storage & retention'),
               ('Admission', 'Admission checks'), ('Enrich fields', 'Enrichment'), ('Enrichment lanes', 'Enrichment'), ('Layer 4 readiness', 'Layer 4'),
               ('Provider descriptions › built-in prompt only', 'Provider descriptions'), ('Scholarship details', 'Scholarships'),
               ('Scholarship discovery', 'Scholarships'), ('Scholarship coverage recovery', 'Scholarships'), ('Scholarship flow guard', 'Scholarships'),
               ('Scholarship eligibility reader', 'Scholarships')) m(from_s, to_s) on m.from_s = s.section
 where s.toolset_key = 'pipeline';

-- 2f. before values; every named setting must exist; a fill never overwrites; nothing unchanged is logged
do $$
declare v_missing text;
begin
  select string_agg(c.toolset_key || '.' || c.key, ', ') into v_missing from cf_p1_changes c
   where not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = c.toolset_key and s.key = c.key);
  if v_missing is not null then raise exception 'settings named by this change are missing: %', v_missing; end if;
  if exists (select 1 from cf_p1_changes where field = 'unit' and after is null) then
    raise exception 'a setting without a unit has no unit in this change: %',
      (select string_agg(toolset_key || '.' || key, ', ') from cf_p1_changes where field = 'unit' and after is null);
  end if;
end $$;
update cf_p1_changes c
   set before = case c.field when 'control_class' then s.control_class when 'used_by' then s.used_by when 'unit' then s.unit when 'section' then s.section end
  from pipeline.platform_toolset_settings s where s.toolset_key = c.toolset_key and s.key = c.key;
update cf_p1_changes set skip = true where before is not distinct from after or (fill_only and nullif(btrim(before), '') is not null);

-- 3. Apply ----------------------------------------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings s set control_class = c.after
  from cf_p1_changes c where not c.skip and c.field = 'control_class' and s.toolset_key = c.toolset_key and s.key = c.key;
update pipeline.platform_toolset_settings s set used_by = c.after
  from cf_p1_changes c where not c.skip and c.field = 'used_by' and s.toolset_key = c.toolset_key and s.key = c.key;
update pipeline.platform_toolset_settings s set unit = c.after
  from cf_p1_changes c where not c.skip and c.field = 'unit' and s.toolset_key = c.toolset_key and s.key = c.key;
update pipeline.platform_toolset_settings s set section = c.after
  from cf_p1_changes c where not c.skip and c.field = 'section' and s.toolset_key = c.toolset_key and s.key = c.key;

-- the change log (§7.5)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'migration', c.toolset_key || '.' || c.key,
       jsonb_build_object('migration', '20261116010000', 'field', c.field, 'before', c.before, 'after', c.after, 'reason', c.reason), null
  from cf_p1_changes c where not c.skip;

-- the component register: each retiring setting, named toolset.key
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, replaced_by, introduced_in, retire_after, note)
select 'setting', s.toolset_key || '.' || s.key, 'Platform', s.section, s.label, 'retiring', '{}',
       case when s.toolset_key in ('serper', 'scrapingbee') then 'Firecrawl (the only page service since 4 Oct 2026)'
            when s.key in ('entry.matrix_model', 'ops.ai_diagnosis_model', 'builder_model') then 'the AI route of its service on Models & services'
            when s.key = 'calendar.university_levels' then 'nothing: intakes are read from the course''s own page only'
            when s.key = 'worker.outcome_failed_runs' then 'nothing: worker failures are reported by Platform health and the queue watchdog'
            else 'nothing: its job is switched off and retiring, or gone' end,
       '20261116010000 (marked retiring)', current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, c.reason
  from cf_p1_changes c join pipeline.platform_toolset_settings s on s.toolset_key = c.toolset_key and s.key = c.key
 where c.field = 'control_class' and c.after = 'retiring'
on conflict (kind, name) do update set status = 'retiring', replaced_by = excluded.replaced_by, note = excluded.note, updated_at = now(),
  retire_after = coalesce(pipeline.component_register.retire_after, excluded.retire_after);

-- 4. Sample-run notices: Serper and ScrapingBee are gone, so there is nothing to raise ------------------------------------------------------
CREATE OR REPLACE FUNCTION security.toolset_sample_notices_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- settings tidy-up Phase 1 (16 Nov 2026): both notices were for Serper and ScrapingBee (dropped 4 Oct 2026): their sample runs
  -- (pipeline.toolset_sample_runs, retiring) and their plans at reserve. Their settings are retiring, so the list is empty; callers keep working.
  select '[]'::jsonb
$function$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in, note)
values ('function', 'security.toolset_sample_notices_v1', 'Platform', 'Models & services', 'Sample-run and plan notices for page services (empty since Serper and ScrapingBee were dropped)',
        'active', '{}', '20261116010000', 'registered by the settings tidy-up; callers: security.admin_read_snapshot_build_v1, security.platform_notices_cached_v1')
on conflict (kind, name) do update set purpose = excluded.purpose, note = excluded.note, updated_at = now();

-- 5. Post-checks ----------------------------------------------------------------------------------------------------------------------------
do $$
declare v_n int;
begin
  select count(*) into v_n from pipeline.platform_toolset_settings s join pipeline.component_register r on r.kind = 'setting' and r.name = s.toolset_key || '.' || s.key
   where s.control_class = 'retiring' and r.status = 'retiring' and r.retire_after is not null;
  if v_n <> 46 then raise exception 'post-check: % of 46 settings are retiring with a register row', v_n; end if;
  select count(*) into v_n from pipeline.platform_toolset_settings
   where control_class is distinct from 'retiring' and toolset_key not in ('serper', 'scrapingbee') and nullif(btrim(used_by), '') is null;
  if v_n <> 0 then raise exception 'post-check: % setting(s) still have no used_by', v_n; end if;
  select count(*) into v_n from pipeline.platform_toolset_settings
   where control_class is distinct from 'retiring' and section not in ('Website API', 'Zoho API') and nullif(btrim(unit), '') is null;
  if v_n <> 0 then raise exception 'post-check: % setting(s) still have no unit', v_n; end if;
  select count(*) into v_n from pipeline.platform_toolset_settings
   where toolset_key = 'pipeline' and section in ('Re-reads and retries', 'Storage', 'Retention', 'Admission', 'Enrich fields', 'Enrichment lanes', 'Layer 4 readiness',
     'Provider descriptions › built-in prompt only', 'Scholarship details', 'Scholarship discovery', 'Scholarship coverage recovery', 'Scholarship flow guard',
     'Scholarship eligibility reader');
  if v_n <> 0 then raise exception 'post-check: % setting(s) are still in a merged section', v_n; end if;
  if position('serper' in pg_get_functiondef('security.toolset_sample_notices_v1()'::regprocedure)) > 0 then
    raise exception 'post-check: security.toolset_sample_notices_v1 still reads the Serper settings';
  end if;
end $$;
