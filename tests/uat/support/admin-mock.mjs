// Mocked Supabase for local admin UAT: a signed-in Platform Admin and live-shaped reads.
// Only for the local dev server (VITE_SUPABASE_URL=https://example.supabase.co); nothing reaches a real backend.
import * as F from './admin-fixtures.mjs'

export async function mockAdmin(page, { rank = 6, healthMissing = false, courseDiffers = false, creditNotices = [], onboardingAuto = false } = {}) {
  const context = { ...F.context, role_rank: rank, role: rank >= 6 ? 'platform_admin' : 'viewer' }
  const session = { access_token: 'mock-token', refresh_token: 'mock-refresh', token_type: 'bearer', expires_in: 360000, expires_at: Math.floor(Date.now() / 1000) + 360000, user: { id: context.user_id, email: 'admin@example.test', aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} } }
  const adminRead = {
    ranking_filters: F.rankingFilters, ranking_filter_options: F.rankingFilterOptions, ranking_observations: F.rankingObservations,
    ranking_link_candidates: F.rankingLinkCandidates, ranking_provider_search: { items: [] }, provider_ranking_history: F.providerRankingHistory,
    context, dashboard: F.dashboard, layer_status_summary: F.layerStatus, platform_health: F.platformHealth,
    live_activity: F.liveActivity, course_coverage: F.courseCoverage, course_coverage_providers: [{ id: 'prov-monash', name: 'Monash University', country: 'AU', courses: 640 }], data_quality_overview: F.dataQualityOverview,
    courses_page: F.coursesPage, course_detail: F.courseDetail, scholarships_page: F.scholarshipsPage, scholarship_detail: F.scholarshipDetail,
    // Decision 254 (job system A2): a finished admin task in the Jobs history, opened to its result
    pipeline_filters: { layers: ['L2'], statuses: ['completed', 'failed'], modes: [], countries: [], job_types: ['layer2_task'], failure_classes: [], completion_classes: [] },
    pipeline_jobs_page: { total: 1, items: [{ id: 'pj-task', job_type: 'layer2_task', task_title: 'Qualify 2 adapter(s) in AU-NSW', task_note: '1 with a passing field', task_providers: ['University of Technology Sydney', 'University of New England'], domain: 'qualify_adapters', status: 'completed', layer_code: 'L2', run_mode: 'DRY_RUN', created_at: '2026-10-06T00:10:00Z', started_at: '2026-10-06T00:11:00Z', completed_at: '2026-10-06T00:12:00Z', duration_ms: 60000, attempt_count: 1, evidence_count: 0, completion_class: 'completed', failure_class: null, provider_name: null, source_label: null }] },
    pipeline_job_detail: { job: { id: 'pj-task', job_type: 'layer2_task', domain: 'qualify_adapters', status: 'completed', payload: { admin_job_id: 'job-done', kind: 'qualify_adapters', title: 'Qualify 2 adapter(s) in AU-NSW' }, result: { state: 'done', passing: 1, errors: 0 } }, run_semantics: {}, entity_impact: {}, safe_actions: {}, evidence: [] },
    layer1_operations: F.layer1Operations,
    layer3_queue_status: F.layer3Queue, campuses_page: F.campusesPage, enrichment_operations: F.enrichmentOps, layer2_ops_overview: F.layer2Overview, layer2_parent_runs: F.layer2Parents, layer2_ops_alerts: [], layer2_acquisition_providers: F.environmentRead.layer2_providers,
  }
  const calls = []; page.l3calls = calls
  const rpc = {
    // v2.15.319/320: Platform health › Work queues and its 15-minute stats
    admin_queue_watch: { queues: [{ key: 'course_page_search', label: 'Find course pages (search)', area: 'Course pages', purpose: 'Searches the web for course pages.', state: 'moving', pending: 1183, per_hour: 36, eta_hours: 32.9, exhausted: 6147, nothing_left_is: 'Courses whose page was not found by any search', last_progress: '2026-10-22T11:03:00Z', since: '2026-10-22T09:58:00Z', tools_out: [], tools_waiting: [] }], events: [], fixes: [{ id: 1, key: 'course_page_read', at: '2026-10-22T10:04:00Z', items: 25, detail: { what: 'Pages that gave up on a time-out: one more read' } }], alerts: [], settings: { stuck_minutes: 120 }, can_run: true },
    admin_stats_15m: { latest: { at: '2026-10-22T11:02:00Z', countries: { NZ: { now: { courses: 6474, official_page: 3019, fee: 1147, english: 1936, intakes: 2103, campus: 3215, delivery: 3618, duration: 3259, level: 6238, field_of_study: 6143 }, change_15m: { fee: 2 }, change_24h: null } }, firecrawl: { total: 25000, used_today: 12787, groups: [{ group: 'course_search', label: 'Finding course pages', used: 10716, share: 13000, refused: 0 }], last_15m: { course_search: 16 } }, ai: [{ use: 'fee_ai', label: 'Fee reader with AI', spent_usd: 0.35, guard_usd: 5, calls: 20 }], worker_calls_15m: { read: { calls: 30, failed: 1, avg_s: 2.8, max_s: 10.3 } }, tasks: { running: 36, queued: 0, not_moving: 0 }, gaps: [{ kind: 'worker', note: 'Worker read: 1 of 30 calls failed, slowest 10.3 s' }] }, trend: [] },
    // Decision 222: Fetch an area on the course-page sweep; Websites to find
    admin_coverage_fetch_area: b => { calls.push({ fetchArea: b }); return b.p_action === 'options' ? F.fetchAreaOptions : b.p_action === 'scope_page' ? F.fetchAreaScope : b.p_action === 'start' ? { ...F.fetchAreaPreview, first_in_sweep: true, started: F.fetchAreaStarted } : F.fetchAreaPreview },
    admin_provider_websites: F.providerWebsites,
    // v2.15.246 (Feature 2): Layer 1 › Sources
    admin_layer1_add_source: b => { calls.push({ l1Add: b.p_args }); return { ok: true, source_id: 'l1-new', label: b.p_args.label } },
    layer1_admin_command: b => { calls.push({ l1Command: b }); return { ok: true } },
    layer1_statistics_candidates_read: [],
    admin_provider_website_set: b => { calls.push({ websiteSet: b }); return { ...F.providerWebsites, total: F.providerWebsites.total - 1, items: F.providerWebsites.items.filter(i => i.provider_id !== b.p_provider_id) } },
    admin_layer3_operations: F.layer3Operations,
    admin_layer3_control_read: F.layer3Control,
    admin_data_flags_read: F.dataFlags,
    admin_data_flag_resolve: b => { calls.push(b); return F.dataFlags },
    admin_data_flag_resolve_bulk: b => { calls.push({ flagBulk: b }); const items = F.dataFlags.items.filter(i => !b.p_flag_ids.includes(i.id)); return { done: b.p_flag_ids.length, skipped: 0, read: { ...F.dataFlags, items, counts: { ...F.dataFlags.counts, open: items.length } } } },
    admin_live_error_ack: b => { calls.push({ errorSeen: b }); return { ...F.liveActivity, worker_errors: F.liveActivity.worker_errors.filter(e => !(e.status === b.p_status && e.message === b.p_message)) } },
    admin_layer3_control: b => { calls.push(b); return F.layer3Control },
    admin_automations_read: F.automations,
    admin_automation_control: b => { calls.push(b); return F.automations },
    admin_requeue_read: F.requeue,
    admin_requeue: b => { calls.push(b); return { ...F.requeue, moved: 12 } },
    admin_scholarship_publishing_read: F.scholarshipPublishing,
    admin_scholarship_record_read: F.scholarshipRecord,
    admin_scholarship_layer_read: b => F.scholarshipLayer(b.p_layer),
    // v2.15.248 (bugs 11/10-5): journey, a university's runs, skip rules
    admin_scholarship_job_journey: () => F.scholarshipJourney,
    admin_scholarship_provider_runs: () => [{ ...F.scholarshipJourney, providers: [F.scholarshipJourney.providers[0]] }],
    admin_scholarship_skip_rules: b => { calls.push({ skipRules: b }); return F.skipRules },
    // v2.15.249 (bugs 11/10-6): Scholarships › Extraction
    admin_scholarship_ai: b => { calls.push({ scholarshipAi: b }); if (b.p_action === 'reviews') return F.scholarshipAiReviews; if (b.p_action === 'review_decide') return { ok: true }; if (b.p_action === 'reviews_reread') return { ...F.scholarshipAi, applied: { queued: 2 } }; if (b.p_action === 'set_chain') return { ...F.scholarshipAi, chain: b.p_args.models, active_model: b.p_args.models[0] }; if (b.p_action === 'activate') return { ...F.scholarshipAi, active_model: b.p_args.model_code, models: F.scholarshipAi.models.map(m => m.code === b.p_args.model_code ? { ...m, status: 'active', activated_at: '2026-10-11T12:00:00Z' } : m) }; return F.scholarshipAi },
    admin_scholarship_coverage_provider: { row: { name: 'Charles Darwin University', listed: 0, found: 0, published: 0, missing: 0, watch: true }, can_manage: true, listing_pages: [], listed: [], extra: [] },
    // v2.15.247 (bugs 11/10-4): Scholarships › Coverage with two providers of one name
    admin_scholarship_coverage_read: { scope: 'watch', total: 2, can_manage: true, can_watch: true, auto_publish: { on: false, recent: [] }, totals: { watch: 2, with_listing: 2, suggested: 0, checked: 0, active: 10, published: 4 },
      rows: [{ provider_id: 'vu-1', name: 'Victoria University', code: '00124K', watch: true, state: 'to_check', listing_pages: 1, listed: 11, found: 2, missing: 9, extra: 1, records_published: 1 },
             { provider_id: 'vu-2', name: 'Victoria University', code: '02475D', watch: true, state: 'to_check', listing_pages: 1, listed: 11, found: 2, missing: 9, extra: 1, records_published: 1 }] },
    admin_scholarship_layer_write: b => { calls.push({ p_action: b.p_action, p_args: b.p_args }); return { ok: true } },
    // Decision 252: toolsets, keys and plan limits, notices and sample runs
    admin_toolsets_read: F.toolsets,
    admin_platform_notices_read: b => F.platformNotices(b.p_layer),
    admin_toolsets_write: b => { calls.push({ toolsets: b.p_action, args: b.p_args }); return { ok: true } },
    // v2.15.269: settings register and policy tables (Pipeline settings)
    admin_settings_register_read: () => F.settingsRegister,
    admin_policy_tables_read: () => F.policyTables,
    admin_policy_tables_write: b => { calls.push({ policy: b }); return F.policyTables },
    admin_toolset_samples_read: b => F.toolsetSamples(b.p_run_id),
    admin_search_pass_read: F.searchPass,
    // Decision 253: Firecrawl work
    admin_firecrawl_read: F.firecrawlWork,
    // Decision 254, job system Phase A: the Task manager
    admin_jobs: b => { calls.push({ jobs: b.p_action, args: b.p_args }); if (b.p_action === 'read') return F.adminJobs(b.p_args?.id, b.p_args); return { ok: true, id: 'job-new', title: 'Qualify 11 adapter(s) in AU-VIC', providers: 11 } },
    admin_uni_adapter_read: F.uniAdapter,
    admin_uni_adapter_review: F.uniAdapterReview,
    admin_universities_read: b => { calls.push({ universities: b.p_args }); return F.universities },
    admin_fee_rules_report: b => { calls.push({ feeRules: true }); return { as_at: '2026-10-06T00:00:00Z', tolerance: 0.05, year: 2026, compared: 6825, agree: 4241, differ: 2584, would_change: 2349, suspected_half: 20, suspected_half_sample: [{ course_id: 'c2', title: 'Diploma of Business', provider: 'Beta College', page_fee: 10400, cricos_per_year: 20000 }], protected_by_hand: 1, kept_no_evidence: 59, kept_other_site: 175, page_higher: 1138, page_lower: 1211, gap_over_20: 962, by_country: [], by_provider: [{ provider_id: 'u1', provider: 'Alpha University', country: 'AU', compared: 10, would_change: 4 }], sample: [{ course_id: 'c1', title: 'Master of Test', provider: 'Alpha University', page_fee: 30000, page_year: 2027, cricos_per_year: 20000, gap: 0.5 }] } },
    admin_adapters: b => { calls.push({ adapters: b.p_action, args: b.p_args }); const gate = o => ({ ...o, can_manage: rank >= 6, can_qualify: rank >= 5 }); return b.p_action === 'list' ? gate(F.adaptersList) : b.p_action === 'detail' ? gate(F.adapterDetail(b.p_args?.provider_id)) : { ok: true, changed: (b.p_args?.provider_ids || []).length } },
    // v2.15.300: Layer 2/3 › Operations and Universities (the Adapters rows plus onboarding), screen use
    admin_layer23: b => { calls.push({ layer23: b.p_action }); if (b.p_action === 'universities') { const l = F.adaptersList; return { ...l, can_manage: rank >= 6, can_qualify: rank >= 5, can_onboard: rank >= 6, adapters: (l.adapters || []).map((x, i) => i === 0 ? { ...x, onboarding: { id: 'ob-1', status: 'stopped', stage: 'admit', stop_reason: 'nothing_ready', note: 'Nothing passed after 2 AI attempts', updated_at: '2026-10-20T00:00:00Z' }, inbox: 2, inbox_kinds: { nothing_ready: 1, course_link: 1 } } : { ...x, onboarding: null, inbox: 0 }) } }
      return { as_at: '2026-10-20T01:00:00Z', can_manage: rank >= 6, done: 129, enrich_review: 634, settings: { enabled: true, auto_admit: onboardingAuto, max_active: 100 },
        stages: [{ key: 'website', label: 'Find the website', order: 1, what: 'The official website is found and checked.', running: 0, waiting: 0, stopped: 40, stopped_by_kind: { website_needed: 40 }, jobs: ['provider-website-check'] },
                 { key: 'pages', label: 'Find course pages', order: 2, what: 'Pages found and read.', running: 1, waiting: 43, stopped: 520, stopped_by_kind: { too_few_pages: 466, pages_not_found: 54 }, jobs: ['coverage-discover'] },
                 { key: 'adapter', label: 'Build the adapter', order: 3, what: 'Adapter built.', running: 0, waiting: 0, stopped: 319, stopped_by_kind: { nothing_ready: 305, onboarding_failed: 14 }, jobs: ['provider-onboarding'] },
                 { key: 'enrich', label: 'Admit and enrich', order: 4, what: 'Admitted and enriched.', running: 0, waiting: 0, stopped: 273, stopped_by_kind: { not_on_site: 221, course_link: 1 }, jobs: ['coverage-admit'] },
                 { key: 'scholarships', label: 'Scholarships', order: 5, what: 'Scholarships checked.', running: 2, waiting: 0, stopped: 857, stopped_by_kind: { held_scholarship: 857 }, jobs: ['scholarship-recheck'] }] } },
    admin_screen_open: () => null,
    admin_screen_usage: { days: 14, since: '2026-10-20', rows: [{ page: 'layer2', tab: 'operations', opens: 3, people: 1, days_used: 1, last_at: '2026-10-20T01:00:00Z' }] },
    admin_university_courses_read: b => { calls.push({ uniCourses: b.p_provider_id, args: b.p_args }); return F.universityCourses },
    admin_university_reread: b => { calls.push({ reread: b.p_action, args: b.p_args }); return b.p_action === 'requests' ? [{ id: 'rq1', universities: 2, done: 2, which: 'all', central: true, pages: 15, central_pages: 2, status: 'sent', last_error: null, requested_at: '2026-10-05T10:30:00Z', finished_at: '2026-10-05T10:31:00Z', reason: 'x' }] : b.p_action === 'preview' ? { which: b.p_args.which, central: b.p_args.central, universities: (b.p_args.provider_ids || []).map((id, i) => ({ provider_id: id, name: id === 'u1' ? 'Example University' : 'Northern College', pages: i === 0 ? 12 : 3, firecrawl_likely: i === 0 ? 2 : 0, central_pages: b.p_args.central ? 1 : 0 })) } : { ok: true, request_id: 'rq1', universities: (b.p_args.provider_ids || []).length, status: 'waiting' } },
    admin_exit_awards: b => { calls.push({ exitAwards: b.p_action, args: b.p_args }); return b.p_action === 'read' ? (b.p_args?.scope === 'settings' ? { same_year_tolerance: 0.02, lagged_tolerance: 0.06, updated_at: '2026-10-05T09:00:00Z', reason: 'defaults' } : F.exitAwards) : { ok: true } },
    admin_host_pages: b => { calls.push({ hostPages: b.p_action, args: b.p_args }); return b.p_action === 'read' ? F.hostPages : { ok: true } },
    admin_provider_fee_range: b => { calls.push({ feeRange: b.p_action, args: b.p_args }); return b.p_action === 'read' ? (b.p_args?.provider_id ? F.feeRangeOne : F.feeRanges) : { ok: true } },
    admin_provider_central_page: b => { calls.push({ centralPage: b.p_action, args: b.p_args }); return { ok: true, source_id: 's1' } },
    admin_adapter_evaluation: F.adapterEvaluation,
    // v2.15.253: Providers › Onboarding and the credit banner (empty unless a test passes creditNotices)
    admin_provider_onboarding: b => { calls.push({ onboarding: b.p_action, args: b.p_args }); if (b.p_action === 'journey') return F.providerOnboardingJourney; if (b.p_action === 'pilot') return { cohort: 'pilot-2026-10-12', report: { ...F.onboardingPilotReport, at: '2026-10-12T08:00:00Z' }, snapshots: [] }; const d = { ...F.providerOnboarding, can_manage: rank >= 6, ...(onboardingAuto ? { settings: { ...F.providerOnboarding.settings, auto_admit: true, auto_admit_at: '2026-10-12T07:10:00Z', auto_admit_reason: 'Platform Admin, 12 Oct 2026 17:43: "Auto-admit everything that passes"' } } : {}) }; const st = b.p_args?.status, sg = b.p_args?.stage, q = (b.p_args?.q || '').toLowerCase(); return { ...d, rows: d.rows.filter(r => (!sg || r.stage === sg) && (!st || r.status === st || (st === 'active' && !['queued', 'stopped', 'waiting_admit', 'waiting_courses', 'done', 'cancelled'].includes(r.status))) && (!q || r.name.toLowerCase().includes(q))) } },
    admin_credit_notices: () => creditNotices,
    admin_adapter_builder: b => { calls.push({ builder: b.p_action, args: b.p_args }); return F.adapterBuilder },
    admin_uni_adapter_control: b => { calls.push({ adapterControl: b.p_action, args: b.p_args }); return { ok: true, id: 2 } },
    admin_uni_adapter_write: b => { calls.push({ adapter: b.p_action, args: b.p_args }); return { ok: true, preview_id: 'pv2', pages_read_again: 66 } },
    admin_ai_config_read: F.aiConfig,
    admin_ai_config: b => { calls.push({ aiConfig: b.p_action, args: b.p_args }); return F.aiConfig },
    admin_firecrawl_credits: b => { calls.push({ fcCredits: b.p_hours }); return F.firecrawlCredits },
    admin_progress_read: b => { calls.push({ progress: b.p_view, args: b.p_args }); const v = b.p_view, a = b.p_args || {}
      if (v === 'overview') return a.group === 'top' ? F.progressTop : F.progressOverview
      if (v === 'journeys') { const rows = F.progressJourneys.rows.filter(r => (!a.stage || r.stage === a.stage) && (!a.group || a.group === 'all' || r.grp === a.group) && (!a.q || r.name.toLowerCase().includes(String(a.q).toLowerCase())) && (!a.held || (a.held === 'any' ? Boolean(r.held_by) : a.held === 'search' ? ['search_held', 'search_stopped'].includes(r.held_by) : a.held === 'pages' ? r.held_by === 'too_few_pages' : true))); return { ...F.progressJourneys, total: rows.length, rows } }
      if (v === 'journey') { const r = F.progressJourneys.rows.find(x => x.onboarding_id === a.onboarding_id) || F.progressJourneys.rows[0]; return { ...r, can_manage: rank >= 6, can_run: rank >= 4, sch_status: 'mapped', steps: [{ stage: 'provider_in', from: '2026-10-12T11:38:00Z', to: '2026-10-12T11:38:00Z', note: 'Queued first: top 50 Australian providers by CRICOS courses.' }, { stage: 'prepare', from: '2026-10-12T11:39:00Z', to: '2026-10-12T12:12:00Z', note: 'Website found; finding course pages.' }] } }
      if (v === 'running') return { at: F.liveActivity.now, can_manage: rank >= 6, jobs: F.liveActivity.jobs.map(j => ({ ...j, stage: j.area === 'Scholarships' ? '6 Scholarship adapter' : j.area === 'Course pages' ? '2 Prepare' : 'Reporting' })), in_flight: 2, worker_errors: F.liveActivity.worker_errors.filter(e => !calls.some(c => c.errorSeen && c.errorSeen.p_status === e.status && c.errorSeen.p_message === e.message)), credits_hour: { course_search: 120, reads: 30 }, refused_hour: 26 }
      if (v === 'running_unis') return a.job === 'coverage-read' ? { job: a.job, unis: [{ provider_id: 'prov-alpha', name: 'Alpha Institute', country: 'AU', onboarding_id: 'ob-alpha', stage: 'prepare', what: 'at this stage now', n: 12 }], fallback: true } : { ...F.progressRunningUnis, job: a.job, fallback: false }
      if (v === 'levers') return F.progressLevers
      return {} },
    admin_firecrawl_search_resume: b => { calls.push({ fcResume: b.p_provider_id, reason: b.p_reason }); return { ok: true } },
    admin_firecrawl_report: b => { calls.push({ fcReport: b.p_since }); return F.firecrawlReport },
    admin_firecrawl_write: b => { calls.push({ firecrawl: b.p_action, args: b.p_args }); return { ok: true, run_id: 'fc000000-0000-4000-8000-000000000003', items: 1102 } },
    admin_search_pass_start: b => { calls.push({ pass: b }); return { ok: true, run_id: 'p1', courses: 2050 } },
    admin_toolset_sample_write: b => { calls.push({ sample: b.p_action, args: b.p_args }); return { ok: true, run_id: '7d1e0000-0000-4000-8000-000000000002', cases: 45 } },
    admin_scholarship_publishing: b => { calls.push(b); return F.scholarshipPublishing },
    admin_priority_read: F.priority,
    admin_priority_search: () => F.prioritySearch,
    admin_priority_control: b => { calls.push(b); return F.priority },
    admin_course_edit_read: F.courseEdit,
    admin_course_edit: b => { calls.push(b); return F.courseEdit },
    admin_course_create: b => { calls.push(b); return { ...F.courseEdit, course: { ...F.courseEdit.course, id: 'c-new' } } },
    admin_provider_edit_read: F.providerEdit,
    admin_provider_edit: b => { calls.push(b); return F.providerEdit },
    admin_provider_create: b => { calls.push(b); return F.providerEdit },
    admin_scholarship_links_read: F.scholarshipLinks,
    admin_scholarship_links_detail: b => { calls.push({ detail: b }); return F.scholarshipLinkDetail },
    admin_scholarship_links_decide: b => { calls.push(b); return { ...F.scholarshipLinkDetail, result: { applied: true, accepted: 1, rejected: 580, sweep_removed: 24 } } },
    admin_fee_rules_read: F.feeRules,
    admin_fee_rule_preview: b => { calls.push({ preview: b }); return F.feeRulePreview },
    admin_fee_rule_control: b => { calls.push(b); return { ...F.feeRules, result: b.p_action === 'approve' ? { admitted: 214, ambiguous: 0, already_had_fee: 0, entered_by_hand: 0 } : null } },
    admin_services_read: F.services,
    admin_services_control: b => { calls.push(b); const off = b.p_kind === 'model' && !b.p_enabled; return { ...F.services, models: F.services.models.map(m => m.id === b.p_id ? { ...m, enabled: b.p_enabled, steps: m.steps.map(x => ({ ...x, active: off ? false : x.active })) } : m), services: F.services.services.map(x => x.id === b.p_id ? { ...x, enabled: b.p_enabled } : x), steps_switched_off: off ? 2 : 0 } },
    admin_catalogue_edit_rows: b => { calls.push({ editRows: b }); return b.p_type === 'course' ? F.courseEditRows : b.p_type === 'scholarship' ? F.scholarshipEditRows : b.p_type === 'campus' ? F.campusEditRows : { can_edit: true, rows: {} } },
    admin_scholarship_edit: b => { calls.push(b); return {} },
    admin_campus_edit: b => { calls.push(b); return {} },
    admin_reference_sources_read: F.referenceSources,
    admin_reference_source_save: b => { calls.push({ refSave: b }); return { ...F.referenceSources, items: F.referenceSources.items.map(x => x.id === b.p_id ? { ...x, ...(b.p_fields.uses ? { uses: b.p_fields.uses } : {}), ...(b.p_fields.name ? { name: b.p_fields.name } : {}), ...('enabled' in b.p_fields ? { enabled: b.p_fields.enabled } : {}) } : x), saved: b.p_id || 'r-new' } },
    admin_reference_source_action: b => { calls.push({ refAction: b }); return { ...F.referenceSources, items: F.referenceSources.items.map(x => x.id === b.p_id ? { ...x, checking: b.p_action === 'check', retired: b.p_action === 'retire' } : x) } },
    admin_key_dates_read: F.keyDates,
    admin_key_date_save: b => { calls.push({ dateSave: b }); return { ...F.keyDates, items: F.keyDates.items.map(x => x.id === b.p_id ? { ...x, ...b.p_fields } : x), saved: b.p_id || 'd-new' } },
    admin_key_date_action: b => { calls.push({ dateAction: b }); return { ...F.keyDates, items: F.keyDates.items.map(x => x.id === b.p_id ? { ...x, status: b.p_action === 'cancel' ? 'cancelled' : 'active' } : x) } },
    admin_waiting_read: F.waiting,
    // v2.15.301: Dashboard › Waiting for you reads the Inbox summary (tests of the Inbox itself route this RPC themselves)
    admin_layer4_inbox: b => b.p_action === 'summary' ? F.inboxSummary : { items: [], total: 0 },
    admin_course_links_read: { ...F.courseLinks, can_edit: rank >= 3 },
    admin_course_link_edit: b => { calls.push({ linkEdit: b }); return F.courseLinks },
    admin_course_applicants_edit: b => { calls.push({ applicants: b }); return { ...F.courseLinks, applicants: { ...F.courseLinks.applicants, ...b.p_args, basis: 'Set by hand' } } },
    admin_provider_applicants_read: { ...F.providerApplicants, can_edit: rank >= 4 },
    admin_provider_applicants_edit: b => { calls.push({ providerApplicants: b }); return {} },
    admin_link_refresh_read: { ...F.linkRefresh, can_edit: rank >= 4 },
    admin_link_refresh_edit: b => { calls.push({ linkRefresh: b }); return F.linkRefresh },
    admin_provider_fee_schedules_read: b => b?.p_source_id ? { ...F.feeScheduleRows, can_decide: rank >= 6 } : { ...F.feeSchedules, can_decide: rank >= 6 },
    admin_ranking_link: b => { calls.push({ rankingLink: b }); return { linked: true, observations_linked: 7 } },
    admin_provider_policies_read: b => b?.p_id ? F.policyRows : { ...(b?.p_kind === 'intake_calendar' ? F.calendarPolicies : F.englishPolicies), can_decide: rank >= 6 },
    admin_semester_intakes_read: { can_set: rank >= 6, providers: [{ provider_id: 'pv-byhand', provider: 'Byhand University', reviews: 45, answerable: 0, periods: ['semester 1', 'semester 2', 'trimester 3'], months: {}, calendar_url: 'https://byhand.edu.au/calendar', sample: 'Semester 1 | Semester 2' }] },
    admin_provider_calendar_set: b => { calls.push({ calendarSet: b }); return { id: 'cal-byhand', to_answer: 44 } },
    admin_provider_policy_decide: b => { calls.push({ policyDecide: b }); return { status: b.p_action === 'approve' ? 'approved' : 'rejected', written: 197 } },
    admin_provider_policy_decide_bulk: b => { calls.push({ policyBulk: b }); return { done: b.p_ids.length, to_fill: 197, skipped: [] } },
    admin_course_link_search_settings: b => { if (b?.p_monthly_credit_cap) calls.push({ searchCap: b }); return { enabled: true, monthly_credit_cap: b?.p_monthly_credit_cap ?? 50000, used_this_month: 49840, queued: 320, can_change: rank >= 6 } },
    admin_provider_fee_schedule_decide: b => { calls.push({ feeDecide: b }); return { decision: b.p_action === 'approve' ? 'approved' : 'rejected', written: 131 } },
    statistics_dataset_registry_read: F.statDatasets,
    statistics_dataset_registry_write: b => { calls.push({ datasetWrite: b }); return null },
    layer4_review_desk_v1: F.l4Desk,
    layer4_review_batches_v1: F.l4Batches,
    layer4_mass_summary: F.l4MassSummary,
    layer4_provider_departures_read: F.l4Departures,
    layer4_mass_operations_history: F.l4History,
    layer4_quality_findings_read: [], layer4_quality_diagnostics: [], layer4_scholarship_scope_groups: [], layer4_review_groups: [],
    layer3_recent_interpretations: F.layer3Recent,
    admin_source_comparison: b => b.p_entity_type === 'course' ? (courseDiffers ? F.courseComparisonDiffers : F.courseComparison) : F.scholarshipComparison,
  }
  await page.addInitScript(s => { try { localStorage.setItem('sb-example-auth-token', JSON.stringify(s)) } catch {} }, session)
  await page.route('https://example.supabase.co/**', async route => {
    const u = new URL(route.request().url())
    let body = {}
    try { body = route.request().postDataJSON() || {} } catch {}
    const json = (data, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(data) })
    if (u.pathname.startsWith('/auth/v1/user')) return json(session.user)
    if (u.pathname.startsWith('/auth/v1/')) return json(session)
    if (u.pathname === '/rest/v1/rpc/admin_read') {
      const op = body.p_operation
      ;(page.readCalls ||= []).push(body)
      if (op === 'platform_health' && healthMissing) return json({ code: 'P0001', message: 'unknown admin_read operation platform_health' }, 400)
      return json(op in adminRead ? adminRead[op] : {})
    }
    if (u.pathname.startsWith('/rest/v1/rpc/')) { const v = rpc[u.pathname.split('/').pop()]; return json(typeof v === 'function' ? v(body) : (v ?? [])) }
    if (u.pathname.endsWith('/functions/v1/toolset-runner')) { calls.push({ runnerKick: body }); return json({ ok: true, run_id: body.run_id }) }
    if (u.pathname.startsWith('/functions/v1/')) return json(u.pathname.endsWith('platform-environment-control') ? F.environmentRead : {})
    return json([])
  })
}
