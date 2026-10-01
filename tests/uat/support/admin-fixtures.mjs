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

export const courseCoverage = { tier: null, countries: [{ code: 'AU', courses: 26103, providers: 1546 }, { code: 'NZ', courses: 6475, providers: 287 }, { code: 'CA', courses: 2382, providers: 34 }], tiers: [{ tier: 'rest', courses: 11393, providers: 1438 }, { tier: 'top_10', courses: 5260, providers: 10 }, { tier: 'top_11_40', courses: 6828, providers: 30 }, { tier: 'top_41_100', courses: 2497, providers: 60 }], trend: [{ date: '2026-09-29', total: 25978, admitted: 25944, attribute: 'campus' }, { date: '2026-09-29', total: 25978, admitted: 25978, attribute: 'duration' }, { date: '2026-09-29', total: 25978, admitted: 3078, attribute: 'english' }, { date: '2026-09-29', total: 25978, admitted: 497, attribute: 'intakes' }, { date: '2026-09-29', total: 25978, admitted: 8092, attribute: 'official_url' }, { date: '2026-09-29', total: 25978, admitted: 1077, attribute: 'provider_tuition' }, { date: '2026-09-29', total: 25978, admitted: 25795, attribute: 'registered_tuition' }], courses: 25978, providers: 1538, attributes: [{ total: 25978, states: { blocked: 1467, admitted: 8092, candidate: 10, in_review: 42, no_website: 3033, page_found: 1313, site_known: 12017, not_on_page: 4 }, attribute: 'official_url' }, { total: 25978, states: { blocked: 1467, admitted: 1077, candidate: 969, in_review: 784, no_website: 3033, page_found: 1283, site_known: 11871, not_on_page: 5494 }, attribute: 'provider_tuition' }, { total: 25978, states: { blocked: 1467, admitted: 3078, candidate: 8, no_website: 3033, page_found: 1312, site_known: 11977, not_on_page: 5103 }, attribute: 'english' }, { total: 25978, states: { blocked: 1467, admitted: 497, candidate: 1876, no_website: 3033, page_found: 1313, site_known: 12059, not_on_page: 5733 }, attribute: 'intakes' }, { total: 25978, states: { admitted: 25795, missing_l1: 183 }, attribute: 'registered_tuition' }, { total: 25978, states: { admitted: 25978 }, attribute: 'duration' }, { total: 25978, states: { admitted: 25944, missing_l1: 34 }, attribute: 'campus' }], computed_at: '2026-09-29T12:47:00.088189+00:00', completeness: { trend: [{ date: '2026-09-29', courses: 25978, completeness: 49.8, accounted_pct: 64, fully_complete: 404 }], courses: 25978, attributes: 7, by_admitted: [{ courses: 208, admitted: 2 }, { courses: 17381, admitted: 3 }, { courses: 5335, admitted: 4 }, { courses: 2166, admitted: 5 }, { courses: 484, admitted: 6 }, { courses: 404, admitted: 7 }], completeness: 49.8, accounted_pct: 64, fully_complete: 404 }, completeness_states: [{ total: 25978, states: { zero: 0, stale: 0, present: 8092, rejected: 0, ambiguous: 52, suppressed: 0, source_null: 4, not_applicable: 0, not_yet_enriched: 17830 }, attribute: 'official_url' }, { total: 25978, states: { present: 1077, ambiguous: 1753, source_null: 5494, not_yet_enriched: 17654 }, attribute: 'provider_tuition' }, { total: 25978, states: { present: 25795, source_null: 183 }, attribute: 'registered_tuition' }], completeness_state_map: { admitted: 'present', candidate: 'ambiguous', in_review: 'ambiguous', missing_l1: 'source_null', not_on_page: 'source_null' } }

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
export const scholarshipDetail = { id: scholarshipRow.id, stable_key: 'sch-rmit-irana-turynska', name: 'RMIT Irana Turynska Scholarship', provider_name: 'RMIT University', type: 'provider_scholarship', audience: 'international', award_value_text: 'AUD $10,000 annually', lifecycle_status: 'active', publication_status: 'published', source_url: 'https://www.rmit.edu.au/scholarships/coursework/irana-turynska', award_duration_basis: 'annual_program_duration', identifiers: [], windows: [], award_tiers: [], criteria: [{ id: 'cr1', criterion_type: 'student_type', operator: 'in', value_codes: ['international'], human_text: 'be an international student', status: 'active', value_json: { by: 'scholarship_sweep' } }, { id: 'cr2', criterion_type: 'academic_minimum', operator: '>=', value_text: 'GPA', value_number: 5.5, human_text: 'have a GPA of 5.5 or higher', status: 'active', value_json: { by: 'scholarship_sweep', scale: 7 } }, { id: 'cr3', criterion_type: 'study_stage', operator: 'equals', value_text: 'current', human_text: 'old reading', status: 'superseded', value_json: { by: 'scholarship_sweep' } }] }
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
    { id: 'f2', flag: 'tuition_period_assumed_annual', status: 'open', created_at: now, course_id: 'c2', course: 'Bachelor of Nursing', course_code: '0100001', provider: 'Example University', amount: 33600, currency: 'AUD', basis: 'annual', fee_status: 'active', page_url: null, schedule: { amount: 34900, year: 2027, url: 'https://example.edu.au/fees-2027.pdf' }, quotes: ['Fee paying overseas: Full-time - $33,600.00 pa'] },
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
  counts: { published: 124, eligible: 2, held: 1, active: 631, domestic_only: 1 },
  not_publishable_reasons: { 'no stated award value': 375, 'no provider page': 111, 'no linked course': 71 },
  eligible: [
    { id: 'e1', name: 'Doherty Supplementary Scholarship', provider: 'Australian National University', value: 'A$7,000', page: 'https://jcsmr.anu.edu.au/study/scholarships/doherty-supplementary-scholarship', courses: 290 },
    { id: 'e2', name: 'Global Excellence Scholarship', provider: 'Example University', value: '25% of tuition', page: null, courses: 40 },
  ],
  held: [{ id: 'h1', name: 'Held Scholarship', provider: 'Example University', reason: 'Value on page is for domestic students', at: now }],
  domestic_only: [{ id: 'd1', name: 'Women in STEM Scholarship', provider: 'Example University', page: 'https://example.edu/women-in-stem', published: true, words: 'be an Australian citizen, an Australian permanent resident or a permanent humanitarian visa holder' }],
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
    { id: 'm4', code: 'new-candidate', model: 'vendor/new-candidate', provider: 'openrouter', tasks: ['intake'], enabled: false, retired: false, qualified: false, steps: [], calls_7d: 0, cost_7d_usd: 0 },
    { id: 'm3', code: 'old-model', model: 'vendor/old-model', provider: 'openrouter', tasks: ['tuition'], enabled: false, retired: true, retired_reason: 'Failed the tuition test', qualified: false, steps: [], calls_7d: 0, cost_7d_usd: 0 },
  ],
  services: [
    { id: 's1', key: 'firecrawl', name: 'Firecrawl', type: 'firecrawl', enabled: true, credential: true, routes: 3057, last_test: { at: '2026-09-30T10:00:00Z', status: 'passed' } },
    { id: 's2', key: 'zenrows', name: 'ZenRows', type: 'zenrows', enabled: true, credential: true, routes: 2114, last_test: { at: null, status: null } },
    { id: 's3', key: 'custom-gateway', name: 'Custom gateway', type: 'custom', enabled: false, credential: false, routes: 0, last_test: { at: null, status: null } },
  ],
  events: [{ at: '2026-10-01T00:00:00Z', action: 'switch_off', target: 'anthropic/claude-sonnet', by: 'admin@example.com' }] }

// v2.15.120 Edit in list.
export const courseEditRows = { can_edit: true, rows: {
  [courseRow.id]: { display_title: 'Associate Degree in Business', duration_value: 2, duration_unit: 'years', delivery_mode: null, official_url: 'https://www.rmit.edu.au/study-with-us/levels-of-study/vocational-study/associate-degrees/associate-degree-in-business-ad021', locks: { display_title: 'value' } },
  c2: { display_title: 'Bachelor of Business (Accountancy)', duration_value: null, duration_unit: null, delivery_mode: 'On campus', official_url: null, locks: {},
    tuition: { amount: 60952, fee_year: 2027, basis: 'indicative_annual', currency: 'AUD' },
    intakes: [{ label: 'Semester 1', year: 2027, start_date: '2027-02-22' }, { label: 'Semester 2', year: 2027, start_date: '2027-07-26' }],
    english: [{ test: 'IELTS', overall: 6.5, components: { reading: 6, writing: 6 } }, { test: 'PTE', overall: 64, components: { minimum_each: 60 } }] } },
  english_tests: [{ code: 'CAE', name: 'Cambridge C1 Advanced' }, { code: 'IELTS', name: 'IELTS Academic' }, { code: 'PTE', name: 'PTE Academic' }, { code: 'TOEFL_IBT', name: 'TOEFL iBT' }] }

// v2.15.121 Reference sources and Key dates.
const refUses = [{ key: 'reference', label: 'Reference link', help: 'Shown to staff.' }, { key: 'data_source', label: 'Data source', help: 'Read by the platform.' }, { key: 'not_provider_site', label: 'Never a university website', help: 'Skipped.' }, { key: 'not_course_page', label: 'Never a course page', help: 'Refused.' }, { key: 'scholarship_placeholder', label: 'Scholarship placeholder', help: 'Needs a university page.' }, { key: 'logo_directory', label: 'Logo directory', help: 'Logos only.' }, { key: 'ranking_publisher', label: 'Ranking publisher', help: 'Default address.' }]
export const referenceSources = { can_edit: true, can_manage: true, uses: refUses,
  categories: [{ key: 'third_party_directory', label: 'Third-party directory' }, { key: 'regulatory_authority', label: 'Regulator or register' }, { key: 'official_scholarship', label: 'Official scholarships' }, { key: 'ranking_publisher', label: 'Ranking publisher' }],
  items: [
    { id: 'r1', country: 'ALL', category: 'third_party_directory', name: 'Hotcourses Abroad', url: 'https://www.hotcoursesabroad.com/', domain: 'hotcourses', uses: ['logo_directory', 'not_provider_site', 'not_course_page'], enabled: true, ref_key: null, purpose: 'University logos only.', retired: false, health: 'healthy', checked_at: '2026-10-01T01:00:00Z', http: 200, checking: false, scholarships: null },
    { id: 'r2', country: 'AU', category: 'official_scholarship', name: 'Study Australia Scholarship Search', url: 'https://search.studyaustralia.gov.au/scholarships', domain: 'studyaustralia.gov.au', uses: ['data_source', 'not_provider_site', 'not_course_page', 'scholarship_placeholder'], enabled: true, ref_key: null, purpose: 'Scholarship catalogue.', retired: false, health: 'healthy', checked_at: null, http: null, checking: false, scholarships: 111 },
    { id: 'r3', country: 'ALL', category: 'ranking_publisher', name: 'QS World University Rankings', url: 'https://www.topuniversities.com/world-university-rankings', domain: 'topuniversities.com', uses: ['ranking_publisher', 'not_provider_site'], enabled: true, ref_key: 'qs_wur', purpose: 'Ranking publisher.', retired: false, health: 'unverified', checked_at: null, http: null, checking: false, scholarships: null },
  ],
  events: [{ at: '2026-10-01T01:10:00Z', action: 'change', target: 'Hotcourses Abroad', detail: { fields: ['uses'], reason: 'Logos only' }, by: 'admin@example.com' }] }
export const keyDates = { can_edit: true, items: [
  { id: 'd1', country: 'AU', event_type: 'provider_application_window', title: 'UQ Semester 1 2027 international application deadline', source_url: 'https://study.uq.edu.au/admissions', precision: 'exact', starts_on: '2026-11-30', ends_on: null, wording: 'Semester 1: 30 November of the previous year', warning_days: 45, scope: 'provider', refresh_layer: 2, status: 'active' },
  { id: 'd2', country: 'AU', event_type: 'regulatory_dataset_release', title: 'QILT GOS 2026 release', source_url: 'https://www.qilt.edu.au/', precision: 'source_vague', starts_on: null, ends_on: null, wording: 'Usually released in late March', warning_days: 14, scope: 'country_reference', refresh_layer: null, status: 'active' } ], events: [] }

// v2.15.125 Dashboard waiting list.
export const waiting = { rank: 6, rows: [
  { key: 'review', label: 'Review items to decide', count: 1803, oldest: '2026-09-02T00:00:00Z', href: '#layer-4-review', min: 3 },
  { key: 'flags', label: 'Flagged values to check', count: 236, oldest: '2026-09-20T00:00:00Z', href: '#layer-4-review?tab=flags', min: 3 },
  { key: 'rules', label: 'Fee rules waiting for approval', count: 0, oldest: null, href: '#layer-4-review?tab=rules', min: 5 },
  { key: 'scholarship_links', label: 'Scholarships to link to courses', count: 87, oldest: '2026-09-25T00:00:00Z', href: '#scholarships?tab=links', min: 4 },
  { key: 'failed_jobs', label: 'Jobs that failed in the last 24 hours', count: 0, oldest: null, href: '#scheduled-jobs?tab=jobs', min: 4 } ] }

// Layer 3 Work queue (v2.15.127), live-shaped from 1 Oct 2026.
export const layer3Queue = { by_task_class: [
  { task_class: 'provider_current_tuition_validation', status_counts: { admitted: 1205, failed: 8, layer4_required: 712 }, total: 1925, oldest_pending_seconds: null, last_completed_at: '2026-09-30T23:48:26Z' },
  { task_class: 'provider_english_validation', status_counts: { admitted: 2999, failed: 249, layer4_required: 172, no_candidate: 2808 }, total: 6228, oldest_pending_seconds: null, last_completed_at: '2026-10-01T01:01:03Z' },
  { task_class: 'provider_intake_validation', status_counts: { admitted: 2655, failed: 281, layer4_required: 866, no_candidate: 5348, pending: 40 }, total: 9190, oldest_pending_seconds: 5400, last_completed_at: '2026-10-01T01:01:06Z' },
] }
export const layer3SourcePatterns = [
  { request_id: 'sp1', provider_name: 'Kaplan Business School', entity_id: 'p1', country_code: 'AU', status: 'queued', created_at: '2026-09-07T05:40:00Z', source_url: 'https://www.kbs.edu.au/courses', schedule_error: 'model error (provider returned 502)' },
]
export const layer3Recent = Array.from({ length: 30 }, (_, i) => ({ id: 'i' + i, created_at: new Date(Date.UTC(2026, 9, 1, 1, 0) - i * 600000).toISOString(), task_class: ['provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation'][i % 3], status: ['validated', 'no_candidate', 'escalated', 'rejected_validation'][i % 4], model_identifier: 'qwen/qwen3-30b-a3b-instruct-2507', estimated_cost_usd: 0.0002, review_state: i % 4 === 2 ? 'pending' : 'not_created', escalation_reason: i % 4 === 2 ? 'differs from value held' : null }))

// Layer 2 Source profiles (v2.15.127).
export const layer2Profiles = { total: 2, limit: 50, offset: 0, has_more: false, summary: { profiles: 2, valid: 2, healthy: 1 }, options: { countries: ['AU'], methods: ['html_scrape'], health: ['healthy', 'stale'] },
  items: [
    { profile_id: 'lp1', source_label: 'RMIT University courses', profile_key: 'au-rmit-courses', country_code: 'AU', acquisition_method: 'html_scrape', affected_provider_name: 'RMIT University', target_entity_type: 'course', current_version: 3, validation_status: 'valid', health: 'healthy', enabled: true, paused: false, last_success_at: '2026-09-30T22:00:00Z', last_inventory_count: 412 },
    { profile_id: 'lp2', source_label: 'Monash University courses', profile_key: 'au-monash-courses', country_code: 'AU', acquisition_method: 'html_scrape', affected_provider_name: 'Monash University', target_entity_type: 'course', current_version: 1, validation_status: 'valid', health: 'stale', enabled: true, paused: false, last_success_at: '2026-09-20T22:00:00Z', last_inventory_count: null },
  ] }
export const layer2ProfileDetail = { profile: { id: 'lp1', profile_key: 'au-rmit-courses', source_label: 'RMIT University courses', country_code: 'AU', acquisition_method: 'html_scrape', target_entity_type: 'course', enabled: true, paused: false }, current_version: { id: 'v3', version_no: 3, validation_status: 'valid', configuration: { base_domain: 'www.rmit.edu.au' } }, history: [], recent_jobs: [], recent_evidence: [] }

// Layer 2 tabs (v2.15.128), live-shaped from 1 Oct 2026.
const hr = (h, o) => ({ hour_utc: `2026-09-30T${String(h).padStart(2, '0')}:00:00+00:00`, country_code: 'AU', domain: 'course_facts', items: 0, fetched: 0, fetch_failures: 0, official_urls_found: 0, intakes_found: 0, english_requirements_found: 0, provider_current_tuition_found: 0, scholarships_found: 0, facts_admitted_lower_bound: 0, unchanged: 0, rejected_or_blocked: 0, layer3_escalated: 0, layer4_referred: 0, courses_improved_lower_bound: 0, vendor_units: 0, vendor_cost_usd: 0, retries: 0, http_429: 0, http_5xx: 0, other_runtime_failures: 0, p50_response_ms: null, p95_response_ms: null, p50_extraction_ms: null, p95_extraction_ms: null, ...o })
export const enrichmentOps = {
  work: { queued: 0, processing: 0, fetched: 64, fetch_failures: 0, evidence_24h: 0, layer3_24h: 2082, admitted_source_records_24h: 1380, vendor_units_24h: 64, vendor_cost_usd_24h: 0, http_429_24h: 0, http_5xx_24h: 0 },
  coverage: [
    { country_code: 'AU', field_key: 'english_requirements', current: 6461, total: 26103, coverage_pct: 24.75, added_hour: 0, added_day: 309, remaining: 19642, queueable: 12, blocked: 1554, awaiting_qualification: 18076 },
    { country_code: 'AU', field_key: 'intake_availability', current: 8120, total: 26103, coverage_pct: 31.1, added_hour: 0, added_day: 412, remaining: 17983, queueable: 40, blocked: 1610, awaiting_qualification: 16333 },
    { country_code: 'AU', field_key: 'provider_current_international_tuition', current: 3804, total: 26103, coverage_pct: 14.57, added_hour: 0, added_day: null, remaining: 22299, queueable: 0, blocked: 30, awaiting_qualification: 22269 },
  ],
  stop_reasons: [{ reason: 'layer3_required', items: 17107, fields_resolved: 56, fields_targeted: 17268 }],
  providers: [{ provider: 'firecrawl', succeeded: 1081, failed: 23, retries: 0, p50_ms: 9192.9, p95_ms: 19152.5 }, { provider: 'direct_http', succeeded: 410, failed: 61, retries: 4, p50_ms: 812, p95_ms: 3020 }],
  hourly: [hr(14, { items: 160, layer3_escalated: 160 }), hr(15, { items: 1539, layer3_escalated: 1539 }), hr(16, { items: 363, fetched: 64, intakes_found: 22, english_requirements_found: 9, facts_admitted_lower_bound: 31, layer3_escalated: 363, vendor_units: 64 })],
  blockers: [{ country_code: 'AU', field_key: 'provider_current_international_tuition', reason: 'source_profile_qualification_required', courses: 22269 }, { country_code: 'AU', field_key: 'english_requirements', reason: 'no_official_course_url', courses: 1554 }],
  admissions: [{ id: 'ad1', status: 'admitted', field_key: 'official_course_url', course_title: 'Graduate Diploma in Mental Health Nursing', provider_name: 'RMIT University (RMIT)', evidence_id: '1c79b982-9e44-438e-83b9-d0083914565f', reason_code: 'qualified_exact_cricos_evidence_match' }],
  recent_items: [{ run_item_id: 'ri1', event_at: '2026-10-01T01:01:03Z', provider_name: 'Flinders University', course_code: '073817K', status: 'layer3_required', fields_resolved: 0, fields_targeted: 1, evidence_count: 0, stop_reason: 'layer3_required', evidence_id: null }],
  observed_at: '2026-10-01T02:10:00Z',
}
export const layer2Overview = {
  recent_runs: [{ id: 'run1', status: 'running', started_at: '2026-09-29T05:02:46Z', created_at: '2026-09-29T05:02:46Z', completed_at: null, target_count: 16844, processed_count: 16844, progress_percent: 100, resolved_l2_count: 0, escalated_l3_count: 16844, blocked_count: 0, vendor_cost_usd: 0, runtime_seconds: 167718 }],
  recent_provider_attempts: [{ id: 'at1', provider_name: 'Firecrawl', provider_key: 'firecrawl', attempt_no: 3, response_http_status: 200, status: 'succeeded', started_at: '2026-09-30T16:28:18Z', completed_at: '2026-09-30T16:28:21Z', request_url: 'https://www.boxhill.edu.au/courses/study-options/', evidence_id: 'a2de1449-6b0f-4916-9446-ad9686f34bec' }],
  evidence_summary: { count: 50638 }, scope_summary: { course_catalogue_total: 26103, course_queueable_total: 12 }, outcomes: {}, sources: [],
}
export const layer2Parents = [{ parent_run_id: 'f120fb4b-ec69-4f2c-8147-550a338c6f3d', status: 'cancelled', scope_type: 'university', country_code: 'AU', total_items: 263, processed_items: 0, resolved_l2: 0, escalated_l3: 25, blocked: 0, child_jobs: 25, evidence_count: 75, completed_items: 0, rescheduled_items: 0, failed_items: 0, recorded_failed_items: 0, scheduled_remainder: 263, updated_at: '2026-09-26T06:52:50Z' }]
export const layer2SyncOptions = { countries: [{ code: 'AU', name: 'Australia', providers: 186, courses: 26103 }, { code: 'NZ', name: 'New Zealand', providers: 34, courses: 4210 }] }
export const layer2SyncPreview = { university_count: 186, catalogue_count: 26103, qualified_provider_count: 41, qualification_required_count: 145, queueable_count: 12, production_accepted_wave_size: 50, execution_policy: { qualification_provider_wave_size: 5, qualification_sample_size: 3, production_target_wave_size: 50 }, firecrawl_budget: { used_units: 1124, limit_units: 100000 }, firecrawl: { usable_remaining_units: 88876, reserve_units: 10000 } }

// Layer 4 review (v2.15.129).
export const l4Desk = { summary: { waiting: 1803, oldest_days: 11, by_task: { Intakes: 866, Tuition: 712, 'English requirements': 225 } }, items: [
  { id: 'q1', status: 'pending', task: 'Intakes', age_days: 11, entity: { title: 'Bachelor of Nursing', code: '012345A', provider: 'RMIT University' }, suggestion: { action: 'reject', text: 'No intake dates on the page' }, claim_active: true, claimed_by_me: true },
  { id: 'q2', status: 'pending', task: 'Tuition', age_days: 3, entity: { title: 'Master of Data Science', code: '098765B', provider: 'Monash University' }, suggestion: { action: 'approve', text: 'Page shows a yearly fee' }, claim_active: true, claimed_by_me: false },
] }
export const l4Batches = { can_apply: true, groups: [{ key: 'g1', task: 'Intakes', action: 'reject', text: 'No intake dates on the page', count: 120, oldest_days: 11, can_approve: false, item_ids: ['q1'], samples: [{ id: 'q1', title: 'Bachelor of Nursing' }] }] }
export const l4MassSummary = { role_rank: 6, mass_mutation_allowed: true, open_findings: 0, scholarship_scope_pending: 37200, generic_review_pending: 1803 }
export const l4Departures = [{ id: 'dp1', provider_name: 'Example Institute', country_code: 'AU', status: 'pending', detected_at: '2026-09-20T00:00:00Z' }]
export const l4History = [{ id: 'h1', target_kind: 'course_tuition', action: 'fee_wording_rule_run', reason: 'Fee wording rule #1: UNSW Sydney', created_at: '2026-09-30T23:48:26Z', before_count: 214, affected_count: 214 }]

// Campus and scholarship edit in list (v2.15.130).
export const campusesPage = { total: 2, items: [{ id: 'cp1', name: 'RMIT City', provider_name: 'RMIT University', campus_code: '00122A', city: 'Melbourne' }, { id: 'cp2', name: 'RMIT Brunswick', provider_name: 'RMIT University', campus_code: '00122B', city: 'Brunswick' }] }
export const campusEditRows = { can_edit: true, rows: { cp1: { name: 'RMIT City', address_line1: '124 La Trobe Street', city: 'Melbourne', postcode: '3000', phone: null, website: null, locks: {} }, cp2: { name: 'RMIT Brunswick', address_line1: null, city: 'Brunswick', postcode: '3056', phone: null, website: null, locks: { city: 'value' } } } }
export const scholarshipEditRows = { can_edit: true, rows: {
  '5f92fc8c-ad2b-5182-a3b7-2e9bba5b3d99': { name: 'RMIT Irana Turynska Scholarship', award_value_text: 'AUD $10,000 annually', award_amount: 10000, award_percentage: null, application_close_date: '2026-11-30', source_url: 'https://www.rmit.edu.au/scholarships/irana', locks: {} },
  s2: { name: 'RMIT David Phillips Memorial Scholarship', award_value_text: 'AUD $5,000 annually', award_amount: null, award_percentage: null, application_close_date: null, source_url: null, locks: { award_amount: 'value' } } } }

// Rankings › Datasets (v2.15.131).
export const statDatasets = [
  { dataset_key: 'qs_wur', label: 'QS World University Rankings', dataset_type: 'ranking', description: 'Global institutional ranking.', display_enabled: true, display_order: 30, compare_enabled: true, source_authority: 'QS Quacquarelli Symonds', admin_import_system: 'qs_wur' },
  { dataset_key: 'arwu', label: 'Academic Ranking of World Universities', dataset_type: 'ranking', description: 'Shanghai ranking.', display_enabled: false, display_order: 50, compare_enabled: true, source_authority: 'ShanghaiRanking', admin_import_system: null },
]

// v2.15.133 (Decisions 200–201): course links, who can apply, link refresh.
export const courseLinks = {
  can_edit: true,
  types: [
    { code: 'official_course', label: 'Official course page', applicant: 'any' },
    { code: 'handbook', label: 'Handbook entry', applicant: 'any' },
    { code: 'international_page', label: 'International students page', applicant: 'international' },
    { code: 'application', label: 'How to apply', applicant: 'any' },
    { code: 'admission_centre', label: 'Admission centre listing', applicant: 'domestic' },
    { code: 'regulator_listing', label: 'Regulator listing', applicant: 'any' },
  ],
  links: [
    { id: 'l-off', link_type: 'official_course', type_label: 'Official course page', url: 'https://www.rmit.edu.au/study-with-us/levels-of-study/undergraduate-study/bachelor-degrees/bachelor-of-business-bp343', label: 'Official provider course page', status: 'active', is_primary: true, last_verified_at: '2026-10-01T06:00:00Z', source: 'RMIT course pages (coverage sweep)', by_hand: false },
    { id: 'l-hb', link_type: 'handbook', type_label: 'Handbook entry', url: 'https://www.rmit.edu.au/students/my-course/program-structures/bp343', label: 'Handbook entry', status: 'active', is_primary: true, last_verified_at: null, source: 'Manual entry', by_hand: true },
  ],
  locks: { 'link:handbook': 'value' },
  applicants: { open_to_international: true, open_to_domestic: null, basis: 'CRICOS course registration', provider_enrols_international: true, english_expected: true, provider: 'RMIT University', country: 'AU' },
}
export const providerApplicants = { can_edit: true, enrols_international: true, basis: 'CRICOS provider registration', country: 'AU', locked: false, courses: { open_to_international: 412, domestic_only: 0, not_known: 3, set_by_hand: 1 } }
export const linkRefresh = {
  can_edit: true,
  policies: [
    { id: 'p1', country: null, country_name: null, provider: null, link_type: 'official_course', type_label: 'Official course page', every_days: 30, active: true, last_run_at: '2026-10-01T07:10:00Z', last_result: { reread: 0, searched_again: 0, verified: 295, unverified: 0, regulator_added: 0 } },
    { id: 'p2', country: null, country_name: null, provider: null, link_type: 'regulator_listing', type_label: 'Regulator listing', every_days: 90, active: true, last_run_at: null, last_result: null },
  ],
  portals: [
    { code: 'nzqa', label: 'NZQA qualification search', country: 'NZ', kind: 'regulator', link_type: 'regulator_listing', base_url: 'https://www.nzqa.govt.nz/nzqf/search/', applicant: 'any', active: true, every_days: 90 },
    { code: 'uac', label: 'UAC course search (NSW, ACT)', country: 'AU', kind: 'admission_centre', link_type: 'admission_centre', base_url: 'https://uac.edu.au/course-search/', applicant: 'domestic', active: false, every_days: 90 },
  ],
  types: [{ code: 'official_course', label: 'Official course page' }, { code: 'handbook', label: 'Handbook entry' }, { code: 'regulator_listing', label: 'Regulator listing' }],
  countries: ['AU', 'CA', 'NZ'],
}
export const feeSchedules = {
  can_decide: true,
  totals: { providers_searched: 12, providers_queued: 138, documents_found: 31, documents_read: 9, with_fee_rows: 2, awaiting_decision: 1 },
  documents: [
    { id: 'fs1', provider_id: 'p-acu', provider: 'Australian Catholic University', url: 'https://www.acu.edu.au/media/acu-2027-schedule-of-tuition-fees.pdf', fee_year: '2027', read_at: '2026-10-01T09:00:00Z', decision: null, decided_at: null, apply_summary: null, rows: 152, new: 131, same: 0, differs: 2, no_course: 19 },
    { id: 'fs2', provider_id: 'p-x', provider: 'Example Institute', url: 'https://example.edu.au/fees.pdf', fee_year: '2027', read_at: '2026-10-01T08:00:00Z', decision: 'approved', decided_at: '2026-10-01T08:30:00Z', apply_summary: { written: 20, refused: 0 }, rows: 22, new: 0, same: 20, differs: 0, no_course: 2 },
  ],
}
export const feeScheduleRows = { can_decide: true, rows: [
  { row_id: 'r1', course_code: '001293G', course_id: 'c1', course_title: 'Bachelor of Nursing', amount: 39672, currency_code: 'AUD', basis: 'annual', fee_year: 2027, current_amount: null, current_basis: null, outcome: 'new' },
  { row_id: 'r2', course_code: '079454F', course_id: 'c2', course_title: 'Bachelor of Accounting and Finance', amount: 36016, currency_code: 'AUD', basis: 'annual', fee_year: 2027, current_amount: 35000, current_basis: 'annual', outcome: 'differs' },
] }
export const rankingFilters = { systems: [{ code: 'qs_wur', label: 'QS World University Rankings' }], years: [2027, 2026], editions: [], statuses: [] }
export const rankingFilterOptions = {
  can_link: true, linked: 37, not_linked: 1, not_linked_in_catalogue_countries: 1,
  countries: [{ value: 'Australia', count: 38, in_catalogue: true }, { value: 'Canada', count: 31, in_catalogue: true }, { value: 'Japan', count: 52, in_catalogue: false }],
  states: [{ value: 'AU-VIC', label: 'Victoria', count: 7 }, { value: 'AU-NSW', label: 'New South Wales', count: 11 }],
  providers: [{ value: 'p-mel', label: 'The University of Melbourne' }],
}
export const rankingObservations = { total: 2, limit: 50, offset: 0, items: [
  { id: 'o1', system_code: 'qs_wur', ranking_name: 'QS World University Rankings', edition_year: 2027, publisher_institution_id: 'pi-mel', publisher_institution_name: 'The University of Melbourne', country_text: 'Australia', provider_id: 'p-mel', provider_name: 'The University of Melbourne', state_code: 'AU-VIC', state_name: 'Victoria', rank_display: '13', rank_exact: 13, overall_score: 90.8, evidence_artifact_id: null },
  { id: 'o2', system_code: 'qs_wur', ranking_name: 'QS World University Rankings', edition_year: 2027, publisher_institution_id: 'pi-cqu', publisher_institution_name: 'Central Queensland University Australia (CQUniversity)', country_text: 'Australia', provider_id: null, provider_name: null, state_code: null, rank_display: '801-850', overall_score: null, evidence_artifact_id: null },
] }
export const rankingLinkCandidates = { can_link: true, items: [{ provider_id: 'p-cqu', provider_name: 'Central Queensland University', state: 'AU-QLD', confidence: 0.5 }] }
export const providerRankingHistory = { items: [{ system_code: 'qs_wur', ranking_name: 'QS World University Rankings', edition_year: 2027, rank_display: '13', overall_score: 90.8, publisher_name: 'The University of Melbourne' }] }

// Decision 214: Live activity
export const liveActivity = {
  now: '2026-10-01T21:40:00Z', in_flight: 2,
  needs_person: { fee_schedules: 12, scholarships_ready: 344, scholarships_domestic: 236, layer4_reviews: 3097, flagged_values: 456, ranking_links: 27 },
  jobs: [
    { job: 'scholarship-discover', area: 'Scholarships', label: 'Discover scholarships', description: 'Finds scholarship pages on provider websites.', schedule: '*/10 * * * *', active: true, running: false, runs_24h: 144, failed_24h: 0,
      last: { start: '2026-10-01T21:30:00Z', status: 'succeeded' }, queue: { unit: 'providers', left: 94, done_24h: 6 },
      worker: { mode: 'scholarship_discover', at: '2026-10-01T21:33:16Z', result: { ok: true, mode: 'scholarship_discover', ms: 65297, candidates: { items: 21, tally: { 'read:rejected': 18 } } } } },
    { job: 'scholarship-read', area: 'Scholarships', label: 'Read scholarship pages', description: 'Reads each page.', schedule: '*/5 * * * *', active: true, running: false, runs_24h: 288, failed_24h: 0,
      last: { start: '2026-10-01T21:35:00Z', status: 'succeeded' }, queue: { unit: 'pages', left: 0, done_24h: 0 }, worker: null },
    { job: 'coverage-read', area: 'Course pages', label: 'Read course pages', description: 'Fetches matched course pages.', schedule: '30 seconds', active: true, running: true, runs_24h: 2879, failed_24h: 0,
      last: { start: '2026-10-01T21:39:50Z', status: 'running' }, queue: { unit: 'course pages', left: 120, done_24h: 11857 }, worker: null },
    { job: 'coverage-find-site', area: 'Course pages', label: 'Find provider websites', description: 'Finds missing websites.', schedule: '*/15 * * * *', active: false, running: false, runs_24h: 0, failed_24h: 0, last: {}, queue: null, worker: null },
    { job: 'evidence-link-index', area: 'Reports', label: 'Index evidence links', description: 'Indexes links.', schedule: '*/10 * * * *', active: true, running: false, runs_24h: 140, failed_24h: 140,
      last: { start: '2026-10-01T21:39:00Z', status: 'failed', message: 'HTTP 401' }, queue: null, worker: null },
  ],
}
