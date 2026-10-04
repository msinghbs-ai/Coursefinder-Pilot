// Mocked Supabase for local admin UAT: a signed-in Platform Admin and live-shaped reads.
// Only for the local dev server (VITE_SUPABASE_URL=https://example.supabase.co); nothing reaches a real backend.
import * as F from './admin-fixtures.mjs'

export async function mockAdmin(page, { rank = 6, healthMissing = false, courseDiffers = false } = {}) {
  const context = { ...F.context, role_rank: rank, role: rank >= 6 ? 'platform_admin' : 'viewer' }
  const session = { access_token: 'mock-token', refresh_token: 'mock-refresh', token_type: 'bearer', expires_in: 360000, expires_at: Math.floor(Date.now() / 1000) + 360000, user: { id: context.user_id, email: 'admin@example.test', aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} } }
  const adminRead = {
    ranking_filters: F.rankingFilters, ranking_filter_options: F.rankingFilterOptions, ranking_observations: F.rankingObservations,
    ranking_link_candidates: F.rankingLinkCandidates, ranking_provider_search: { items: [] }, provider_ranking_history: F.providerRankingHistory,
    context, dashboard: F.dashboard, layer_status_summary: F.layerStatus, platform_health: F.platformHealth,
    live_activity: F.liveActivity, course_coverage: F.courseCoverage, course_coverage_providers: [{ id: 'prov-monash', name: 'Monash University', country: 'AU', courses: 640 }], data_quality_overview: F.dataQualityOverview,
    courses_page: F.coursesPage, course_detail: F.courseDetail, scholarships_page: F.scholarshipsPage, scholarship_detail: F.scholarshipDetail,
    layer3_queue_status: F.layer3Queue, campuses_page: F.campusesPage, enrichment_operations: F.enrichmentOps, layer2_ops_overview: F.layer2Overview, layer2_parent_runs: F.layer2Parents, layer2_ops_alerts: [], layer2_profiles: F.layer2Profiles, layer2_profile_detail: F.layer2ProfileDetail, layer2_acquisition_providers: F.environmentRead.layer2_providers, layer2_provider_routes: [{ id: 'rt1', provider_id: 'pv1', display_name: 'Direct HTTP', adapter_type: 'direct_http', priority: 10, enabled: true }],
  }
  const calls = []; page.l3calls = calls
  const rpc = {
    // Decision 222: Fetch an area on the course-page sweep; Websites to find
    admin_coverage_fetch_area: b => { calls.push({ fetchArea: b }); return b.p_action === 'options' ? F.fetchAreaOptions : b.p_action === 'scope_page' ? F.fetchAreaScope : b.p_action === 'start' ? { ...F.fetchAreaPreview, first_in_sweep: true, started: F.fetchAreaStarted } : F.fetchAreaPreview },
    admin_provider_websites: F.providerWebsites,
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
    admin_scholarship_layer_write: b => { calls.push({ p_action: b.p_action, p_args: b.p_args }); return { ok: true } },
    // Decision 252: toolsets, keys and plan limits, notices and sample runs
    admin_toolsets_read: F.toolsets,
    admin_platform_notices_read: b => F.platformNotices(b.p_layer),
    admin_toolsets_write: b => { calls.push({ toolsets: b.p_action, args: b.p_args }); return { ok: true } },
    admin_toolset_samples_read: b => F.toolsetSamples(b.p_run_id),
    admin_search_pass_read: F.searchPass,
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
    layer3_source_pattern_queue: F.layer3SourcePatterns,
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
    if (u.pathname.endsWith('/functions/v1/layer2-sync-control')) return json(body.action === 'options' ? F.layer2SyncOptions : body.action === 'preview_background' ? F.layer2SyncPreview : {})
    if (u.pathname.endsWith('/functions/v1/toolset-runner')) { calls.push({ runnerKick: body }); return json({ ok: true, run_id: body.run_id }) }
    if (u.pathname.startsWith('/functions/v1/')) return json(u.pathname.endsWith('platform-environment-control') ? F.environmentRead : {})
    return json([])
  })
}
