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
// v2.15.171: the scholarship record drawer (admin_scholarship_record_read)
export const scholarshipRecord = { id: scholarshipRow.id, name: 'RMIT Irana Turynska Scholarship', provider: 'RMIT University', provider_id: 'p-rmit', can_edit: true, status: 'held', held_reasons: ['no linked course'], publication_status: 'unpublished', lifecycle_status: 'active', value_label: 'A$10,000 a year', page_words: 'AUD $10,000 annually', award_amount: 10000, award_percentage: null, award_value_type: 'fixed_amount', is_maximum: false, tiers: [], audience: 'international', audience_phrase: 'international students', nationalities: ['VN'], nationality_phrases: { VN: 'citizens of Vietnam' }, nationality_terms: [{ code: 'VN', name: 'Vietnam' }, { code: 'IN', name: 'India' }, { code: 'R-ASEAN', name: 'ASEAN region' }], duration_basis: 'annual_program_duration', application_required: true, application_open_date: null, application_close_date: '2027-03-08', page: 'https://www.rmit.edu.au/scholarships/coursework/irana-turynska', page_read_at: '2026-09-29T10:57:16+00:00', courses: 1, criteria: [{ id: 'c1', criterion_type: 'study_stage', value_text: 'commencing', status: 'active' }, { id: 'c2', criterion_type: 'academic_minimum', value_text: 'GPA', value_number: 5.5, value_json: { scale: 7 }, status: 'active' }], locks: { audience: 'value' }, history: [{ at: '2026-10-03T12:00:00+00:00', field: 'audience', action: 'set_audience', reason: 'Checked the page' }], course_levels: [{ level: 'Bachelor', courses: 1 }], course_list: [{ id: 'c-1', title: 'Bachelor of Business', level: 'Bachelor', code: '012345A' }] }
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
const layer3RecentBase = Array.from({ length: 30 }, (_, i) => ({ id: 'i' + i, created_at: new Date(Date.UTC(2026, 9, 1, 1, 0) - i * 600000).toISOString(), task_class: ['provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation'][i % 3], status: ['validated', 'no_candidate', 'escalated', 'rejected_validation'][i % 4], model_identifier: 'qwen/qwen3-30b-a3b-instruct-2507', estimated_cost_usd: 0.0002, review_state: i % 4 === 2 ? 'pending' : 'not_created', escalation_reason: i % 4 === 2 ? 'differs from value held' : null }))
// Decision 221: a cascade claim no step has answered yet (placeholder profile hidden), and an answer from step 2
export const layer3Recent = layer3RecentBase.map((r, i) => i === 0 ? { ...r, status: 'calling', model_identifier: null, profile_code: null, aggregator_response_model: null, model_pending: true, cascade_tier_no: null } : i === 1 ? { ...r, cascade_tier_no: 2 } : r)

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
    { id: 'fs1', provider_id: 'p-acu', country: 'AU', provider: 'Australian Catholic University', url: 'https://www.acu.edu.au/media/acu-2027-schedule-of-tuition-fees.pdf', fee_year: '2027', read_at: '2026-10-01T09:00:00Z', decision: null, decided_at: null, apply_summary: null, rows: 152, new: 131, same: 0, differs: 2, no_course: 19 },
    { id: 'fs2', provider_id: 'p-x', country: 'AU', provider: 'Example Institute', url: 'https://example.edu.au/fees.pdf', fee_year: '2027', read_at: '2026-10-01T08:00:00Z', decision: 'approved', decided_at: '2026-10-01T08:30:00Z', apply_summary: { written: 20, refused: 0 }, rows: 22, new: 0, same: 20, differs: 0, no_course: 2 },
  ],
}
// Decision 227: English policies and academic calendars
const pTotals = { documents_found: 413, documents_read: 116, providers_found: 150, no_values_by_style: { bands: 6, by_faculty: 9, course_specific: 12, none: 55 } }
export const englishPolicies = { can_decide: true, totals: pTotals, proposals: [
  { id: 'ep1', provider_id: 'p-fl', provider: 'Flinders University', country: 'AU', url: 'https://www.flinders.edu.au/international/apply/entry-requirements/english-language-requirements', style: 'level_default', status: 'proposed',
    caveats: [], conflicts: [], named_requirements: 2, named_courses: 4,
    defaults: { undergraduate: [{ test_code: 'IELTS', overall_score: 6, component_scores: { speaking: 6, writing: 6 } }], postgraduate: [{ test_code: 'IELTS', overall_score: 6.5, component_scores: { listening: 6, reading: 6, speaking: 6, writing: 6 } }] },
    plan: { write: 197, agrees: 57, differs: 12, held: 210 } },
  { id: 'ep2', provider_id: 'p-uts', provider: 'University of Technology Sydney', country: 'AU', url: 'https://www.uts.edu.au/english', style: 'level_default', status: 'proposed',
    caveats: ['level_not_stated'], conflicts: [], named_requirements: 0, named_courses: 0,
    defaults: { undergraduate: [{ test_code: 'IELTS', overall_score: 7, component_scores: { listening: 7, reading: 7, speaking: 7, writing: 7 } }] },
    plan: { write: 227, agrees: 2, differs: 204, held: 97 } },
  { id: 'ep3', provider_id: 'p-wa', provider: 'William Angliss Institute', country: 'AU', url: 'https://www.angliss.edu.au/entry', style: 'level_default', status: 'approved', decided_at: '2026-10-02T07:30:00Z',
    caveats: [], conflicts: [], named_requirements: 0, named_courses: 0, apply_summary: { written: 19 },
    defaults: { undergraduate: [{ test_code: 'IELTS', overall_score: 6, component_scores: { listening: 5.5, reading: 5.5, speaking: 5.5, writing: 5.5 } }] },
    plan: { write: 0, held: 18 } },
] }
export const calendarPolicies = { can_decide: true, totals: { ...pTotals, no_values_by_style: { none: 90 } }, proposals: [
  { id: 'cp1', provider_id: 'p-acu', provider: 'Australian Catholic University', country: 'AU', url: 'https://www.acu.edu.au/study-at-acu/important-dates', status: 'proposed',
    periods: [{ period: 'semester 1', months: [3], years: [2027] }, { period: 'semester 2', months: [8], years: [2027] }] },
] }
export const policyRows = { provider: 'Flinders University', rows: [
  { course_id: 'c1', title: 'Bachelor of Business', study_level: 'bachelor', plan: 'default', reason: null, outcome: 'write', existing: {}, ielts: 6 },
  { course_id: 'c2', title: 'Bachelor of Nursing', study_level: 'bachelor', plan: 'default', reason: null, outcome: 'differs', existing: { IELTS: 7 }, ielts: 6 },
  { course_id: 'c3', title: 'Doctor of Philosophy', study_level: 'doctorate', plan: 'held', reason: 'research degree', outcome: 'held', existing: {}, ielts: null },
] }
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
  worker_errors: [
    { function: 'evidence-link-index', job: 'Index evidence links', status: 401, timed_out: false, message: '{"error":"invalid_pilot_automation_key"}', count: 36, last: '2026-10-01T21:29:00Z' },
    { status: 500, timed_out: false, message: '{"success":false,"code":"UNKNOWN_ERROR","error":"An unexpected error occurred (firecrawl)"}', count: 1, last: '2026-10-01T18:00:34Z' },
  ],
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

// Decision 222: Fetch an area (course-page sweep) and Websites to find
export const fetchAreaOptions = { countries: [{ code: 'AU', name: 'Australia', providers: 1546, courses: 26103 }, { code: 'NZ', name: 'New Zealand', providers: 287, courses: 6475 }, { code: 'CA', name: 'Canada', providers: 34, courses: 2382 }] }
export const fetchAreaScope = { items: [{ value: 'prov-latrobe', label: 'La Trobe University', meta: '248 courses · site found, 239 pages read' }], total: 1, offset: 0, has_more: false }
export const fetchAreaPreview = { country: 'AU', scope_type: 'university', scope_id: 'prov-latrobe', providers: 1, courses: 248, sites: { known: 1, mapped: 1, not_found: 0, to_search: 0, failed: 0, not_queued: 0 }, pages: { found: 239, read: 239, to_read: 0, not_this_course: 9, no_page: 0 }, searches_waiting: 0, facts: { official_url: 239, english: 0, intakes: 23, provider_tuition: 0 }, facts_built_at: '2026-10-02T02:47:00Z', first_in_sweep: false }
export const fetchAreaStarted = { joined: 0, site_search_again: 0, site_map_retry: 0, page_searches_queued: 0, pages_to_read_now: 0 }
export const providerWebsites = { total: 2, can_edit: true, countries: { AU: 1, CA: 1 }, items: [
  { provider_id: 'prov-macewan', name: 'Grant MacEwan University', country: 'CA', courses: 44, cricos: null, dli: 'O19092022262', searched_at: '2026-10-02T02:16:41Z', query: 'Grant MacEwan University official website', note: null, tried: ['https://www.macewan.ca/', 'https://en.wikipedia.org/wiki/MacEwan_University'] },
  { provider_id: 'prov-small', name: 'Example Training College', country: 'AU', courses: 12, cricos: '01234A', dli: null, searched_at: '2026-10-01T02:16:41Z', query: 'Example Training College CRICOS 01234A', note: null, tried: [] }] }

// v2.15.173 (Decision 251): scholarships by layer (admin_scholarship_layer_read)
const slJobs = layer => ({ 1: [{ jobname: 'coursefinder-scholarship-etl-scheduler', label: 'Government feeds', what: 'Reads the qualified government feeds.', schedule: '43 * * * *', active: true, runs_7d: 168, failed_7d: 0, last_run: now }],
  2: [{ jobname: 'scholarship-discover', label: 'Find university scholarship pages', what: 'Maps universities.', schedule: '*/10 * * * *', active: true, runs_7d: 607, failed_7d: 0, last_run: now }],
  3: [{ jobname: 'coursefinder-scholarship-ai-change-scheduler', label: 'AI check on change', what: 'Sends changed pages to the AI check.', schedule: '17 */6 * * *', active: true, runs_7d: 28, failed_7d: 0, last_run: now }],
  4: [{ jobname: 'scholarship-publication-review', label: 'Daily publication review', what: 'Withdraws failing scholarships.', schedule: '17 20 * * *', active: true, runs_7d: 4, failed_7d: 0, last_run: now }] })[layer]
export const scholarshipLayer = layer => ({ layer, can_manage: true, jobs: slJobs(layer),
  settings: layer === 2 ? [{ key: 'discover_limit', label: 'Universities searched per run', help: 'How many universities each run maps.', value: 6, min: 1, max: 6, unit: 'universities', reason: 'Value in the job command until 4 Oct 2026', updated_at: now }] : [],
  ...(layer === 1 ? { countries: [{ code: 'AU', name: 'Australia', enabled: true, currency: 'AUD', providers: 1556, universities_queued: 967, scholarships: 1217, published: 391, detail_sources: 210 }, { code: 'NZ', name: 'New Zealand', enabled: true, currency: 'NZD', providers: 414, universities_queued: 8, scholarships: 7, published: 1, detail_sources: 0 }],
    sources: [{ id: 's-sa', country: 'AU', type: 'scholarship_catalogue', role: 'ingest', label: 'Study Australia Scholarship Search', url: 'https://search.studyaustralia.gov.au/scholarships', status: 'active', qualification: 'qualified', records: 204, feed: { feed: 'study_australia', enabled: true, cadence_hours: 168, last_dispatched_at: now, next_due_at: now, last_error: null } },
      { id: 's-iefa', country: 'ALL', type: 'scholarship_reference', role: 'validation', label: 'IEFA', url: 'https://www.iefa.org/', status: 'active', records: 0, reader: 'none', use: 'Comparison list only' }] } : {}),
  ...(layer === 2 ? { countries: [{ code: 'NZ', pages_found: 1829, discovery: { mapped: 8 }, page_reads: { read: 38, waiting: 1761 }, outcomes: { admitted: 7, rejected: 30 }, refusals: [{ reason: 'international_not_stated', pages: 20 }], rereads: { read: 7 } }], worker: [{ mode: 'scholarship_discover', sent: 37, answered: 36, ok: 36, failed: 0, last_failure: null }], firecrawl: { used: 2696, cap: 3000, reserve: 800, by_purpose: { sch_scrape: { all: 1781, last_7_days: 1781 } } } } : {}),
  ...(layer === 3 ? { ai: [{ country: 'AU', enabled: false, state: 'benchmark_required', profile: null, task: 'scholarship_page_classification', budget_usd: 1, max_records: 25, runs: 0 }], profiles: [{ code: 'openrouter-scholarship-gemini-flash-lite-v1', model: 'google/gemini-2.5-flash-lite', enabled: true, paused: true, benchmark_pass: false }] } : {}) })

// Decision 252 (v2.15.177, amended v2.15.178): toolsets and limits, notices per layer, keys with plan limits, sample runs
const notice = (o) => ({ count: 1, first_at: '2026-10-04T02:00:00Z', last_at: '2026-10-04T02:45:00Z', acknowledged: false, ...o })
export const platformNotices = layer => {
  const all = [
    notice({ key: 'openrouter:3:refused:key_limit', layer: 3, toolset: 'openrouter', kind: 'refused', severity: 'high', title: 'OpenRouter refused calls: the key\'s own spending limit was reached', detail: '92 work items in the last 24 hours were released and will be retried.', hint: 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in CourseFinder.' }),
    notice({ key: 'openrouter:3:low_balance', layer: 3, toolset: 'openrouter', kind: 'low_balance', severity: 'warning', title: 'OpenRouter balance is US$27.67', detail: 'Below the warning level of US$30.' }),
    notice({ key: 'scheduled_jobs:2:timeout:scholarship-nationality', layer: 2, toolset: 'scheduled_jobs', kind: 'timeout', severity: 'high', title: 'Job "scholarship-nationality" hit the database time limit 10 times', detail: 'In the last 24 hours (16 runs in all).', hint: 'Lower the job\'s batch size setting so each run finishes inside the limit.' }),
    notice({ key: 'scheduled_jobs:2:failed:coverage-bind', layer: 2, toolset: 'scheduled_jobs', kind: 'failed', severity: 'warning', title: 'Job "coverage-bind" failed 1 times', acknowledged: true, acknowledged_at: '2026-10-04T03:00:00Z' }),
  ]
  return { can_manage: true, notices: layer == null ? all : all.filter(n => n.layer === layer) }
}
export const toolsets = {
  can_manage: true,
  toolsets: [
    { key: 'firecrawl', label: 'Firecrawl (page reading and site maps)', kind: 'scrape', layers: [2], enforcement: null, help: 'Search, map, scrape and crawl.',
      settings: [
        { key: 'target_min_courses', label: 'Least active courses, by country', help: 'For example AU:100.', kind: 'list', value: ['AU:100', 'NZ:100', 'CA:30'], section: 'Target universities' },
        { key: 'target_only', label: 'Use Firecrawl only for target universities', help: '', kind: 'boolean', value: true, section: 'Target universities' },
        { key: 'read_proxy', label: 'Proxy', help: 'basic, auto, stealth or enhanced.', kind: 'text', value: 'auto', section: 'Read pages' },
        { key: 'find_query', label: 'Search wording', help: '', kind: 'text', value: '{course} site:{domain}', section: 'Find pages' },
        { key: 'run_concurrency', label: 'Calls at the same time', help: '', kind: 'number', value: 12, min: 1, max: 50, unit: 'calls', section: 'Runs' },
      ] },
    { key: 'openrouter', label: 'OpenRouter (AI models)', kind: 'ai', layers: [3], enforcement: 'observe', help: 'Observe only: the daily spend guards and the credit floor are shown and raise notices but do not stop Layer 3.', reason: 'Decision 252', updated_at: '2026-10-04T03:30:00Z',
      settings: [{ key: 'low_balance_warn_usd', label: 'Warn when the balance is below', help: 'A notice is raised on Layer 3.', kind: 'number', value: 10, min: 0, max: 1000, unit: 'US$' }] },
    { key: 'serper', label: 'Serper (web search)', kind: 'search', layers: [2], enforcement: null, help: 'Finds a course\'s official page, or a provider\'s website, where the site map has none.', key_saved: true, switched_on: false,
      plan: { name: 'Free plan', credits: 2500, used: 48, left: 2452, reserve: 100, counted_from: '2026-10-04', renews_monthly: false, max_concurrency: 5, at_reserve: false },
      settings: [
        { key: 'plan_name', label: 'Plan of the key in use', help: 'Change it when you replace the key.', kind: 'text', value: 'Free plan', section: 'Key and plan limits' },
        { key: 'plan_credits', label: 'Credits in the plan', help: 'Credits the key\'s plan gives.', kind: 'number', value: 2500, min: 0, max: 100000000, unit: 'credits', section: 'Key and plan limits' },
        { key: 'plan_counted_from', label: 'Count credits from', help: 'The date this key started (YYYY-MM-DD).', kind: 'text', value: '2026-10-04', section: 'Key and plan limits' },
        { key: 'plan_renews_monthly', label: 'Credits renew each month', help: '', kind: 'boolean', value: false, section: 'Key and plan limits' },
        { key: 'course_query', label: 'Search wording: course page', help: '', kind: 'text', value: '{course} {provider}', section: 'How the service is used' },
        { key: 'course_site_filter', label: 'Limit the course search to the provider\'s website', help: '', kind: 'boolean', value: true, section: 'How the service is used' },
        { key: 'sample_countries', label: 'Countries sampled', help: 'Country codes a sample run takes cases from.', kind: 'list', value: ['AU', 'NZ', 'CA'], section: 'Sample runs' },
        { key: 'sample_cases_per_country', label: 'Cases per country', help: '', kind: 'number', value: 20, min: 1, max: 500, unit: 'cases', section: 'Sample runs' }] },
    { key: 'scrapingbee', label: 'ScrapingBee (pages that need a browser)', kind: 'fetch', layers: [2], enforcement: null, help: 'Reads pages that need a browser to render.', key_saved: false, switched_on: false,
      plan: { name: 'Free plan', credits: 1000, used: 0, left: 1000, reserve: 50, counted_from: '2026-10-04', renews_monthly: false, max_concurrency: 5, at_reserve: false }, settings: [] },
  ],
  openrouter: { balance: { remaining_usd: 27.67, total_credits: 75, observed_at: '2026-10-04T02:45:00Z' }, guards: [{ task_class: 'provider_intake_validation', daily_usd_max: 20, credit_floor_usd: 5, spent_today: 0.42 }], spend_by_day: [{ day: '2026-10-03', usd: 1.2, calls: 340 }] },
  job_layers: {},
}
const RUN = '7d1e0000-0000-4000-8000-000000000001'
export const toolsetSamples = run => ({
  can_manage: true,
  runs: [{ id: RUN, toolset: 'serper', purpose: 'find_course_page', countries: ['AU', 'NZ', 'CA'], status: 'paused_time_limit', status_note: '12 cases left', credits_used: 48, cases: 60, done: 48, usd_per_1k_credits: 1, created_at: '2026-10-04T04:00:00Z' }],
  summary: [
    { toolset: 'serper', purpose: 'find_course_page', country: 'AU', outcome: 'found_on_provider_site', n: 14, credits: 14 },
    { toolset: 'serper', purpose: 'find_course_page', country: 'AU', outcome: 'other_sites_only', n: 6, credits: 6 },
    { toolset: 'serper', purpose: 'find_course_page', country: 'NZ', outcome: 'found_on_provider_site', n: 9, credits: 9 },
    { toolset: 'serper', purpose: 'find_course_page', country: 'NZ', outcome: 'no_results', n: 7, credits: 7 },
    { toolset: 'serper', purpose: 'find_course_page', country: 'CA', outcome: 'provider_site_no_title_match', n: 12, credits: 12 },
  ],
  backlog: [{ toolset: 'serper', purpose: 'find_course_page', country: 'AU', n: 7325 }, { toolset: 'serper', purpose: 'find_course_page', country: 'NZ', n: 3797 }, { toolset: 'serper', purpose: 'find_course_page', country: 'CA', n: 1227 },
    { toolset: 'scrapingbee', purpose: 'render_page', country: 'AU', n: 1187 }],
  items: run ? [{ country: 'AU', input: { course: 'Bachelor of Nursing', provider: 'Example University' }, outcome: 'found_on_provider_site', credits: 1, result: { found_url: 'https://example.edu.au/nursing', same_as_earlier_candidate: true } }] : [],
})

// Decision 252 step 1 (v2.15.179): search pass
export const searchPass = { can_manage: true,
  runs: [{ id: 'p0', status: 'running', credits_used: 640, created_at: '2026-10-04T05:10:00Z', courses: 2050, done: 640 }],
  links: [{ country: 'AU', refind: false, state: 'found', n: 210 }, { country: 'AU', refind: false, state: 'verified', n: 64 }, { country: 'NZ', refind: false, state: 'none', n: 12 }],
  reading: [{ read_status: 'waiting', n: 180 }],
  repairs: [{ reason: 'query string restored from the stored search results (Decision 252 step 2)', n: 392, last_at: '2026-10-04T05:00:00Z' }, { reason: 'search pass: page found', n: 274, last_at: '2026-10-04T05:12:00Z' }] }
// Decision 253 (v2.15.180): Firecrawl work — target universities, runs by use case, report for Firecrawl support
export const firecrawlWork = { can_manage: true,
  plan: { budget: { allowed: true, remaining_units: 490830, stop_at_remaining_units: 2000, limit_units: 500000 }, vendor: { plan_credits: 500000, remaining: 490846, period_start: '2026-10-02T15:57:21.000Z', period_end: '2026-11-02T15:57:21+00:00', observed_at: '2026-10-04T05:00:00Z' } },
  backlog: { read_page: 1102, find_page: 3975 },
  figures_at: '2026-10-04T08:20:00Z',
  runs: [
    { id: 'fc000000-0000-4000-8000-000000000002', use_case: 'find_page', status: 'running', reason: 'Decision 253', items: 3975, done: 420, credits_cap: 15000, credits_used: 840, outcomes: { found_on_provider_site: 260, provider_site_no_title_match: 120, no_results: 40 }, created_at: '2026-10-04T05:20:00Z', last_call_at: '2026-10-04T05:40:00Z' },
    { id: 'fc000000-0000-4000-8000-000000000001', use_case: 'read_page', status: 'stopped_credit_cap', reason: 'Decision 253 pilot', items: 1684, done: 39, credits_cap: 120, credits_used: 331, outcomes: { read_other_page: 39 }, created_at: '2026-10-04T05:12:00Z' },
  ],
  targets: [
    { provider_id: 'u9', country: 'AU', name: 'Flinders University', domain: 'flinders.edu.au', rule_match: true, included: true, adapter: 'admitting', adapter_confirmed: 20, waiting_read: 70, requests_open: 0, courses: 476, confirmed: 360, unreadable: 98, no_page: 18, intakes: 215, english: 305, web_fee: 0, any_fee: 476 },
    { provider_id: 'u1', country: 'AU', name: 'The University of Sydney', domain: 'sydney.edu.au', rule_match: true, included: true, adapter: 'testing', adapter_confirmed: 19, waiting_read: 68, requests_open: 1, courses: 655, confirmed: 346, unreadable: 65, no_page: 244, intakes: 15, english: 487, web_fee: 0, any_fee: 655 },
    { provider_id: 'u2', country: 'NZ', name: 'University of Auckland', domain: 'auckland.ac.nz', rule_match: true, included: true, courses: 458, confirmed: 216, unreadable: 40, no_page: 202, intakes: 120, english: 150, web_fee: 3, any_fee: 3 },
    { provider_id: 'u3', country: 'AU', name: 'Avondale University', domain: 'avondale.edu.au', rule_match: false, included: false, courses: 21, confirmed: 20, unreadable: 0, no_page: 1, intakes: 0, english: 5, web_fee: 0, any_fee: 21 },
  ],
  spend: [{ purpose: 'scrape', target: true, units: 5341 }, { purpose: 'scrape', target: false, units: 1751 }, { purpose: 'fc_read', target: true, units: 331 }],
}
export const firecrawlReport = { since: '2026-09-27T05:00:00Z', generated_at: '2026-10-04T05:45:00Z',
  account: { plan_credits: 500000, remaining: 490846, period_start: '2026-10-02T15:57:21.000Z', period_end: '2026-11-02T15:57:21+00:00', observed_at: '2026-10-04T05:00:00Z' },
  totals: { calls: 461, succeeded: 452, failed: 9, credits: 1171, api_errors: 4, timeouts: 3, rate_limited: 0, stealth_used: 12, median_ms: 6100 },
  by_endpoint: [{ endpoint: 'scrape', use_case: 'read_page', calls: 41, succeeded: 39, credits: 331 }, { endpoint: 'search', use_case: 'find_page', calls: 420, succeeded: 413, credits: 840 }],
  by_outcome: { read_other_page: 39, timeout: 2, found_on_provider_site: 260 },
  errors: [{ error: 'Request timed out', calls: 3, first_at: '2026-10-04T05:13:00Z', last_at: '2026-10-04T05:30:00Z', sample_scrape_id: '01a10555-0b96-720b-9ea2-dfe988faa072', sample_url: 'https://www.otago.ac.nz/study/qualification/bachelor-of-arts' }],
  by_site: [{ site: 'otago.ac.nz', calls: 12, failed: 3, page_statuses: { 403: 2, none: 1 }, errors: ['Request timed out'], proxies: ['stealth'], samples: [{ url: 'https://www.otago.ac.nz/study/qualification/bachelor-of-arts', scrape_id: '01a10555-0b96-720b-9ea2-dfe988faa072', http: 408, page_status: null, error: 'Request timed out', at: '2026-10-04T05:30:00Z' }] }],
}
export const uniAdapter = { can_manage: true, provider: { id: 'u1', name: 'The University of Sydney', website: 'https://sydney.edu.au' },
  adapter: { enabled: true, json_source: '__NEXT_DATA__', json_paths: { title: 'props.pageProps.pageContent.title', code: 'props.pageProps.pageContent.cricos_code' }, sections: {}, section_chars: 2000, title_strip: null, course_title_strip: null, notes: 'CourseLoop handbook' },
  pages: { read: 346, needs_render: 38, identity_mismatch: 12 },
  previews: [{ id: 'pv1', created_at: '2026-10-04T06:00:00Z', done_at: '2026-10-04T06:00:20Z', adapter: {}, result: { pages: [
    { course: 'Bachelor of Accounting and Finance', code: '065056B', url: 'https://handbook.example.edu.au/courses/2026/baf', was: 'identity_mismatch', identity: 'adapter_title', how: 'title in page data (props.pageProps.pageContent.title)', json_found: true, page: { title: 'BAF Bachelor of Accounting and Finance', h1: 'Handbook', text_chars: 2283, scripts: [{ id: '__NEXT_DATA__', chars: 103091 }] }, found: { intakes: ['February', 'July'], english: { ielts_overall: 6.5 }, fee: null } },
    { course: 'Bachelor of Psychology (Honours)', code: '021498F', url: 'https://handbook.example.edu.au/courses/2026/c9', was: 'identity_mismatch', identity: null, how: '', json_found: true, page: { title: 'Bachelor of Psychology', h1: 'Handbook', text_chars: 16295, scripts: [] }, found: null },
  ], json_shape: ['props.pageProps.pageContent.title: Bachelor of Accounting and Finance', 'props.pageProps.pageContent.cricos_code: null'] } }],
  applied: [{ identity: 'adapter_title', before: 'identity_mismatch', n: 41, last_at: '2026-10-04T06:05:00Z' }],
  allowed: [{ country: 'AU', identities: { english: ['cricos_code', 'exact_title'] } }] }
export const uniAdapterReview = { admit: { on: false, fields: ['english', 'fee', 'intakes'], reason: null, changed_at: null }, confirmed_total: 19,
  exclusions: [{ course_id: 'c9', course: 'Graduate Certificate of Arts', code: '116337M', field: 'fee', reason: 'course shorter than a year, page prints the course total', set_at: '2026-10-05T08:00:00Z' }],
  confirmed: [{ course: 'Master of Advanced Practice (Clinical)', code: '121373J', url: 'https://handbook.example.edu.au/courses/2027/MAPC', identity: 'adapter_code', intakes: ['February', 'July'], ielts: 7, english_context: 'page data: IELTS 7', link_admitted: false, english_admitted: false }],
  readings_total: 262, intakes_by_adapter: 240,
  readings: [{ course: 'Bachelor of Engineering (Electrical and Electronic) (Honours)', code: '111210M', url: 'https://www.example.edu.au/study/courses/bachelor-engineering', identity: 'cricos_code', intakes: ['March', 'July'], intakes_by: 'adapter', intake_context: 'adapter pattern: March July', fee: 47300, fee_by: 'adapter', ielts: 6, english_by: null, extra: { campus: 'In person: Tonsley', duration: '5 years full-time' }, intakes_now: null }],
  requests: [{ id: 1, request: 'Intakes are under Start dates', status: 'open', requested_at: '2026-10-04T06:30:00Z' }] }

export const adapterEvaluation = { settings: { no_page_share: 0.3, unreadable_share: 0.2, field_share: 0.5 }, figures_at: '2026-10-04T11:50:00Z', universities: [
  { provider_id: 'u2', name: 'Australian National University', country: 'AU', courses: 423, confirmed: 405, no_page: 18, unreadable: 0, intakes: 17, english: 0, adapter: 'none', gap: 829, next: 'adapter_intakes' },
  { provider_id: 'u3', name: 'Macquarie University', country: 'AU', courses: 461, confirmed: 270, no_page: 25, unreadable: 166, intakes: 82, english: 111, adapter: 'testing', gap: 729, next: 'adapter_page_data' },
  { provider_id: 'u9', name: 'Flinders University', country: 'AU', courses: 476, confirmed: 360, no_page: 18, unreadable: 98, intakes: 215, english: 305, adapter: 'admitting', gap: 432, next: 'admitting' }] }

export const adapterBuilder = { can_manage: true, budget: { used_usd: 0.0021, proposals: 1, limit_usd: 0.5, limit_proposals: 30, model: 'qwen/qwen3-30b-a3b-instruct-2507' },
  drafts: [{ id: 'dr1', provider_id: 'u1', status: 'proposed', samples: [], marks: [{ sample: 0, kind: 'block', ref: '3', field: 'intakes', value: 'March July' }], comments: 'Start dates in the international view',
    captures: [{ course: 'Bachelor of Engineering', code: '111210M', kind: 'undergraduate', url: 'https://www.example.edu.au/study/courses/be', credits: 1, screenshot_url: null, json_source: '__NEXT_DATA__',
      blocks: [{ id: 3, heading: 'Key information', text: 'CRICOS code 111210M Start dates March July Annual fee 2026: $47,300' }], leaves: [{ path: 'props.pageProps.pageContent.duration_ft_std', value: '4' }] }],
    proposals: [{ at: '2026-10-04T13:00:00Z', kind: 'proposal', model: 'qwen/qwen3-30b-a3b-instruct-2507', cost: 0.0021, reason: 'Start dates follow the CRICOS code.', dropped: [],
      adapter: { json_source: '__NEXT_DATA__', json_paths: { duration: 'props.pageProps.pageContent.duration_ft_std' }, patterns: { intakes: 'CRICOS(?:.|\\n){0,200}?Start dates((?:.|\\n){0,60})' }, pick: { intakes: 'first' } },
      output: [{ course: 'Bachelor of Engineering', code: '111210M', identity: 'cricos_code', intakes: ['March', 'July'], fee: 47300, fee_year: 2026, ielts: 6, extra: { duration: '4' } }] }] }] }

// Coverage › Universities (Decision 254, 5 Oct)
export const universities = { as_at: '2026-10-05T09:00:00Z', universities: [
  { provider_id: 'u1', name: 'Example University', country: 'AU', domain: 'example.edu.au', courses: 200, pages_read: 180,
    adapter: { state: 'admitting', fields: ['english', 'fee', 'intakes'], exclusions: 3, admit_changed_at: '2026-10-05T07:00:00Z' },
    english_policy: { status: 'approved', style: 'level_default', url: 'https://www.example.edu.au/english' }, calendar: { status: 'proposed', url: 'https://www.example.edu.au/key-dates' },
    central_pages: [{ kind: 'english_policy', url: 'https://www.example.edu.au/english', status: 'parsed', read_at: '2026-10-05T08:00:00Z', evidence_id: 'ev-1' }],
    intakes: { held: 150, adapter: 120, central: 0, reader: 30, excluded: 2 }, english: { held: 190, adapter: 40, central: 150, reader: 0, excluded: 0 }, fee: { held: 100, adapter: 100, reader: 0, excluded: 1 } },
  { provider_id: 'u2', name: 'Northern College', country: 'NZ', domain: 'northern.ac.nz', courses: 50, pages_read: 10, adapter: null, english_policy: null, calendar: null, central_pages: [],
    intakes: { held: 0, adapter: 0, central: 0, reader: 0, excluded: 0 }, english: { held: 5, adapter: 0, central: 0, reader: 5, excluded: 0 }, fee: { held: 0, adapter: 0, reader: 0, excluded: 0 } }] }
export const universityCourses = { total: 2, offset: 0, limit: 100, courses: [
  { course_id: 'c1', course: 'Bachelor of Nursing', code: '012345A', level: 'bachelor', url: 'https://www.example.edu.au/nursing', read_status: 'read', evidence_id: 'ev-2',
    intakes: { value: ['February', 'July'], source: 'adapter', excluded: false }, english: { value: 7, source: 'central', excluded: false }, fee: { value: 41000, year: 2026, currency: 'AUD', source: 'adapter', excluded: false },
    delivery: { value: 'on_campus_and_online', read: 'On campus, Online', source: 'adapter', excluded: false }, location: { value: 'Bundoora Campus', read: null, source: 'catalogue' }, requirement: { read: 'Prerequisite: Year 12 Chemistry', other: 'Uniform and clinical placement kit', source: 'adapter' }, host: { kind: 'exit_award', host: 'Bachelor of Nursing', years: 1, register_check: 'pass', active: true, applied: true } },
  { course_id: 'c2', course: 'Graduate Certificate of Arts', code: '116337M', level: 'graduate_certificate', url: null, read_status: null, evidence_id: null,
    intakes: { value: null, source: 'missing', excluded: false }, english: { value: null, source: 'missing', excluded: false }, fee: { value: 18836, year: 2026, currency: 'AUD', source: 'reader', excluded: true } }] }

// 5 Oct 17:04/18:04: indicative whole-course fees per university (current first, CRICOS fallback, award courses only)
const frU1 = { provider_id: 'u1', name: 'Example University', country: 'AU', currency: 'AUD', low: 13500, high: 290400, by_hand: false,
  computed: { low: 13500, high: 290400, low_course_id: 'c9', high_course_id: 'c8', low_course: 'Diploma of Accounting', high_course: 'Bachelor of Engineering (Honours)', low_source: 'register_total', high_source: 'current_annual_x_years',
    courses: 499, sources: { current_total: 24, current_annual_x_years: 329, register_total: 146 }, skipped: { below_floor: 2 }, fee_year_from: 2027, fee_year_to: 2027, register_as_of: '2026-09-30', meets_minimum: true, computed_at: '2026-10-05T07:10:00Z' },
  manual: { low: null, high: null, note: null, at: null }, published: false, published_at: null, publish_reason: null }
export const feeRanges = { settings: { include_under_one_year: true, min_courses: 5, min_fee_year: 2026, min_whole_fee: 1000, excluded_level_codes: ['non_aqf_award', 'vocational_short_course'], updated_at: '2026-10-05T07:00:00Z', reason: 'Decision 254 defaults' },
  levels: [{ code: 'bachelor', name: 'Bachelor' }, { code: 'non_aqf_award', name: 'Non AQF Award' }, { code: 'vocational_short_course', name: 'Vocational Short Course' }, { code: 'graduate_certificate', name: 'Graduate Certificate' }],
  ranges: [frU1, { ...frU1, provider_id: 'u2', name: 'Northern College', country: 'NZ', currency: 'NZD', low: 24561, high: 203048, published: true, computed: { ...frU1.computed, courses: 3, meets_minimum: false } }] }
export const feeRangeOne = { range: frU1, courses: [
  { provider_id: 'u1', course_id: 'c8', title: 'Bachelor of Engineering (Honours)', level_code: 'bachelor', country_currency: 'AUD', currency_code: 'AUD', whole_fee: 290400, source: 'current_annual_x_years', fee_amount: 48400, fee_basis: 'annual', fee_year: 2027, years: 6, years_from: 'catalogue', register_as_of: null, skip: null },
  { provider_id: 'u1', course_id: 'c7', title: 'Doctor of Philosophy', level_code: 'doctorate', country_currency: 'AUD', currency_code: 'AUD', whole_fee: 1, source: 'register_total', fee_amount: 1, fee_basis: 'registered_total_course', fee_year: null, years: 4, years_from: 'catalogue', register_as_of: '2026-09-30', skip: 'below_floor' }] }

// 5 Oct 19:18: hosted courses (award links and host pages)
export const exitAwards = [
  { child_course_id: 'c2', child: 'Diploma of Nursing Studies', child_code: '0100xx', parent_course_id: 'c1', parent: 'Bachelor of Nursing', years: 1, page_url: 'https://www.example.edu.au/courses/bachelor-of-nursing', printed: '1 years: Diploma of Nursing Studies', active: true, set_by: 'adapter', link_type: 'exit_award', register_check: 'pass', check_detail: 'register 41000 over 52.00 weeks = 41000 a year against the parent fee 41000 (2026)', annual_fee: 41000, fee_year: 2026, total_fee: 41000, applied_at: '2026-10-05T08:37:00Z' },
  { child_course_id: 'c3', child: 'Graduate Diploma in Nursing', child_code: '0101xx', parent_course_id: 'c4', parent: 'Master of Nursing', years: 1, page_url: 'https://www.example.edu.au/courses/master-of-nursing', printed: 'Graduate Diploma in Nursing within Master of Nursing (title match)', active: true, set_by: 'adapter', link_type: 'nested_award', register_check: 'fail', check_detail: 'register 30000 over 52.00 weeks = 30000 a year is -25.0% off the parent fee 40000 (2026)', annual_fee: null, fee_year: null, total_fee: null, applied_at: null }]
export const hostPages = [
  { course_id: 'c5', course: 'Doctor of Philosophy (Nursing)', code: '0102xx', link_type: 'shared_page', host_course_id: 'c6', host: 'Doctor of Philosophy', host_url: 'https://www.example.edu.au/courses/phd', basis: 'title', printed: 'Doctor of Philosophy (Nursing) on the page of Doctor of Philosophy', register_check: 'pass', check_detail: 'register 38000 over 156.00 weeks = 12667 a year against the parent fee 12667 (2026)', active: true, set_by: 'detector', applied_at: null, set_at: '2026-10-05T09:00:00Z' },
  { course_id: 'c7', course: 'Bachelor of Nursing/Bachelor of Midwifery', code: '0103xx', link_type: 'double_degree', host_course_id: null, host: null, host_url: 'https://www.example.edu.au/courses/nursing-midwifery', basis: 'bound page', printed: 'bound to the page', register_check: null, check_detail: null, active: true, set_by: 'detector', applied_at: null, set_at: '2026-10-05T09:00:00Z' },
  { course_id: 'c8', course: 'Bachelor of Old Things', code: '0104xx', link_type: 'no_public_page', host_course_id: null, host: null, host_url: 'https://www.example.edu.au/courses/old-things', basis: '404', printed: 'is gone', register_check: null, check_detail: null, active: true, set_by: 'detector', applied_at: null, set_at: '2026-10-05T09:00:00Z' }]


// Decision 254, job system Phase A: the Task manager (Scheduled jobs › Task manager)
const adminJobRows = [
  { id: 'job-fc', kind: 'firecrawl_run', lane: 'firecrawl', state: 'running', scope: 'find_page', title: 'Firecrawl run: find page (120 pages, cap 600 credits)', args: { run_id: 'fc000000-0000-4000-8000-000000000009', use_case: 'find_page' }, providers: 0, cursor: {}, progress: { done: 40, total: 120 }, result: { done: 40, total: 120, errors: 0 }, error: null, cancel_requested: false, pause_requested: false, requested_by: 'user-admin', requested_by_name: 'admin@example.test', reason: 'Decision 253 run', created_at: '2026-10-06T00:50:00Z', started_at: '2026-10-06T00:51:00Z', updated_at: '2026-10-06T00:52:00Z', finished_at: null },
  { id: 'job-run', kind: 'qualify_adapters', lane: 'adapters', state: 'running', scope: 'AU-VIC', title: 'Qualify 11 adapter(s) in AU-VIC', args: { country: 'AU', state: 'AU-VIC', provider_kind: 'university', adapter_state: 'enabled' }, providers: 11, cursor: { next: 5 }, progress: { done: 4, total: 11 }, result: { passing: 4, errors: 0 }, error: null, cancel_requested: false, pause_requested: false, requested_by: 'user-admin', requested_by_name: 'admin@example.test', reason: 'First Qualify run', created_at: '2026-10-06T00:40:00Z', started_at: '2026-10-06T00:41:00Z', updated_at: '2026-10-06T00:42:00Z', finished_at: null },
  { id: 'job-done', kind: 'qualify_adapters', lane: 'adapters', state: 'done', scope: 'AU-NSW', title: 'Qualify 2 adapter(s) in AU-NSW', args: { country: 'AU', state: 'AU-NSW', provider_kind: 'university', adapter_state: 'enabled' }, providers: 2, cursor: { next: 3 }, progress: { done: 2, total: 2 }, result: { passing: 1, errors: 0 }, error: null, cancel_requested: false, pause_requested: false, requested_by: 'user-admin', requested_by_name: 'admin@example.test', reason: 'NSW check', created_at: '2026-10-06T00:10:00Z', started_at: '2026-10-06T00:11:00Z', updated_at: '2026-10-06T00:12:00Z', finished_at: '2026-10-06T00:12:00Z' },
]
// read: live tasks only (A2); match: the live task of a kind and scope (B, JobButton)
export const adminJobs = (id, args = {}) => ({
  jobs: adminJobRows.filter(j => ['queued', 'running', 'paused'].includes(j.state) || args.all),
  match: args.kind ? (adminJobRows.find(j => j.kind === args.kind && ['queued', 'running', 'paused'].includes(j.state) && (j.scope || null) === (args.scope || null)) || null) : undefined,
  job: id === 'job-done' ? { ...adminJobRows.find(j => j.id === 'job-done'), events: [{ at: '2026-10-06T00:12:00Z', note: 'finished', detail: { passing: 1, errors: 0 } }, { at: '2026-10-06T00:11:00Z', note: 'started' }, { at: '2026-10-06T00:10:00Z', note: 'queued by admin@example.test', detail: { reason: 'NSW check' } }],
    qualifications: [
      { provider_id: 'prov-uts', name: 'University of Technology Sydney', country: 'AU', pages_read: 360, adapter: 'admitting', admitted: ['delivery', 'english', 'fee', 'intakes'], passing: ['intakes', 'english', 'delivery'],
        fields: { intakes: { read: 249, agree: 249, differ: 0, new: 0, excluded: 0, unclear: 0, read_share: 0.692, agree_share: 1, pass: true, why: 'passes' }, fee: { read: 83, agree: 83, differ: 0, new: 0, excluded: 2, unclear: 0, read_share: 0.232, agree_share: 1, pass: false, why: 'read on 83 of 358 pages, under the share needed' }, english: { read: 307, agree: 307, differ: 0, new: 0, excluded: 0, unclear: 0, read_share: 0.853, agree_share: 1, pass: true, why: 'passes' }, delivery: { read: 343, agree: 343, differ: 0, new: 0, excluded: 0, unclear: 0, read_share: 0.953, agree_share: 1, pass: true, why: 'passes' } } },
      { provider_id: 'prov-une', name: 'University of New England', country: 'AU', pages_read: 40, adapter: 'testing', admitted: null, passing: [],
        fields: { intakes: { read: 0, agree: 0, differ: 0, new: 0, excluded: 0, unclear: 0, read_share: 0, agree_share: null, pass: false, why: 'not read by the adapter' }, fee: { read: 0, agree: 0, differ: 0, new: 0, excluded: 0, unclear: 0, read_share: 0, agree_share: null, pass: false, why: 'not read by the adapter' }, english: { read: 12, agree: 10, differ: 2, new: 0, excluded: 0, unclear: 0, read_share: 0.3, agree_share: 0.833, pass: false, why: 'read on 12 of 40 pages, under the share needed' }, delivery: { read: 0, agree: 0, differ: 0, new: 0, excluded: 0, unclear: 0, read_share: 0, agree_share: null, pass: false, why: 'not read by the adapter' } } },
    ] } : null,
  settings: { min_read_share: 0.5, min_agree_share: 0.9 },
  countries: [{ code: 'AU', name: 'Australia', adapters: 700 }, { code: 'CA', name: 'Canada', adapters: 27 }, { code: 'NZ', name: 'New Zealand', adapters: 60 }],
  states: [{ code: 'AU-NSW', name: 'New South Wales', country: 'AU', adapters: 200 }, { code: 'AU-VIC', name: 'Victoria', country: 'AU', adapters: 180 }, { code: 'CA-BC', name: 'British Columbia', country: 'CA', adapters: 10 }],
  can_admit: true,
})
