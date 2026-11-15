-- CF-247 G2 promotion wave A (Phase 2 of the UI/UX and settings simplification; Platform Admin 16 Nov 2026 05:23: "Proceed directly into
-- Phase 2 (G2 hardcoded values -> settings)"; audit claude/ui-ux-settings-audit-2026-11-15.md §2.4).
-- Operational values written into eleven live functions become settings, each with the same value as today, so nothing behaves differently
-- until a person changes a setting with a reason. Technical values in the same functions (leases, the window of the run itself, page sizes)
-- stay in code and are marked "-- fixed: <why>" on their line (G2).
--   Promoted (9 new settings; 1 existing setting now also read):
--     security.layer1_plan_finish_v1            30 days (x2)  -> layer1.reverify_after_days       (a course or provider counts as verified for)
--     security.scholarship_admit_from_provider_page_v1  90 days -> reread.scholarship_page_days (existing: the scholarship page re-read)
--     security.scholarship_scheduler_tick_impl  1 hour        -> scholarship.scheduler_retry_minutes (a failed scheduler step is tried again after)
--     security.coverage_fetch_area_v1           7 days        -> coverage.link_search_retry_days   (search again for a course page after)
--     security.data_quality_exceptions_impl     180 days (x3) -> data_quality.stale_after_days     (verification older than this is stale)
--     security.data_quality_overview_impl       180 days (x3) -> data_quality.stale_after_days
--     security.progress_snapshot_v1             90 days       -> retention.progress_snapshots_days (progress snapshots kept for)
--     security.retention_evidence_candidates_v1 7 days        -> retention.evidence_min_age_days   (evidence younger than this is never purged)
--     security.zero_yield_detect_v1             23 hours (x3) -> zero_yield.redetect_hours         (a provider is checked again after)
--     security.provider_policy_refresh_plans_v1 30 minutes    -> english_policy.replan_minutes     (an English policy plan is worked out again after)
--     security.retention_tick_v1                limit 3       -> retention.audit_columns_per_tick  (evidence audit columns per tick: a job size)
--   Marked fixed: layer1_plan_finish_v1 (the run's own hour, x2), coverage_fetch_area_v1 (page size of the area list, x2),
--     zero_yield_detect_v1 (the hour that zero_yield.providers_per_run counts), retention_tick_v1 (the 10-minute hand-over lease, x3).
-- How: each function's live definition is md5-guarded, every edit must match exactly the expected number of times, and the edited definition
--   is executed in place (same name, signature, owner and grants). Nothing else in a function changes. Applying it twice changes nothing.
-- Not touched: consumer API functions (G3), AER v1 functions (Decision 276), retiring components, admin screen reads (they move with each
--   screen's redesign), security.provider_onboarding_step_v1 (wave B: its stage timers need their own review).
-- G1: no job. G2: 9 settings with label, range, unit, section and used_by; no number in a job. G3: security.consumer_api_check_v1() before and after.
-- Replaces: the eleven functions above (same names and signatures; md5-guarded edits in place).
-- Retires: nothing. Nothing is dropped or deleted.

set local lock_timeout = '5s';

-- 1. Settings (G2): today's values ---------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by, control_class) values
 ('pipeline', 'layer1.reverify_after_days', 'Layer 1: a course or provider counts as verified for',
  'When a register run finishes, active courses and providers not verified within this many days are marked for checking again.',
  'number', to_jsonb(30), 1, 365, 'days', 1901, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Re-read and retry', 'security.layer1_plan_finish_v1', 'automatic'),
 ('pipeline', 'scholarship.scheduler_retry_minutes', 'Scholarship scheduler: try a failed step again after',
  'A scholarship scheduler step that fails is due again after this many minutes.',
  'number', to_jsonb(60), 5, 1440, 'minutes', 1902, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Scholarships', 'security.scholarship_scheduler_tick_impl', 'automatic'),
 ('pipeline', 'coverage.link_search_retry_days', 'Course page search: search again after',
  'A course whose page search found nothing is searched again after this many days.',
  'number', to_jsonb(7), 1, 90, 'days', 1903, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Course page search', 'security.coverage_fetch_area_v1', 'automatic'),
 ('pipeline', 'data_quality.stale_after_days', 'Data quality: verification is stale after',
  'On the data quality overview and exceptions, a course or provider last verified longer ago than this is counted as stale.',
  'number', to_jsonb(180), 30, 730, 'days', 1904, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Health report', 'security.data_quality_overview_impl, security.data_quality_exceptions_impl', 'automatic'),
 ('pipeline', 'retention.progress_snapshots_days', 'Retention: keep progress snapshots for',
  'Progress snapshots older than this are removed by the snapshot job.',
  'number', to_jsonb(90), 7, 730, 'days', 1905, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Storage & retention', 'security.progress_snapshot_v1', 'automatic'),
 ('pipeline', 'retention.evidence_min_age_days', 'Retention: never purge evidence younger than',
  'Evidence files are offered for purging only when they are older than this (and older than the audit that found them).',
  'number', to_jsonb(7), 1, 90, 'days', 1906, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Storage & retention', 'security.retention_evidence_candidates_v1', 'automatic'),
 ('pipeline', 'zero_yield.redetect_hours', 'Zero-yield pages: check a provider again after',
  'A provider checked for zero-yield pages is not checked again, nor reset again, within this many hours.',
  'number', to_jsonb(23), 1, 168, 'hours', 1907, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Zero-yield pages', 'security.zero_yield_detect_v1', 'automatic'),
 ('pipeline', 'english_policy.replan_minutes', 'English policies: work out a plan again after',
  'A proposed or approved English policy whose plan is older than this is planned again.',
  'number', to_jsonb(30), 5, 1440, 'minutes', 1908, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'English policies', 'security.provider_policy_refresh_plans_v1', 'automatic'),
 ('pipeline', 'retention.audit_columns_per_tick', 'Retention: evidence audit columns per run',
  'How many evidence audit columns one retention run checks.',
  'number', to_jsonb(3), 1, 50, 'columns', 1909, 'G2 promotion wave A (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Storage & retention', 'security.retention_tick_v1', 'automatic')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings set used_by = used_by || '; security.scholarship_admit_from_provider_page_v1 (next read of a page admitted from its title)'
 where toolset_key = 'pipeline' and key = 'reread.scholarship_page_days' and position('scholarship_admit_from_provider_page_v1' in coalesce(used_by, '')) = 0;

-- 2. The edit helper (this transaction only) ------------------------------------------------------------------------------------------------
-- p_edits: one row per edit {kind, old, new, n}: kind 'swap' replaces old with new; kind 'mark' appends " -- fixed: <new>" to each line that
-- contains old. Each edit must match exactly n times, or nothing is changed.
create or replace function pg_temp.cf_g2_edit(p_fn text, p_md5 text, p_done text, p_edits jsonb) returns text language plpgsql as $edit$
declare v_def text := pg_get_functiondef(p_fn::regprocedure); v_new text; e jsonb; v_n int; v_pat text;
begin
  if position(p_done in v_def) > 0 then return 'already'; end if;
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_fn, md5(v_def); end if;
  v_new := v_def;
  for e in select * from jsonb_array_elements(p_edits) loop
    v_n := (length(v_new) - length(replace(v_new, e->>'old', ''))) / length(e->>'old');
    if v_n <> (e->>'n')::int then raise exception '%: "%" found % time(s), expected %', p_fn, e->>'old', v_n, e->>'n'; end if;
    if e->>'kind' = 'swap' then
      v_new := replace(v_new, e->>'old', e->>'new');
    else
      v_pat := regexp_replace(e->>'old', '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '[^\n]*';
      v_new := regexp_replace(v_new, v_pat, '\& -- fixed: ' || (e->>'new'), 'g');
    end if;
  end loop;
  if position(p_done in v_new) = 0 then raise exception '%: the edited definition does not carry %', p_fn, p_done; end if;
  execute v_new;
  return md5(pg_get_functiondef(p_fn::regprocedure));
end $edit$;

-- 3. The edits ------------------------------------------------------------------------------------------------------------------------------
do $$
declare r record; v_out text; v_log jsonb := '{}'::jsonb;
begin
  for r in select * from (values
    ('security.layer1_plan_finish_v1(uuid,boolean,uuid)', '92818b53fa475a437dbf84cae67ec766', 'layer1.reverify_after_days', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now()-interval ''30 days''', 'new', 'now()-make_interval(days => security.pipeline_num_v1(''layer1.reverify_after_days'', 30)::int)', 'n', 2),
       jsonb_build_object('kind', 'mark', 'old', 'p.created_at-interval ''1 hour''', 'new', 'rows seen by this run (its own hour), not an operating window', 'n', 1),
       jsonb_build_object('kind', 'mark', 'old', 'c.last_verified_at>=now()-interval ''1 hour''', 'new', 'verified by this run (its own hour), not an operating window', 'n', 1))),
    ('security.scholarship_admit_from_provider_page_v1(bigint)', '0741db9c35ef91eba6caa55b04fde869', 'reread.scholarship_page_days', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now()+interval ''90 days''', 'new', 'now()+make_interval(days => security.pipeline_num_v1(''reread.scholarship_page_days'', 90)::int)', 'n', 1))),
    ('security.scholarship_scheduler_tick_impl(timestamp with time zone,integer)', '6af37c60bfa0f2a41d4ea14e7cdc9d0c', 'scholarship.scheduler_retry_minutes', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'next_due_at=p_now+interval ''1 hour''', 'new', 'next_due_at=p_now+make_interval(mins => security.pipeline_num_v1(''scholarship.scheduler_retry_minutes'', 60)::int)', 'n', 1))),
    ('security.coverage_fetch_area_v1(text,jsonb)', 'cc69c46ac00b76f93be4846c721ca4df', 'coverage.link_search_retry_days', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', '< now() - interval ''7 days'';', 'new', '< now() - make_interval(days => security.pipeline_num_v1(''coverage.link_search_retry_days'', 7)::int);', 'n', 1),
       jsonb_build_object('kind', 'mark', 'old', 'limit 10 offset v_off', 'new', 'page size of the area list (display)', 'n', 2))),
    ('security.data_quality_exceptions_impl(jsonb)', '85b6c4d92bb1575e095f604e89860c30', 'data_quality.stale_after_days', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now()-interval ''180 days''', 'new', 'now()-make_interval(days => security.pipeline_num_v1(''data_quality.stale_after_days'', 180)::int)', 'n', 3))),
    ('security.data_quality_overview_impl(jsonb)', '5587c9b82d6adde716d229843d66f7a4', 'data_quality.stale_after_days', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now()-interval ''180 days''', 'new', 'now()-make_interval(days => security.pipeline_num_v1(''data_quality.stale_after_days'', 180)::int)', 'n', 3))),
    ('security.progress_snapshot_v1()', 'd2b01fca6972a405e72603ff12ed1b9e', 'retention.progress_snapshots_days', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now() - interval ''90 days''', 'new', 'now() - make_interval(days => security.pipeline_num_v1(''retention.progress_snapshots_days'', 90)::int)', 'n', 1))),
    ('security.retention_evidence_candidates_v1()', '2f877c1898de889e44b1983f582f5599', 'retention.evidence_min_age_days', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now() - interval ''7 days''', 'new', 'now() - make_interval(days => security.pipeline_num_v1(''retention.evidence_min_age_days'', 7)::int)', 'n', 1))),
    ('security.zero_yield_detect_v1()', 'd7424522e9c0dcc97a62ad0d4a662268', 'zero_yield.redetect_hours', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now() - interval ''23 hours''', 'new', 'now() - make_interval(hours => security.pipeline_num_v1(''zero_yield.redetect_hours'', 23)::int)', 'n', 3),
       jsonb_build_object('kind', 'mark', 'old', 'now() - interval ''1 hour'')', 'new', 'the hour that zero_yield.providers_per_run counts', 'n', 1))),
    ('security.provider_policy_refresh_plans_v1(integer)', '130169b8cef0c8683b29eef86d0a8bb8', 'english_policy.replan_minutes', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'now() - interval ''30 minutes''', 'new', 'now() - make_interval(mins => security.pipeline_num_v1(''english_policy.replan_minutes'', 30)::int)', 'n', 1))),
    ('security.retention_tick_v1()', '4f583aa618658a66c70acd56cbbd014c', 'retention.audit_columns_per_tick', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'order by tbl, col limit 3 loop', 'new', 'order by tbl, col limit security.pipeline_num_v1(''retention.audit_columns_per_tick'', 3)::int loop', 'n', 1),
       jsonb_build_object('kind', 'mark', 'old', 'now() - interval ''10 minutes''', 'new', 'hand-over lease: work not confirmed within 10 minutes is taken back', 'n', 3)))
  ) t(fn, md5, done, edits) loop
    v_out := pg_temp.cf_g2_edit(r.fn, r.md5, r.done, r.edits);
    v_log := v_log || jsonb_build_object(r.fn, v_out);
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('settings', 'migration', 'G2 promotion wave A', jsonb_build_object('migration', '20261116020000', 'functions', v_log), null);
end $$;

-- 4. Post-checks ----------------------------------------------------------------------------------------------------------------------------
do $$
declare v_bad text;
begin
  select string_agg(f, ', ') into v_bad from (values
    ('security.layer1_plan_finish_v1(uuid,boolean,uuid)', 'now()-interval ''30 days'''),
    ('security.scholarship_admit_from_provider_page_v1(bigint)', 'now()+interval ''90 days'''),
    ('security.scholarship_scheduler_tick_impl(timestamp with time zone,integer)', 'p_now+interval ''1 hour'''),
    ('security.coverage_fetch_area_v1(text,jsonb)', 'interval ''7 days'''),
    ('security.data_quality_exceptions_impl(jsonb)', 'interval ''180 days'''),
    ('security.data_quality_overview_impl(jsonb)', 'interval ''180 days'''),
    ('security.progress_snapshot_v1()', 'interval ''90 days'''),
    ('security.retention_evidence_candidates_v1()', 'interval ''7 days'''),
    ('security.zero_yield_detect_v1()', 'interval ''23 hours'''),
    ('security.provider_policy_refresh_plans_v1(integer)', 'interval ''30 minutes'''),
    ('security.retention_tick_v1()', 'col limit 3 loop')) x(f, lit)
   where position(x.lit in pg_get_functiondef(x.f::regprocedure)) > 0;
  if v_bad is not null then raise exception 'post-check: a value is still written into %', v_bad; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('layer1.reverify_after_days', 'scholarship.scheduler_retry_minutes',
        'coverage.link_search_retry_days', 'data_quality.stale_after_days', 'retention.progress_snapshots_days', 'retention.evidence_min_age_days',
        'zero_yield.redetect_hours', 'english_policy.replan_minutes', 'retention.audit_columns_per_tick')) <> 9 then
    raise exception 'post-check: the 9 settings are not all present';
  end if;
end $$;
