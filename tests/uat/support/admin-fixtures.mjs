// Live-shaped fixtures (values from the live project on 29 Sep 2026, trimmed) for the mocked admin UAT (v2.15.107). No secrets.
const now = '2026-09-29T13:19:58.605421+00:00'
export const context = { role: 'platform_admin', email: 'admin@example.test', user_id: '63ba56cb-48d4-4169-98c2-7c4d1f72925b', role_rank: 6, authenticated: true }

const checks = [
  { key: 'cron', area: 'scheduled jobs', label: 'Scheduled jobs: failures and missed runs', detail: { active_jobs: 53, jobs_failing: 0, jobs_overdue: 0 }, status: 'ok', checked_at: now },
  { key: 'edge_calls', area: 'edge functions', label: 'Edge function calls: failures and timeouts (last 30 minutes)', detail: { calls: 160, queued: 0, failures: 1, window_minutes: 30 }, status: 'ok', checked_at: now },
  { key: 'edge_deployed', area: 'edge functions', label: 'Edge functions deployed vs expected', detail: { note: 'Skipped: the live Edge function list cannot be read from the database.' }, status: 'skipped', checked_at: now },
  { key: 'coverage_queues', area: 'coverage sweep', label: 'Coverage sweep queues: read, discover, re-extract, tuition hand-off', detail: { queues: 4 }, status: 'ok', checked_at: now },
  { key: 'layer_queues', area: 'Layer 3', label: 'Layer 2 to 4 work: stuck items and review backlog', detail: { layer3_stuck_over_1h: 1, layer4_pending: 941 }, status: 'warning', checked_at: now },
  { key: 'budgets', area: 'budgets', label: 'Budgets: Firecrawl reserve and OpenRouter spend', detail: { firecrawl: { used: 13798, limit: 100000, reserve: 2000 }, openrouter_spend_24h_usd: 0.6387, openrouter_daily_ceiling_usd: 5 }, status: 'ok', checked_at: now },
  { key: 'db_capacity', area: 'storage/DB', label: 'Database size and connections', detail: { db_size: '1718 MB', connections: 12, max_connections: 60 }, status: 'ok', checked_at: now },
  { key: 'search_probe', area: 'search/API', label: 'Course search responds within 3 seconds', detail: { ms: 648, items: 5 }, status: 'ok', checked_at: now },
]
export const platformHealth = {
  data: { scholarships: 528, evidence_fetched_24h: 16014 }, jobs: { running: 6, failed_24h: 0, completed_24h: 489 },
  edge_runtime: { status: 'healthy', completed_24h: 489, active_workloads: 6 },
  api_activity: { layer3_cost_24h_usd: 0.530431, layer3_external_calls_24h: 1131, layer2_provider_requests_24h: 329 },
  security: { note: 'Security Advisor remains the authority.', status: 'reviewed_with_existing_findings' },
  scholarship_ai: { active_runs: 0 },
  generated_at: now, overall: 'warning', counts: { info: 2, warning: 1, critical: 0 },
  issues: [
    { id: 'i1', area: 'Layer 3', title: '1 Layer 3 work item(s) stuck in reserved/interpreting for more than an hour', detail: { stuck: 1, since: '2026-09-29T05:17:12.547858+00:00' }, severity: 'warning', check_key: 'layer_queues:layer3_stuck', last_seen: now, first_seen: now, occurrences: 1, acknowledged_at: null },
    { id: 'i2', area: 'storage/DB', title: 'Database is 1718 MB, over the watch level of 1024 MB', detail: { bytes: 1801383059 }, severity: 'info', check_key: 'db_capacity:size', last_seen: now, first_seen: now, occurrences: 1, acknowledged_at: null },
    { id: 'i3', area: 'Layer 3', title: 'Layer 4 review backlog grew by 809 in 24 hours (941 waiting)', detail: { pending: 941, created_24h: 842, decided_24h: 33 }, severity: 'info', check_key: 'layer_queues:layer4_backlog', last_seen: '2026-09-29T12:19:45+00:00', first_seen: '2026-09-28T13:19:45+00:00', occurrences: 3, acknowledged_at: null },
  ],
  checks,
  history: Array.from({ length: 14 }, (_, i) => ({ day: `2026-09-${String(16 + i).padStart(2, '0')}`, warning: i === 13 ? 1 : i === 9 ? 2 : 0, critical: i === 10 ? 1 : 0 })),
}

export const dashboard = { jobs: 11599, courses: 43639, campuses: 3949, evidence: 50638, providers: 3092, attributes: 4, operational: { evidence_24h: 16035, running_jobs: 6, latest_job_at: now, failed_jobs_24h: 0, search_row_count: 32453, search_rebuilt_at: now, completed_jobs_24h: 497 }, snapshot_at: now, open_reviews: 941, scholarships: 528, recent_activity: [{ id: 'a1', kind: 'evidence', title: 'Source Snapshot', detail: 'Evidence captured', status: 'captured', occurred_at: now }], search_documents: 32453 }
export const layerStatus = { layer1: { failed_24h: 0, running_jobs: 0, active_sources: 32, latest_activity: now }, layer2: { evidence_24h: 13832, processed_24h: 1297, active_batches: 35, wave_pending_courses: 501 }, layer3: { calls_24h: 1131, tokens_24h: 6505643, recorded_cost_24h: 0.530431, qualified_profiles: 1, interpretations_24h: 1133, pending_evidence_candidates: 390 }, layer4: { pending_reviews: 941, active_overrides: 0, publication_decisions: 0 }, snapshot_at: now }

export const courseCoverage = { tier: null, tiers: [{ tier: 'rest', courses: 11393, providers: 1438 }, { tier: 'top_10', courses: 5260, providers: 10 }, { tier: 'top_11_40', courses: 6828, providers: 30 }, { tier: 'top_41_100', courses: 2497, providers: 60 }], trend: [{ date: '2026-09-29', total: 25978, admitted: 25944, attribute: 'campus' }, { date: '2026-09-29', total: 25978, admitted: 25978, attribute: 'duration' }, { date: '2026-09-29', total: 25978, admitted: 3078, attribute: 'english' }, { date: '2026-09-29', total: 25978, admitted: 497, attribute: 'intakes' }, { date: '2026-09-29', total: 25978, admitted: 8092, attribute: 'official_url' }, { date: '2026-09-29', total: 25978, admitted: 1077, attribute: 'provider_tuition' }, { date: '2026-09-29', total: 25978, admitted: 25795, attribute: 'registered_tuition' }], courses: 25978, providers: 1538, attributes: [{ total: 25978, states: { blocked: 1467, admitted: 8092, candidate: 10, in_review: 42, no_website: 3033, page_found: 1313, site_known: 12017, not_on_page: 4 }, attribute: 'official_url' }, { total: 25978, states: { blocked: 1467, admitted: 1077, candidate: 969, in_review: 784, no_website: 3033, page_found: 1283, site_known: 11871, not_on_page: 5494 }, attribute: 'provider_tuition' }, { total: 25978, states: { blocked: 1467, admitted: 3078, candidate: 8, no_website: 3033, page_found: 1312, site_known: 11977, not_on_page: 5103 }, attribute: 'english' }, { total: 25978, states: { blocked: 1467, admitted: 497, candidate: 1876, no_website: 3033, page_found: 1313, site_known: 12059, not_on_page: 5733 }, attribute: 'intakes' }, { total: 25978, states: { admitted: 25795, missing_l1: 183 }, attribute: 'registered_tuition' }, { total: 25978, states: { admitted: 25978 }, attribute: 'duration' }, { total: 25978, states: { admitted: 25944, missing_l1: 34 }, attribute: 'campus' }], computed_at: '2026-09-29T12:47:00.088189+00:00', completeness: { trend: [{ date: '2026-09-29', courses: 25978, completeness: 49.8, accounted_pct: 64, fully_complete: 404 }], courses: 25978, attributes: 7, by_admitted: [{ courses: 208, admitted: 2 }, { courses: 17381, admitted: 3 }, { courses: 5335, admitted: 4 }, { courses: 2166, admitted: 5 }, { courses: 484, admitted: 6 }, { courses: 404, admitted: 7 }], completeness: 49.8, accounted_pct: 64, fully_complete: 404 }, completeness_states: [{ total: 25978, states: { zero: 0, stale: 0, present: 8092, rejected: 0, ambiguous: 52, suppressed: 0, source_null: 4, not_applicable: 0, not_yet_enriched: 17830 }, attribute: 'official_url' }, { total: 25978, states: { present: 1077, ambiguous: 1753, source_null: 5494, not_yet_enriched: 17654 }, attribute: 'provider_tuition' }, { total: 25978, states: { present: 25795, source_null: 183 }, attribute: 'registered_tuition' }], completeness_state_map: { admitted: 'present', candidate: 'ambiguous', in_review: 'ambiguous', missing_l1: 'source_null', not_on_page: 'source_null' } }

export const dataQualityOverview = {
  scope: { default_scope: 'AU+NZ' }, policy: { reason: 'Regulatory authority, enrichment coverage, Search admission and publication are independent decisions.' },
  metrics: [
    { domain: 'regulatory_fee', label: 'Regulatory fee', definition: 'Registered tuition from the regulator.', authority: 'Layer 1 regulator', entity_type: 'course', scope_count: 33105, applicable_count: 26648, readiness_pct: 99.28, states: { present: 26326, source_null: 191, not_applicable: 6457, zero: 131 } },
    { domain: 'official_url', label: 'Official course page', definition: 'Provider page bound to the course.', authority: 'Layer 2 provider source', entity_type: 'course', scope_count: 33105, applicable_count: 33105, readiness_pct: 24.4, states: { present: 8092, not_yet_enriched: 24961, ambiguous: 52 } },
    { domain: 'provider_identity', label: 'Provider identity', definition: 'Provider registered with the regulator.', authority: 'Layer 1 regulator', entity_type: 'provider', scope_count: 3092, applicable_count: 3092, readiness_pct: 100, states: { present: 3092 } },
  ],
}

export const courseRow = { id: '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5', course_id: '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5', canonical_title: 'Associate Degree in Business', provider_name: 'RMIT University', course_code: '111279A', subdivision_name: 'Victoria', level_name: 'Associate Degree', field_of_study: 'Management and Commerce', fee_amount: 74880, completeness_score_v2: 71, last_verified_at: '2026-09-26T13:39:49+00:00' }
export const coursesPage = { total: 26648, items: [courseRow, { ...courseRow, id: 'c2', course_id: 'c2', canonical_title: 'Bachelor of Business (Accountancy)', course_code: '003473J', fee_amount: 125760 }] }
export const courseDetail = { id: courseRow.id, stable_key: 'au-cricos-111279A', canonical_title: 'Associate Degree in Business', display_title: 'Associate Degree in Business', provider_id: 'p1', provider_name: 'RMIT University', course_code: '111279A', country_code: 'AU', subdivision_name: 'Victoria', level_name: 'Associate Degree', field_name: 'Management and Commerce', duration_value: 104, duration_unit: 'weeks', delivery_mode: 'On campus', lifecycle_status: 'active', publication_status: 'published', course_url: 'https://www.rmit.edu.au/study-with-us/levels-of-study/undergraduate-study/associate-degrees/associate-degree-in-business-ad029', last_verified_at: '2026-09-26T13:39:49+00:00', campuses: [{ name: 'RMIT University - 124 Latrobe Street, Melbourne' }], fee_summary: { cricos_registered: [{ fee_type: 'tuition', amount: 74880, currency_code: 'AUD', basis: 'registered_total_course' }], provider_current: [{ fee_type: 'provider_current_tuition', amount: 37440, currency_code: 'AUD', basis: 'annual', fee_year: 2027 }] }, course_scholarships: { items: [] } }
export const courseComparison = { entity_type: 'course', id: courseRow.id, provider: { url: courseDetail.course_url, read_at: '2026-09-29T04:16:45.230799+00:00', tuition: { basis: 'annual', amount: 37440, currency: 'AUD', fee_year: 2027, evidence_id: '02f76986-f7f6-4b7c-9671-36b67a9c4969', source_type: 'provider_course_page', verified_at: '2026-08-20T00:20:10+00:00' }, campuses: null, duration: null }, regulator: { tuition: { basis: 'registered_total_course', amount: 74880, currency: 'AUD', fee_year: null, evidence_id: '84c30217-2f91-4e48-b4f3-846f861c0bcd', verified_at: '2026-09-26T13:39:49+00:00', per_year_estimate: 37440 }, campuses: ['RMIT University - 124 Latrobe Street, Melbourne'], duration: { unit: 'weeks', value: 104 }, cricos_code: '111279A' } }
// A second course where the values differ, to show highlighting.
export const courseComparisonDiffers = { ...courseComparison, provider: { ...courseComparison.provider, tuition: { ...courseComparison.provider.tuition, amount: 39360 } } }

export const scholarshipRow = { id: '5f92fc8c-ad2b-5182-a3b7-2e9bba5b3d99', name: 'RMIT Irana Turynska Scholarship', provider_name: 'RMIT University', scholarship_type: 'provider_scholarship', audience: 'international', award_value_text: 'AUD $10,000 annually', publication_status: 'published' }
export const scholarshipsPage = { total: 528, items: [scholarshipRow, { ...scholarshipRow, id: 's2', name: 'RMIT David Phillips Memorial Scholarship', award_value_text: 'AUD $5,000 annually' }] }
export const scholarshipDetail = { id: scholarshipRow.id, stable_key: 'sch-rmit-irana-turynska', name: 'RMIT Irana Turynska Scholarship', provider_name: 'RMIT University', type: 'provider_scholarship', audience: 'international', award_value_text: 'AUD $10,000 annually', lifecycle_status: 'active', publication_status: 'published', source_url: 'https://www.rmit.edu.au/scholarships/coursework/irana-turynska', identifiers: [], windows: [], award_tiers: [] }
export const scholarshipComparison = { entity_type: 'scholarship', id: scholarshipRow.id, current: { source_url: 'https://www.rmit.edu.au/scholarships/coursework/irana-turynska', value_text: 'AUD $10,000 annually', closing_date: null }, provider: { url: 'https://www.rmit.edu.au/scholarships/coursework/irana-turynska', value: { type: 'ambiguous', up_to: true, amounts: [20000, 10000], percentages: [] }, levels: ['postgraduate_coursework', 'undergraduate'], heading: 'Irana Turynska Scholarship', read_at: '2026-09-29T12:47:36.332184+00:00', deadline: '2026-10-06', url_source: 'discovered', evidence_id: 'd53b931f-275c-45aa-a3ae-a1de801689cb', read_status: 'read', international: true }, government: { url: 'https://search.studyaustralia.gov.au/scholarship/rmit-irana-turynska-scholarship/3d26fbb4f240456a8ffc71f9bd51ecf4', amount: 10000, currency: 'AUD', value_text: 'AUD $10,000 annually', evidence_id: '1235823d-f54a-4648-a3fb-a099e94163d4', levels_text: 'Postgraduate, Undergraduate / VET', observed_at: '2026-08-18T07:19:19.288146+00:00', closing_date: null, closing_text: 'Early October', study_levels: null } }

const p = (o) => ({ aggregator_provider: 'openrouter', base_url: 'https://openrouter.ai/api/v1', max_input_tokens: 12000, max_output_tokens: 1200, requests_per_minute: 20, timeout_ms: 30000, retry_ceiling: 1, retired_at: null, fallback_profile_id: null, updated_at: '2026-09-28T09:17:39+00:00', ...o })
export const layer3Operations = {
  generated_at: now, days: 14,
  routing: [
    { status: 'active', candidates: 6, open_items: 1, task_class: 'provider_current_tuition_validation', active_code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', calls_today: 1093, active_model: 'mistralai/mistral-small-3.2-24b-instruct', layer4_items: 893, fallback_code: null, fallback_model: null, spend_today_usd: 0.50049, cost_ceiling_usd: 0.05, requests_per_day: 15000 },
    { status: 'no_qualified_model', candidates: 2, open_items: 0, task_class: 'provider_intake_validation', calls_today: 0, spend_today_usd: 0, layer4_items: 0 },
    { status: 'no_qualified_model', candidates: 2, open_items: 0, task_class: 'scholarship_detail_extract', calls_today: 0, spend_today_usd: 0, layer4_items: 0 },
    { status: 'no_qualified_model', candidates: 1, open_items: 0, task_class: 'source_pattern', calls_today: 0, spend_today_usd: 0, layer4_items: 0 },
  ],
  profiles: [
    p({ id: '03beae2f', code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', model_identifier: 'mistralai/mistral-small-3.2-24b-instruct', allowed_task_classes: ['provider_current_tuition_validation'], enabled: true, paused: false, state: 'active', qualified: true, is_retired: false, cost_ceiling_usd: 0.05, requests_per_day: 15000, calls_today: 1093, spend_today_usd: 0.50049, quality_benchmark: { pass: true }, last_test: { status: 'pass', at: '2026-09-28T09:17:39.027592+00:00', summary: 'CF-247 route-safety tuition benchmark provider 10/10; controls 5/5; calls=15; cost_usd=0.003080' } }),
    p({ id: '0ffc083a', code: 'openrouter-provider-intake-validation-mistral-medium-3-1-v1', model_identifier: 'mistralai/mistral-medium-3.1', allowed_task_classes: ['provider_intake_validation'], enabled: false, paused: true, state: 'candidate', qualified: false, is_retired: false, cost_ceiling_usd: 3, requests_per_day: 15000, calls_today: 0, spend_today_usd: 0, quality_benchmark: { pass: false }, last_test: { status: 'fail', at: '2026-09-29T12:24:03.405232+00:00', summary: 'stated exact 18/21 (0.8571); not-stated with invented intakes 0/24' } }),
    p({ id: '1280ba18', code: 'openrouter-provider-intake-validation-mistral-small-3-2-v1', model_identifier: 'mistralai/mistral-small-3.2-24b-instruct', allowed_task_classes: ['provider_intake_validation'], enabled: false, paused: true, state: 'candidate', qualified: false, is_retired: false, cost_ceiling_usd: 3, requests_per_day: 15000, calls_today: 0, spend_today_usd: 0, last_test: { status: 'fail', at: '2026-09-29T12:21:50.922031+00:00', summary: 'stated exact 16/21 (0.7619); not-stated with invented intakes 1/24' } }),
    p({ id: 'e17d8971', code: 'openrouter-provider-tuition-validation-gemini-2-5-flash-v1', model_identifier: 'google/gemini-2.5-flash', allowed_task_classes: ['provider_current_tuition_validation'], enabled: true, paused: true, state: 'retired', qualified: false, is_retired: true, retired_at: '2026-09-29T11:00:00+00:00', retired_reason: 'Failed two benchmark runs', cost_ceiling_usd: 0.05, requests_per_day: 1000, calls_today: 0, spend_today_usd: 0, last_test: { status: 'fail', at: '2026-09-25T05:16:56.647885+00:00', summary: 'provider 5/10; controls 5/5' } }),
    p({ id: '0b02920e', code: 'openrouter-free-router-v1', model_identifier: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free', allowed_task_classes: ['course_description', 'official_course_url', 'delivery_mode', 'duration'], enabled: true, paused: true, state: 'retired', qualified: false, is_retired: true, last_validation_result: { retired: true }, cost_ceiling_usd: 0, requests_per_day: 50, calls_today: 0, spend_today_usd: 0, last_test: { status: 'pass', at: '2026-08-26T00:42:53.96991+00:00', summary: 'Provider semantic cases 5/5; controls 13/13' } }),
  ],
  tests: [
    { at: '2026-09-29T12:24:03.405232+00:00', id: '1c7ff65f', calls: 44, model: 'mistralai/mistral-medium-3.1', status: 'fail', cost_usd: 0.064629, withheld: 2, profile_code: 'openrouter-provider-intake-validation-mistral-medium-3-1-v1', stated_exact: 18, stated_total: 21, control_total: 24, wrong_admitted: 1, summary: 'CF-247 A3 intake benchmark a3-holdout-1-mistral-medium-3.1: stated exact 18/21 (0.8571); not-stated with invented intakes 0/24; safety rule applied 1; cases 45/45' },
    { at: '2026-09-29T12:21:50.922031+00:00', id: 'ba21faf0', calls: 44, model: 'mistralai/mistral-small-3.2-24b-instruct', status: 'fail', cost_usd: 0.012872, withheld: 2, profile_code: 'openrouter-provider-intake-validation-mistral-small-3-2-v1', stated_exact: 16, stated_total: 21, control_total: 24, wrong_admitted: 1 },
    { at: '2026-09-28T09:17:39.027592+00:00', id: 'e2401317', calls: 15, model: 'mistralai/mistral-small-3.2-24b-instruct', status: 'pass', cost_usd: 0.00308, withheld: 0, profile_code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', stated_exact: 10, stated_total: 10, control_total: 5, wrong_admitted: 0 },
    { at: '2026-09-25T05:16:56.647885+00:00', id: 'e451479d', calls: 15, model: 'google/gemini-2.5-flash', status: 'fail', cost_usd: 0.017553, withheld: 2, profile_code: 'openrouter-provider-tuition-validation-gemini-2-5-flash-v1', stated_exact: 5, stated_total: 10, control_total: 5, wrong_admitted: 0 },
  ],
  spend: [
    { day: '2026-09-29', profile_code: 'openrouter-provider-intake-validation-mistral-medium-3-1-v1', model: 'mistralai/mistral-medium-3.1', live_calls: 0, live_cost_usd: 0, test_calls: 44, test_cost_usd: 0.064629, cost_ceiling_usd: 3, requests_per_day: 15000 },
    { day: '2026-09-29', profile_code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', model: 'mistralai/mistral-small-3.2-24b-instruct', live_calls: 1093, live_cost_usd: 0.50049, test_calls: 0, test_cost_usd: 0, cost_ceiling_usd: 0.05, requests_per_day: 15000 },
    { day: '2026-09-28', profile_code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', model: 'mistralai/mistral-small-3.2-24b-instruct', live_calls: 44, live_cost_usd: 0.036168, test_calls: 15, test_cost_usd: 0.00308, cost_ceiling_usd: 0.05, requests_per_day: 15000 },
    { day: '2026-09-24', profile_code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', model: 'mistralai/mistral-small-3.2-24b-instruct', live_calls: 248, live_cost_usd: 0.214358, test_calls: 96, test_cost_usd: 0.017584, cost_ceiling_usd: 0.05, requests_per_day: 15000 },
    { day: '2026-09-23', profile_code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', model: 'mistralai/mistral-small-3.2-24b-instruct', live_calls: 365, live_cost_usd: 0.320834, test_calls: 60, test_cost_usd: 0.008222, cost_ceiling_usd: 0.05, requests_per_day: 15000 },
  ],
}

export const environmentRead = {
  settings: [{ setting_key: 'site_url', category: 'platform', display_name: 'Site URL', setting_value: 'https://coursefinder-pilot.techm.workers.dev', management_mode: 'admin', status: 'configured', required_for_production: true }],
  integration_secrets: [
    { integration_key: 'openrouter', display_name: 'OpenRouter API key', configured: true, admin_settable: true, production_rotation_required: true, updated_at: '2026-09-20T02:00:00+00:00' },
    { integration_key: 'cloudflare_api', display_name: 'Cloudflare API token', configured: false, admin_settable: true, production_rotation_required: true },
    { integration_key: 'smtp', display_name: 'SMTP relay password', configured: false, admin_settable: true, production_rotation_required: true },
  ],
  consumer_credentials: [{ integration_key: 'website_api', display_name: 'Website API bearer token', configured: true, credential_name: 'website-2026-09', storage_mode: 'sha256_only' }],
  layer2_providers: [
    { id: 'f1', provider_key: 'firecrawl', display_name: 'Firecrawl', enabled: true, credential_configured: true, billing_config: { monthly_vendor_units_limit: 100000, stop_at_vendor_units_remaining: 2000 }, rate_limit_per_minute: 60, auth_scheme: 'bearer' },
    { id: 'z1', provider_key: 'zenrows', display_name: 'ZenRows', enabled: false, credential_configured: false, billing_config: {}, auth_scheme: 'query' },
    { id: 'pb', provider_key: 'parsebot', display_name: 'Parse.bot', enabled: false, credential_configured: true, billing_config: {}, auth_scheme: 'header' },
  ],
  layer3_profiles: [{ id: '03beae2f', code: 'openrouter-provider-tuition-validation-mistral-small-3-2-v1', aggregator_provider: 'openrouter', credential_configured: true, enabled: true, paused: false }],
  migration_manifest: [{ component_key: 'db', component_group: 'Database', display_name: 'Database schema', migration_mode: 'migrations', required: true, source_status: 'ready', target_status: 'pending', sort_order: 1 }],
  runtime: { evidence_rows: 50638, storage_objects: 61234, cron_jobs: 53, vault_secret_count: 21, evidence_absolute_storage_paths: 0 },
}
export const platformResources = { days: 30, database: { size_bytes: 1801383059 }, tables: [], daily: [], cost_model: [] }

// Layer 3 control read (shape of public.admin_layer3_control_read, 29 Sep 2026)
const tier = (tier, model, profile, right, cost, answered, up, final = false, active = true) => ({ tier, model, profile, active, final, test_right_pct: right, test_wrong: 0, cost_per_1000_usd: cost, answered_24h: answered, passed_up_24h: up, cost_24h_usd: 0.01, audits: { checked: 2, disagreed: 0 } })
export const layer3Control = {
  generated_at: now, can_control: true, credit: { remaining_usd: 19.08, observed_at: now },
  tasks: [
    { task_class: 'provider_intake_validation', label: 'Intakes', running: true, cascade: true, daily_usd: 4, spent_today_usd: 4.06, in_review: 17, last_24h: { admitted: 98, not_stated: 222, to_review: 0, retrying: 265 },
      tiers: [tier(1, 'qwen/qwen3-30b-a3b-instruct-2507', 'openrouter-intake-l3c-qwen3-30b-a3b-2507-v1', 83, 0.19, 19, 109), tier(2, 'anthropic/claude-haiku-4.5', 'openrouter-intake-l3r-claude-haiku-4-5-v1', 93.6, 3.69, 3, 106), tier(3, 'anthropic/claude-sonnet-4.6', 'openrouter-intake-l3r-claude-sonnet-4-6-v1', 93.6, 10.94, 298, 0, true)],
      addable: [] },
    { task_class: 'provider_english_validation', label: 'English requirements', running: true, cascade: true, daily_usd: 4, spent_today_usd: 4.05, in_review: 0, last_24h: { admitted: 349, not_stated: 248, to_review: 0, retrying: 247 },
      tiers: [tier(1, 'qwen/qwen3-30b-a3b-instruct-2507', 'openrouter-english-l3c-qwen3-30b-a3b-2507-v1', 91.9, 0.14, 247, 114), tier(2, 'mistralai/mistral-small-3.2-24b-instruct', 'openrouter-english-l3c-mistral-small-3-2-v1', 100, 0.25, 12, 102), tier(3, 'anthropic/claude-sonnet-4.6', 'openrouter-english-l3r-claude-sonnet-4-6-v1', 100, 10.72, 338, 0, true)],
      addable: [{ profile: 'openrouter-english-l3c-gemini-2-5-flash-lite-v1', model: 'google/gemini-2.5-flash-lite', test_right_pct: 89.2, test_wrong: 0, cost_per_1000_usd: 0.29 }] },
    { task_class: 'provider_current_tuition_validation', label: 'Tuition', running: false, cascade: false, daily_usd: 5, spent_today_usd: 0.54, in_review: 5, last_24h: { admitted: 223, not_stated: 0, to_review: 0, retrying: 1014 },
      tiers: [tier(1, 'qwen/qwen3-235b-a22b-2507', 'openrouter-tuition-l3r-qwen3-235b-2507-v1', 75, 0.55, 4, 0, true)], addable: [] },
  ],
  events: [{ at: now, kind: 'requeued_parked', detail: { note: 'parked work returned' } }, { at: now, kind: 'admin_tier_move', detail: { task: 'provider_english_validation', tier: 2 } }],
}

// Flagged values (shape of public.admin_data_flags_read, 29 Sep 2026)
export const dataFlags = {
  can_edit: true, counts: { open: 2, removed: 27 },
  items: [
    { id: 'f1', flag: 'tuition_period_assumed_annual', status: 'open', created_at: now, course_id: 'c1', course: 'Bachelor of Laws/Bachelor of Psychology', course_code: '0102000', provider: 'Edith Cowan University', amount: 54750, currency: 'AUD', basis: 'annual', fee_status: 'active', page_url: 'https://www.ecu.edu.au/example', quotes: ['International students - estimated 1st year indicative fee AUD $54,750'] },
    { id: 'f2', flag: 'tuition_period_assumed_annual', status: 'open', created_at: now, course_id: 'c2', course: 'Bachelor of Nursing', course_code: '0100001', provider: 'Example University', amount: 33600, currency: 'AUD', basis: 'annual', fee_status: 'active', page_url: null, quotes: ['Fee paying overseas: Full-time - $33,600.00 pa'] },
  ],
}

// Automations (shape of public.admin_automations_read, 29 Sep 2026)
const lastOk = { at: now, status: 'succeeded', seconds: 1.9, message: null }
export const automations = {
  generated_at: now, rank: 5,
  jobs: [
    { job: 'coverage-read', area: 'Course pages', sort: 40, label: 'Read course pages', description: 'Fetches matched course pages and saves them as evidence.', schedule: '1-59/2 * * * *', active: true, control_rank: 5, batch: 60, last: lastOk, runs_24h: 720, failed_24h: 0 },
    { job: 'coverage-discover', area: 'Course pages', sort: 20, label: 'Discover course pages', description: "Maps each provider's website to find its course pages.", schedule: '3-59/10 * * * *', active: false, control_rank: 5, batch: 8, last: { at: now, status: 'failed', seconds: 0.4, message: 'ERROR: canceling statement due to statement timeout' }, runs_24h: 144, failed_24h: 3 },
    { job: 'layer3-intake-route', area: 'Layer 3 AI', sort: 10, label: 'AI check: intakes', description: 'Sends waiting pages through the intake model cascade.', schedule: '* * * * *', active: true, control_rank: 5, batch: 25, last: lastOk, runs_24h: 1440, failed_24h: 0 },
    { job: 'course-completeness-build', area: 'Reports', sort: 10, label: 'Completeness score', description: 'Works out how complete each course and provider is.', schedule: '17 20 * * *', active: true, control_rank: 5, batch: null, last: lastOk, runs_24h: 1, failed_24h: 0 },
    { job: 'cron-history-retention', area: 'Platform upkeep', sort: 40, label: 'Trim job history', description: 'Deletes job history older than 14 days.', schedule: '41 3 * * *', active: true, control_rank: 6, batch: null, last: lastOk, runs_24h: 1, failed_24h: 0 },
  ],
  events: [{ at: now, action: 'set_every', target: 'coverage-read', detail: { minutes: 2 } }],
}

// Send back to AI (shape of public.admin_requeue_read after 20260930052000)
export const requeue = {
  can_control: true,
  groups: [
    { field: 'provider_current_tuition_validation', reason: "The page doesn't clearly show [amount] as an annual tuition fee for international students. Please check the page and confirm the fee, or mark it as not available.", items: 178, oldest: now },
    { field: 'provider_current_tuition_validation', reason: 'The page gives this fee for a different period (for example the total for the whole course), not per year. Please confirm the annual fee.', items: 23, oldest: now },
    { field: 'course_intake', reason: "The AI's answer was not fully supported by the words it quoted from the page. Please check the page. Confirm the months this course starts for international students.", items: 12, oldest: now },
  ],
  stays_with_person: { official_course_url: 42, scope_resolution: 6, provider_current_tuition_validation: 5 },
  layer3_failed: { provider_current_tuition_validation: 4 },
  layer3_waiting: { provider_intake_validation: 219, provider_english_validation: 94, provider_current_tuition_validation: 566 },
  models: {
    course_intake: [
      { profile: 'openrouter-intake-l3c-qwen3-30b-a3b-2507-v1', model: 'qwen/qwen3-30b-a3b-instruct-2507', in_cascade: true, cost_per_1000_usd: 0.19 },
      { profile: 'openrouter-intake-l3r-claude-haiku-4-5-v1', model: 'anthropic/claude-haiku-4.5', in_cascade: true, cost_per_1000_usd: 3.69 },
      { profile: 'openrouter-intake-l3r-claude-sonnet-4-6-v1', model: 'anthropic/claude-sonnet-4.6', in_cascade: false, cost_per_1000_usd: 10.94 },
    ],
    course_english: [],
    provider_current_tuition_validation: [{ profile: 'openrouter-tuition-l3r-qwen3-235b-2507-v1', model: 'qwen/qwen3-235b-a22b-2507', in_cascade: true, cost_per_1000_usd: null }],
  },
  events: [],
}

// Scholarship publishing (shape of public.admin_scholarship_publishing_read)
export const scholarshipPublishing = {
  can_control: true,
  counts: { published: 124, eligible: 2, held: 1, active: 631 },
  not_publishable_reasons: { 'no stated award value': 375, 'no provider page': 111, 'no linked course': 71 },
  eligible: [
    { id: 'e1', name: 'Doherty Supplementary Scholarship', provider: 'Australian National University', value: 'A$7,000', page: 'https://jcsmr.anu.edu.au/study/scholarships/doherty-supplementary-scholarship', courses: 290 },
    { id: 'e2', name: 'Global Excellence Scholarship', provider: 'Example University', value: '25% of tuition', page: null, courses: 40 },
  ],
  held: [{ id: 'h1', name: 'Held Scholarship', provider: 'Example University', reason: 'Value on page is for domestic students', at: now }],
  published: [{ id: 'p1', name: 'RMIT Irana Turynska Scholarship', provider: 'RMIT University', page: 'https://www.rmit.edu.au/scholarships/coursework/irana-turynska' }],
  events: [],
}

// Priority queue (shape of public.admin_priority_read, 30 Sep 2026)
export const priority = {
  can_control: true,
  pins: [
    { id: 11, kind: 'provider', target_id: 'p-melb', sort: 1, note: null, at: now, label: 'The University of Melbourne (UniMelb)', detail: 'Victoria · Australia', courses: 438 },
    { id: 12, kind: 'state', target_id: 's-vic', sort: 2, note: null, at: now, label: 'Victoria', detail: 'Australia', courses: 9120 },
  ],
  ranking: [
    { rank: 1, provider_id: 'p-melb', name: 'The University of Melbourne (UniMelb)', state: 'Victoria', country: 'AU', courses: 438, pinned_by: 'provider', pages_matched: 11, pages_waiting: 80 },
    { rank: 2, provider_id: 'p-monash', name: 'Monash University', state: 'Victoria', country: 'AU', courses: 582, pinned_by: 'state', pages_matched: 5, pages_waiting: 161 },
    { rank: 3, provider_id: 'p-unsw', name: 'UNSW Sydney', state: 'New South Wales', country: 'AU', courses: 666, pinned_by: null, pages_matched: 246, pages_waiting: 1 },
  ],
  states: [{ id: 's-nsw', name: 'New South Wales', country: 'Australia' }, { id: 's-vic', name: 'Victoria', country: 'Australia' }],
  countries: [{ id: 'c-au', name: 'Australia' }, { id: 'c-nz', name: 'New Zealand' }],
  events: [{ at: now, action: 'add', target: 'Victoria', detail: { kind: 'state' } }],
}
export const prioritySearch = [{ id: 'p-mq', label: 'Macquarie University', detail: 'New South Wales · Australia' }]

// v2.15.114 record editing
export const courseEdit = {
  course: { id: courseRow.id, provider_id: 'p1', provider: 'RMIT University', course_code: '111279A', canonical_title: 'Associate Degree in Business', display_title: 'Associate Degree in Business', description: null, duration_value: 104, duration_unit: 'weeks', delivery_mode: 'On campus', lifecycle_status: 'active', course_url: courseDetail.course_url, manual_course: false },
  official_links: [{ id: 'l1', url: courseDetail.course_url, is_primary: true, source: 'RMIT University course pages (coverage sweep)', manual: false }],
  intakes: [{ id: 'i1', label: 'February', year: 2027 }, { id: 'i2', label: 'July', year: 2027 }],
  english: [{ id: 'e1', test: 'IELTS', test_name: 'IELTS Academic', overall: 6.5, components: {} }],
  tuition: [{ id: 'f1', amount: 37440, currency: 'AUD', fee_year: 2027, basis: 'annual', source: 'Manual entry (platform operators)', manual: true }],
  locks: { tuition: { mode: 'value', at: '2026-10-01T00:10:00+00:00' } },
  history: [{ at: '2026-10-01T00:10:00+00:00', field: 'tuition', action: 'set_tuition', by: 'admin@example.test', reason: 'Checked on the RMIT website' }],
  english_tests: [{ code: 'CAE', name: 'Cambridge C1 Advanced' }, { code: 'IELTS', name: 'IELTS Academic' }, { code: 'PTE', name: 'PTE Academic' }, { code: 'TOEFL_IBT', name: 'TOEFL iBT' }],
  can_edit: true, can_manage: true,
}
export const providerEdit = {
  provider: { id: 'p1', canonical_name: 'RMIT University', display_name: 'RMIT University', website: 'https://www.rmit.edu.au', phone: null, email: null, description: null, primary_city: 'Melbourne', address_line1: null, postcode: null, lifecycle_status: 'active', country: 'Australia', state: 'Victoria', manual_provider: false, active_courses: 506 },
  course_finder: { address: 'https://www.rmit.edu.au', status: 'mapped', pages_found: 840, mapped_at: '2026-09-29T10:00:00+00:00' },
  link_recipe: null, locks: {}, history: [], can_edit: true, can_manage: true,
}

// v2.15.115 scholarship course links
export const scholarshipLinks = {
  can_decide: true,
  summary: { waiting_links: 37200, waiting_scholarships: 87, decided_scholarships: 0, accepted_links: 0, rejected_links: 0 },
  items: [
    { scholarship_id: 'sch-mgmd', name: 'Master of Global Medicines Development Pioneers Scholarship', provider: 'Monash University', award_type: 'fixed_amount', award: '$15,000', waiting: 581, proposed: 581, accepted: 0, decision: null, suggestion: { decision: 'filter', filter: { title: 'Master of Global Medicines Development' }, why: 'The name mentions one course: Master of Global Medicines Development.' } },
    { scholarship_id: 'sch-travel', name: 'Arts Equity Travel Grant', provider: 'Monash University', award_type: 'fixed_amount', award: '$3,000', waiting: 581, proposed: 581, accepted: 0, decision: null, suggestion: { decision: 'none', filter: {}, why: 'The name suggests support that is not tied to a course’s tuition (for example travel or hardship).' } },
  ],
}
export const scholarshipLinkDetail = {
  scholarship: { id: 'sch-mgmd', name: 'Master of Global Medicines Development Pioneers Scholarship', award: '$15,000', provider: 'Monash University', source_url: 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/mgmd', academic_year: 2027 },
  proposed: 581, waiting: 581,
  levels: [{ id: 'lv-mc', name: 'Masters Degree (Coursework)', count: 180 }, { id: 'lv-b', name: 'Bachelor', count: 220 }],
  fields: [{ id: 'f-health', name: 'Health', count: 90 }, { id: 'f-bus', name: 'Management and Commerce', count: 120 }],
  suggestion: { decision: 'filter', filter: { title: 'Master of Global Medicines Development' }, why: 'The name mentions one course: Master of Global Medicines Development.' },
  decision: null,
  preview: { decision: 'filter', filter: { title: 'Master of Global Medicines Development' }, matched: 1, not_matched: 580, sample_matched: [{ id: 'c-mgmd', title: 'Master of Global Medicines Development', code: '079513K' }], sample_not_matched: [] },
  can_decide: true,
}

// v2.15.116 Layer 4 batch rules (fee wording)
export const feeRules = {
  can_create: true, can_approve: true,
  rules: [
    { id: 1, provider_id: 'p-unsw', provider: 'UNSW Sydney', label: 'UNSW Sydney: Indicative First Year Fee', phrase: 'Indicative First Year Fee', basis: 'annual', url_pattern: null, status: 'draft', admitted: 0, created_at: '2026-10-01T08:00:00+10:00', note: 'International fee block' },
    { id: 2, provider_id: 'p-rmit', provider: 'RMIT University', label: 'RMIT', phrase: 'Full-fee places:', basis: 'annual', url_pattern: null, status: 'active', admitted: 89, created_at: '2026-09-28T08:00:00+10:00', approved_at: '2026-09-28T09:00:00+10:00', approved_by: 'admin@example.test', last_run_at: '2026-10-01T07:37:00+10:00' },
  ],
  suggestions: [{ provider_id: 'p-uts', provider: 'University of Technology Sydney (UTS)', phrase: 'Indicative first-year tuition fee', pages: 145, example: 'Tuition Fee Indicative first-year tuition fee $52,730', has_rule: false }],
  recent: [],
}
export const feeRulePreview = { would_admit: 214, ambiguous: 0, already_had_fee: 0, amount_range: { min: 23500, max: 99500 },
  samples: [{ course_id: 'c-1', course: 'Bachelor of Commerce/Bachelor of Information Systems', code: '068783B', amount: 56500, fee_year: 2026, text: '2026 Indicative First Year Fee $56,500', has_fee: false, amounts: 1 }] }

// v2.15.118 Platform settings › Models & services.
export const services = { can_control: true,
  models: [
    { id: 'm1', code: 'qwen3-30b', model: 'qwen/qwen3-30b-a3b', provider: 'openrouter', tasks: ['intake', 'english'], enabled: true, retired: false, qualified: true, steps: [{ task: 'english', step: 1, active: true }, { task: 'intake', step: 1, active: true }], calls_7d: 1204, cost_7d_usd: 0.84 },
    { id: 'm2', code: 'sonnet-english', model: 'anthropic/claude-sonnet', provider: 'openrouter', tasks: ['english'], enabled: false, retired: false, qualified: true, steps: [{ task: 'english', step: 3, active: false }], calls_7d: 0, cost_7d_usd: 0 },
    { id: 'm3', code: 'old-model', model: 'vendor/old-model', provider: 'openrouter', tasks: ['tuition'], enabled: false, retired: true, retired_reason: 'Failed the tuition test', qualified: false, steps: [], calls_7d: 0, cost_7d_usd: 0 },
  ],
  services: [
    { id: 's1', key: 'firecrawl', name: 'Firecrawl', type: 'firecrawl', enabled: true, credential: true, routes: 3057, last_test: { at: '2026-09-30T10:00:00Z', status: 'passed' } },
    { id: 's2', key: 'zenrows', name: 'ZenRows', type: 'zenrows', enabled: true, credential: true, routes: 2114, last_test: { at: null, status: null } },
    { id: 's3', key: 'custom-gateway', name: 'Custom gateway', type: 'custom', enabled: false, credential: false, routes: 0, last_test: { at: null, status: null } },
  ],
  events: [{ at: '2026-10-01T00:00:00Z', action: 'switch_off', target: 'anthropic/claude-sonnet', by: 'admin@example.com' }] }
