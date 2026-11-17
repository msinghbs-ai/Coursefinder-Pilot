-- CF-247 SS-020 step 1: admin menu consolidation, dead sections retire (Decision 269; Platform Admin 3 Nov 2026 about 22:05 AEDT "Approve all,
-- build in order"; admin docs/platform/ui-audit/2026-11-03-admin-menu-build-prompt.md step 1, keep-merge-retire review section 5).
-- Measured live, read only, 3 Nov 2026 22:01-22:30 AEDT (project fxcwkweaxjtknorudmwp):
--   a. Scheduled jobs › Automations shows an area "Layer 3 AI". Its three jobs are not Layer 3: coverage-ai-match-prepare (every 2 minutes,
--      720 runs in 24 h), coverage-ai-match (every minute, 1,160 runs) and fee-period-settle (every 10 minutes, 144 runs) are live course-page
--      and fee work. Retiring the area therefore moves them to the areas of their work; no job is paused, changed or removed.
--   b. Serper and ScrapingBee (Firecrawl only since 4 Oct 2026): no scheduled job uses them; the last sample run was 4 Oct 04:14 UTC. The Serper
--      settings are read only by security.toolset_pass_backlog, called only by public.admin_search_pass_start (the Search pass card).
--      public.svc_search_pass_bind and public.svc_toolset_sample_continue are called only by the toolset-runner edge function, which only the
--      Sample runs and Search pass cards start. pipeline.search_pass_links is NOT retired: Firecrawl course-page finding writes it
--      (svc_fc_find_bind, svc_adapter_page_record; 3,392 rows changed in the last 7 days) and course_link_search_tick_v1 calls search_pass_advance_v1.
--      pipeline.toolset_sample_runs and toolset_sample_items are still read by security.toolset_sample_notices_v1 (notice snapshots), so they
--      may only be dropped after that reader stops reading them; the register note says so.
--   c. ScraperAPI, Scrape.do and ZenRows are switched off (enabled = false since 4 Oct); Parsebot has no row. Their rows stay; the screens no
--      longer list them (src/retired-services.js).
--   d. Platform health › Health checks: check layer_queues reports under area "Layer 3" and carries two Layer 3 sub-checks (stuck work items,
--      work dispatch) on pipeline.layer3_work_items, empty of live work since 11 Oct 21:56 UTC. The screen shows the check under its real
--      scope and leaves the Layer 3 sub-checks out; the server function is not edited in this step (recorded below for the follow-up).
-- What this migration does: re-areas three catalogue rows (an update with a where clause, no job command changed) and records the retired
-- screens, functions, tables and edge function in pipeline.component_register. Nothing is dropped, deleted, paused or switched off.
-- Not in this step (DECISION REQUIRED — SS-020, see the SS-020 report): Scheduled jobs › Automations › "Refresh schedules and one-off runs" stays,
-- because its Edit schedule is the only control of the cadence that drives the Layer 1 register runs (security.refresh_scheduler_tick_impl reads
-- pipeline.refresh_policies.cadence_interval; Layer 1 › Sources edits layer1_source_operations.verification_cadence_days, which no tick reads).
-- Replaces: the "Layer 3 AI" area of pipeline.automation_catalogue (its three jobs move to Course pages and Admission)
-- Retires: the Serper, ScrapingBee, Search pass and Sample runs cards; dropped acquisition providers on Fetchers, Settings and the Go-live checklist;
--   the Go-live Layer 3 model profiles gate; Progress "Courses with each field"; the Health checks Layer 3 block (all marked retiring in
--   pipeline.component_register, with the functions, tables and edge function that only served them)

-- 1. Automations: the "Layer 3 AI" area ---------------------------------------------------------------------------------------------------
update pipeline.automation_catalogue set area = 'Course pages'
 where jobname in ('coverage-ai-match-prepare', 'coverage-ai-match') and area = 'Layer 3 AI';
update pipeline.automation_catalogue set area = 'Admission'
 where jobname = 'fee-period-settle' and area = 'Layer 3 AI';

-- 2. housekeeping: the register ---------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaced_by, retire_after, introduced_in, note) values
 ('screen', 'Models & services › Toolsets & limits › Serper card', 'L2 read', 'Models & services',
  'Serper key, plan limits and search settings', 'retiring', 'Firecrawl (Models & services; Firecrawl only since 4 Oct 2026)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): card removed; pipeline.platform_toolsets row and its settings kept'),
 ('screen', 'Models & services › Toolsets & limits › ScrapingBee card', 'L2 read', 'Models & services',
  'ScrapingBee key, plan limits and render settings', 'retiring', 'Firecrawl (Models & services; Firecrawl only since 4 Oct 2026)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): card removed; pipeline.platform_toolsets row and its settings kept'),
 ('screen', 'Models & services › Toolsets & limits › Search pass', 'L2 read', 'Models & services',
  'Run the Serper search pass for courses without a page', 'retiring', 'Firecrawl course-page search (Layer 2/3 › Course sources)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): card removed; pipeline.search_pass_links stays (Firecrawl finding writes it)'),
 ('screen', 'Models & services › Toolsets & limits › Sample runs', 'L2 read', 'Models & services',
  'Sample runs of the Serper and ScrapingBee keys', 'retiring', 'nothing (only Serper and ScrapingBee had sample runs)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): card removed; last sample run 4 Oct 2026'),
 ('screen', 'Models & services › Fetchers (dropped providers: ScraperAPI, Scrape.do, ZenRows, Parsebot, Serper, ScrapingBee)', 'L2 read', 'Models & services',
  'Rows of acquisition providers dropped for go-live (29 Sep) or by Firecrawl only (4 Oct)', 'retiring', 'Firecrawl and Direct HTTP rows on the same tab',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): not listed on Fetchers, Settings or the Go-live checklist; pipeline.layer2_acquisition_providers rows kept'),
 ('screen', 'Go-live checklist › Layer 3 model profiles gate', 'Platform', 'Go-live checklist',
  'Production gates of the Layer 3 model profiles', 'retiring', 'nothing (Layer 3 retired 12 Oct 2026)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): table removed from the checklist; pipeline.layer3_profile_environment_gates kept'),
 ('screen', 'Go-live checklist › dropped Layer 2 provider gates', 'Platform', 'Go-live checklist',
  'Production gates of the dropped acquisition providers', 'retiring', 'Firecrawl and Direct HTTP gates on the same checklist',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): rows left out; pipeline.layer2_provider_environment_gates kept'),
 ('screen', 'Coverage & completeness › Progress › Courses with each field', 'Platform', 'Coverage & completeness',
  'Share of courses with intakes, English, fee and delivery', 'retiring', 'Coverage & completeness › Attributes',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): duplicate of Attributes; admin_progress_read still returns the figures (no function edited)'),
 ('screen', 'Platform health › Health checks › Layer 3 block', 'Platform', 'Platform health',
  'Layer 3 stuck work items and Layer 3 work dispatch in check layer_queues (area "Layer 3")', 'retiring', 'the same check shown as Layer 2 and 4 queues',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): screen leaves out the Layer 3 sub-checks. Follow-up: an md5-guarded edit of security.platform_health_check_v1 removing the layer3_stuck and layer3_dispatch sub-checks and renaming the area'),
 ('screen', 'Scheduled jobs › Automations › Layer 3 AI area', 'Platform', 'Scheduled jobs',
  'Catalogue area of three jobs', 'retiring', 'areas Course pages and Admission (same jobs, unchanged)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1 (Decision 269): coverage-ai-match-prepare, coverage-ai-match and fee-period-settle re-areaed; none paused'),
 ('function', 'public.admin_search_pass_start', 'L2 read', 'Models & services',
  'Start the Serper search pass', 'retiring', 'Firecrawl course-page search',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: only caller was the Search pass card'),
 ('function', 'public.admin_search_pass_read', 'L2 read', 'Models & services',
  'Search pass card read', 'retiring', 'nothing',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: only caller was the Search pass card'),
 ('function', 'security.toolset_pass_backlog', 'L2 read', 'Models & services',
  'Courses the Serper search pass would search', 'retiring', 'nothing',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: only caller public.admin_search_pass_start (retiring)'),
 ('function', 'public.svc_search_pass_bind', 'L2 read', 'Models & services',
  'toolset-runner binds a Serper-found page', 'retiring', 'svc_fc_find_bind (Firecrawl)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: only caller the toolset-runner edge function (retiring)'),
 ('function', 'public.admin_toolset_sample_write', 'L2 read', 'Models & services',
  'Start, continue or stop a sample run', 'retiring', 'nothing',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: only caller was the Sample runs card'),
 ('function', 'public.admin_toolset_samples_read', 'L2 read', 'Models & services',
  'Sample runs card read', 'retiring', 'nothing',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: only caller was the Sample runs card'),
 ('function', 'public.svc_toolset_sample_continue', 'L2 read', 'Models & services',
  'toolset-runner continues a sample run', 'retiring', 'nothing',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: only caller the toolset-runner edge function (retiring)'),
 ('edge_function', 'toolset-runner', 'L2 read', 'Models & services',
  'Runs Serper and ScrapingBee sample runs and the search pass', 'retiring', 'nothing (Firecrawl only)',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: started only by the Sample runs and Search pass cards'),
 ('table', 'pipeline.toolset_sample_runs', 'L2 read', 'Models & services',
  'Sample runs of the Serper and ScrapingBee keys', 'retiring', 'nothing',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: still read by security.toolset_sample_notices_v1 (notice snapshots); drop only after that reader stops reading it'),
 ('table', 'pipeline.toolset_sample_items', 'L2 read', 'Models & services',
  'Items of the Serper and ScrapingBee sample runs', 'retiring', 'nothing',
  (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, '20261104340000',
  'SS-020 step 1: still read by security.toolset_sample_notices_v1 (notice snapshots); drop only after that reader stops reading it')
on conflict (kind, name) do update set status = excluded.status, replaced_by = excluded.replaced_by, retire_after = excluded.retire_after,
  note = excluded.note, updated_at = now()
 where pipeline.component_register.status = 'active';

-- 3. post-check ---------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pipeline.automation_catalogue where area = 'Layer 3 AI') then
    raise exception 'SS-020 step 1: a job is still in the Layer 3 AI area';
  end if;
  if (select count(*) from pipeline.component_register where note like 'SS-020 step 1%' and status in ('retiring', 'retired')) < 20 then
    raise exception 'SS-020 step 1: the register rows were not all recorded';
  end if;
end $$;
