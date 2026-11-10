// Mocked answer for public.admin_layer23('data_delivery') (F-OPS.03A). The shape follows security.data_delivery_v1 in
// supabase/migrations/20261110000100_cf247_fops03a_data_delivery.sql. Nothing reaches a real backend.
const ago = (m) => new Date(Date.now() - m * 60000).toISOString()
const soon = (m) => new Date(Date.now() + m * 60000).toISOString()
const meta = (m = 3) => ({ measured_at: ago(m), age_minutes: m, stale: false, took_ms: 400 })
const unknown = (reason) => ({ known: false, reason })
const job = (name, over = {}) => ({ job: name, scheduled: true, active: true, schedule: '26 * * * *', next_run: soon(14), last_start: ago(46), last_end: ago(45), last_status: 'succeeded', last_message: 'done', runs: 1, succeeded: 1, failed: 0, ...over })
const jobs = (list, over = {}) => ({ last_run_at: ago(46), next_run_at: soon(14), runs: 1, succeeded: 1, failed: 0, last_status: 'succeeded', last_message: 'done', active: list.length, total: list.length, history_hours: 48, known: true, reason: null, list, ...over })

export const STREAMS = [
  { stream: 'pdesc', title: 'Provider descriptions', unit: 'providers', net_unit: 'providers', consumer_unit: 'providers', what: 'Official About pages to provider descriptions.', lane: 'pdesc', net_basis: 'Machine admissions and Layer 4 approvals, by timestamp', stale: false,
    drill: { screen: 'providers', filled: { description: 'filled' }, missing: { description: 'missing' }, website: { key: 'website' }, zoho: { key: 'zoho' }, needs_provider_filters: true, note: null },
    coverage: { known: true, n: 800, total: 3087, pct: 25.9, by_country: [{ cc: 'AU', n: 700, total: 2500 }, { cc: 'NZ', n: 100, total: 587 }], ...meta() },
    net_short: { known: true, window_hours: 24, added: 12, removed: 2, removed_known: true, net: 10, processed: 120, last_added_at: ago(30), since: ago(60 * 24 * 10), partial: false, ...meta() },
    net_long: { known: true, window_hours: 168, added: 800, removed: 5, removed_known: true, net: 795, processed: 900, last_added_at: ago(30), since: ago(60 * 24 * 10), partial: false, ...meta() },
    website: { known: true, expected: 800, matched: 790, pending: 6, missing: 4, not_applicable: 0, ...meta() },
    zoho: { known: true, expected: 800, matched: 700, pending: 0, missing: 100, not_applicable: 0, ...meta() },
    queue: { known: true, n: 435, partial: false, parts: [{ stage: 'queued', title: 'Waiting for the reader', kind: 'queued', n: 435 }], reasons: [] },
    holds: { known: true, n: 760, partial: false, parts: [{ stage: 'held', title: 'Held, by cause', kind: 'held', n: 750 }, { stage: 'human', title: 'Waiting for a person', kind: 'human_review', n: 10 }],
      reasons: [{ reason: 'N verified fact(s) held (register, location)', n: 472, stage: 'Held, by cause' }, { reason: 'The page does not prove the institution', n: 152, stage: 'Held, by cause' }, { reason: 'no About or Overview link on the home page', n: 56, stage: 'Held, by cause' }] },
    speed: { known: true, processed: 120, window_hours: 24, per_hour: 5, basis: 'reads that reached a verdict' },
    jobs: jobs([job('provider-description-read', { schedule: '6,16,26,56 * * * *' })]), recovery: { state: 'healthy', text: 'No open issues; the scheduled job retries on its next run', open_issues: 0, issue_refs: [], remedy_acted: 0, remedy_refused: 0 }, flags: [] },
  { stream: 'int', title: 'Intake dates and deadlines', unit: 'intake rows', net_unit: 'intake events', consumer_unit: 'courses', what: 'Course page and calendar evidence to exact start dates.', lane: 'int', net_basis: 'Intake date events by run time', stale: false,
    drill: { screen: 'courses', filled: { hasIntake: 'true' }, missing: { hasIntake: 'false' }, filled_label: 'Courses with an intake', missing_label: 'Courses with no intake', coverage_note: 'Counts intake rows. The Course Catalogue has no dated-intake filter.', website: null, zoho: null, needs_provider_filters: false, note: 'The Course Catalogue has no dated-intake filter. These links list courses that have any intake (or none), which is a count of courses and not the dated intake rows shown under Coverage.' },
    coverage: { known: true, n: 1563, total: 20000, pct: 7.8, by_country: [{ cc: 'AU', n: 1500, total: 18000 }], ...meta() },
    net_short: { known: true, window_hours: 24, admitted_known: true, added: 0, removed: 0, removed_known: true, net: 0, processed: 589, last_added_at: ago(60 * 30), since: ago(60 * 24 * 4.4), partial: true, ...meta() },
    net_long: { known: true, window_hours: 168, added: 120, removed: 3, removed_known: true, net: 117, processed: 2000, last_added_at: ago(60 * 30), since: ago(60 * 24 * 4.4), partial: true, ...meta() },
    website: { known: true, expected: 958, matched: 958, pending: 0, missing: 0, not_applicable: 0, ...meta() }, zoho: { known: true, expected: 958, matched: 958, pending: 0, missing: 0, not_applicable: 0, ...meta() },
    queue: { known: true, n: 16174, partial: false, parts: [{ stage: 'selected', title: 'Selected and evaluated', kind: 'eligible', n: 16174 }], reasons: [] },
    holds: { known: true, n: 575, partial: false, parts: [{ stage: 'held', title: 'Held, by cause', kind: 'held', n: 575 }], reasons: [{ reason: 'missing_application_deadline', n: 400, stage: 'Held, by cause' }] },
    speed: { known: true, processed: 589, window_hours: 24, per_hour: 24.5, basis: 'intake date events of every outcome, including skipped and nothing new' },
    jobs: jobs([job('intake-dates-apply', { runs: 24, succeeded: 24 })], { runs: 24, succeeded: 24 }), recovery: { state: 'stalled', text: 'Stalled: the job ran OK 24 time(s) in 24 h but admitted nothing (16174 waiting); it retries on schedule, and nothing is changing', open_issues: 0, issue_refs: [], remedy_acted: 0, remedy_refused: 0 },
    flags: [{ code: 'green_no_admission', severity: 'warn', text: 'Ran OK 24 time(s) in 24 h, admitted nothing; 16174 waiting; top hold: missing_application_deadline' }] },
  { stream: 'eng', title: 'English entry requirements', unit: 'courses', net_unit: 'courses', consumer_unit: 'courses', what: 'University English policies to course English rows.', lane: 'eng', net_basis: 'Layer 4 approvals of course English', stale: false,
    drill: { screen: 'courses', filled: { hasEnglish: 'true' }, missing: { hasEnglish: 'false' }, website: null, zoho: null, needs_provider_filters: false, note: null },
    coverage: { known: true, n: 16350, total: 36000, pct: 45.4, by_country: [], ...meta() },
    net_short: { known: false, window_hours: 24, reason: 'English admissions are not counted. The only dated record is 14 Layer 4 approvals (October), and catalogue.course_english_requirements has no created_at, so a count of 0 for the last day or week would not be true.' },
    net_long: { known: false, window_hours: 168, reason: 'English admissions are not counted. The only dated record is 14 Layer 4 approvals (October), and catalogue.course_english_requirements has no created_at, so a count of 0 for the last day or week would not be true.' },
    website: { known: true, expected: 100, matched: 99, pending: 1, missing: 0, not_applicable: 0, ...meta() }, zoho: unknown('The Zoho comparison for English is not built yet. Follow-up gap.'),
    queue: unknown('There is no English reader queue stage, so the queue is not counted.'),
    holds: { known: true, n: 1, partial: false, parts: [{ stage: 'human', title: 'Waiting for a person (course English)', kind: 'human_review', n: 1 }], reasons: [{ reason: 'Waiting for a person (course English)', n: 1, stage: 'x' }], causes_reason: 'English holds are not recorded by cause; only items waiting for a person are counted.' },
    speed: unknown('English reads have no timestamped ledger, so items per hour cannot be counted.'),
    jobs: jobs([job('central-attach')], { known: false, last_run_at: null, next_run_at: soon(20), reason: 'No run of central-attach in the last 48 hours of scheduler history' }),
    recovery: { state: 'failing', text: 'The last run failed; the job retries at its next scheduled run (9 Nov 22:48 Melbourne)', open_issues: 1, issue_refs: ['IQ-00111'], remedy_acted: 0, remedy_refused: 0 },
    flags: [{ code: 'job_failing', severity: 'bad', text: '2 failed run(s) in 24 h' }] },
  { stream: 'cdesc', title: 'Course descriptions', unit: 'courses', net_unit: 'courses', consumer_unit: 'courses', what: 'Source-backed course description proposals.', lane: 'cdesc', net_basis: 'Layer 4 approvals of the first reading', stale: true,
    drill: { screen: 'courses', filled: null, missing: null, website: null, zoho: null, needs_provider_filters: false, note: 'The Course Catalogue has no description filter yet, so the filled and missing courses cannot be listed (follow-up gap).' },
    coverage: { known: false, reason: 'Could not be counted: canceling statement due to statement timeout', ...meta(95), stale: true },
    net_short: { known: true, window_hours: 24, admitted_known: false, admitted_reason: 'No course description admission is recorded with a date, so a count of 0 would not be true.', added: null, removed: null, removed_known: false, net: null, processed: 416, last_added_at: null, since: null, partial: true, ...meta() },
    net_long: { known: true, window_hours: 168, admitted_known: false, admitted_reason: 'No course description admission is recorded with a date, so a count of 0 would not be true.', added: null, removed: null, removed_known: false, net: null, processed: 3000, last_added_at: null, since: null, partial: true, ...meta() },
    website: unknown('Whether the course description reaches the Website and Zoho course feed items is not compared yet (no feed field check is built for it). Follow-up gap.'), zoho: unknown('Whether the course description reaches the Website and Zoho course feed items is not compared yet (no feed field check is built for it). Follow-up gap.'),
    queue: unknown('The description reader keeps no waiting state, so its queue is not counted.'), holds: { known: true, n: 4803, partial: true, parts: [], reasons: [{ reason: 'duplicate_of_another_course', n: 23, stage: 'Held by a check' }] },
    speed: { known: true, processed: 416, window_hours: 24, per_hour: 17.3, basis: 'description reader items updated in the window' },
    jobs: jobs([job('enrich-plan-run', { schedule: '*/5 * * * *' })]), recovery: { state: 'needs_attention', text: '1 open issue(s) and no automatic remedy has acted in the window', open_issues: 1, issue_refs: ['IQ-00200'], remedy_acted: 0, remedy_refused: 1 }, flags: [{ code: 'measure_unknown', severity: 'info', text: 'A headline measure could not be counted; see the reason in the cell' }] },
  { stream: 'fee', title: 'Tuition and other fees', unit: 'courses', net_unit: 'fee rows', consumer_unit: 'courses', what: 'Fee rows read, checked and admitted.', lane: 'fee', net_basis: 'Fee rows created in the window. A row that replaces an earlier fee row is counted as created too, so removals are not separated and no net is shown', stale: false,
    drill: { screen: 'courses', filled: { hasFee: 'true' }, missing: { hasFee: 'false' }, filled_label: 'Courses with a fee', missing_label: 'Courses with no fee', website: null, zoho: null, needs_provider_filters: false, note: null },
    coverage: { known: true, n: 27600, total: 35689, pct: 77.3, by_country: [], ...meta() },
    net_short: { known: true, window_hours: 24, admitted_known: true, added: 40, removed: null, removed_known: false, removed_reason: 'Removals are not separable: a fee row that is no longer active is usually one replaced by a newer row, and no withdrawal time is recorded.', net: null, processed: 300, last_added_at: ago(20), since: ago(60 * 24 * 30), partial: false, ...meta() },
    net_long: { known: true, window_hours: 168, admitted_known: true, added: 3095, removed: null, removed_known: false, removed_reason: 'Removals are not separable: a fee row that is no longer active is usually one replaced by a newer row, and no withdrawal time is recorded.', net: null, processed: 2100, last_added_at: ago(20), since: ago(60 * 24 * 30), partial: false, ...meta() },
    website: { known: true, expected: 27600, matched: 27000, pending: 500, missing: 100, not_applicable: 0, ...meta() }, zoho: { known: true, expected: 27600, matched: 27000, pending: 500, missing: 100, not_applicable: 0, ...meta() },
    queue: { known: true, n: 0, partial: false, parts: [{ stage: 'queued', title: 'Waiting for the reader', kind: 'queued', n: 0 }], reasons: [] }, holds: { known: true, n: 12, partial: false, parts: [], reasons: [{ reason: 'fee not on the page', n: 12, stage: 'Held' }] },
    speed: { known: true, processed: 300, window_hours: 24, per_hour: 12.5, basis: 'fee rows the reader read in the window' },
    jobs: jobs([job('fee-reader', { schedule: '* * * * *' })]), recovery: { state: 'healthy', text: 'No open issues; the scheduled job retries on its next run', open_issues: 0, issue_refs: [], remedy_acted: 0, remedy_refused: 0 }, flags: [] },
  { stream: 'sch', title: 'Scholarships', unit: 'scholarships', net_unit: 'scholarships', consumer_unit: 'scholarships', what: 'Scholarships read, reviewed and published.', lane: 'sch', net_basis: 'Scholarship admission log', stale: false,
    drill: { screen: 'scholarships', filled: {}, missing: null, website: null, zoho: null, needs_provider_filters: false, note: null },
    coverage: { known: true, n: 1150, total: null, total_reason: 'The number of scholarships that should be published is not defined, so there is no total or percentage.', pct: null, by_country: [], ...meta() },
    net_short: { known: true, window_hours: 24, admitted_known: true, added: 8, removed: 0, removed_known: true, net: 8, processed: 8, last_added_at: ago(40), since: ago(60 * 24 * 20), partial: false, ...meta() },
    net_long: { known: true, window_hours: 168, admitted_known: true, added: 59, removed: 0, removed_known: true, net: 59, processed: 59, last_added_at: ago(40), since: ago(60 * 24 * 20), partial: false, ...meta() },
    website: { known: true, expected: 1150, matched: 1150, pending: null, pending_reason: 'Scholarship feed items are not compared with the stored scholarship, so pending is not measured.', missing: 0, not_applicable: 0, ...meta() }, zoho: unknown('The Zoho scholarship comparison is not built yet. Follow-up gap.'),
    queue: { known: true, n: 0, partial: false, parts: [], reasons: [] }, holds: { known: true, n: 3, partial: false, parts: [], reasons: [{ reason: 'Waiting for review', n: 3, stage: 'Layer 4' }] },
    speed: { known: true, processed: 8, window_hours: 24, per_hour: 0.3, basis: 'scholarship admission decisions in the window' },
    jobs: jobs([job('scholarship-read', { active: false, next_run: null })]), recovery: { state: 'paused', text: 'Paused: scholarship-read is paused, so that work does not run until it is switched on', open_issues: 0, issue_refs: [], remedy_acted: 0, remedy_refused: 0 }, flags: [] },
]

export const DATA_DELIVERY = {
  at: new Date().toISOString(), timezone: 'Australia/Melbourne', ui_refresh_seconds: 60, stale_after_minutes: 30, windows: { short_hours: 24, long_hours: 168 },
  snapshot: { oldest_measured_at: ago(9), newest_measured_at: ago(1), failed_measures: 1, job: { active: true, schedule: '* * * * *', last_status: 'succeeded' } },
  provider_filters_available: true, streams: STREAMS, meaning: { unknown: 'Unknown or Not measured means the figure is not counted here; it is never shown as 0' },
}

/** The course description stage counts exactly as security.data_delivery_cdesc_stages_v1() returns them (the cdesc fixture's own numbers). Added to the cdesc stream by the stage tests only. */
export const STAGES = {
  known: true, counted_at: new Date().toISOString(), unit: 'courses',
  source: { proposals_from_a_stored_page: 9 },
  proposal: { waiting_in_layer4: 5, held_behind_provider_cap: 1, held_by_a_check: 1 },
  validation: { not_yet_checked_by_machine: 0, declined_by_machine: 5, top_decline_reasons: [{ code: 'wrong_page_kind', n: 5, example: 'The description was read from a page whose address has the part "requirements"' }] },
  admitted: { by_machine: 3, by_person: 1, withdrawn: 1, described_courses: 5, described_other_route: 1 },
  consumers: { website_published: 1, unpublished_course: 4, machine_readback: { matched: 3, lag: 0, not_in_feed: 0, error: 0, not_checked: 0 },
    zoho: { known: false, reason: 'The latest course item in the Zoho course feed has no description field, so a course description does not reach Zoho. Nothing is counted for it.' } },
  flow: {
    known: true, counted_at: new Date().toISOString(), unit: 'courses',
    eligible: { active_courses: 40, without_description: 30, never_read: 20, waiting_in_layer4: 5, held_behind_provider_cap: 2, held_by_a_check: 2, read_other: 1 },
    gain: { admitted_24h: 3, admitted_7d: 7, withdrawn_7d: 1, retained_total: 6 },
    declined_by_cause: [{ code: 'wrong_page_kind', n: 3 }, { code: 'twin_course', n: 2 }], held_by_cause: [{ code: 'unsupported_claim', n: 2 }],
    reads: { today: 4, daily_cap: 500, universities_with_all_places_taken: 1, parked_for_a_person: 5 },
    run: { automatic_admission_on: true, last_admission_at: new Date().toISOString(), last_decline_at: new Date().toISOString(), schedule: '*/10 * * * *' },
    blocker: '1 universities have every place taken by waiting descriptions; no new reading is made for them until a person decides.',
  },
}
/** DATA_DELIVERY with the stage counts on the cdesc stream (or any other stages value). */
export const withStages = (stages = STAGES) => ({ ...DATA_DELIVERY, streams: DATA_DELIVERY.streams.map((s) => (s.stream === 'cdesc' ? { ...s, stages } : s)) })

/** The provider AI cost, admissions and upgrade counts exactly as security.data_delivery_pdesc_v1() returns them (live figures of 10 Nov 2026 12:00 UTC). Added to the pdesc stream by the provider AI tests only. */
export const PROVIDER_AI = {
  known: true, counted_at: new Date().toISOString(), unit: 'providers',
  ai: { ceiling_usd: 0.75, spent_usd: 0.2837956, calls: 187, reserved_usd: 0.136690016, reserved_reads: 19, remaining_usd: 0.329514384, today_usd: 0.1856412, daily_guard_usd: 1, daily_remaining_usd: 0.677668784, settled_estimated_reads: 60, settled_estimated_usd: 0.18 },
  admitted: { ai_first_description: 2, ai_upgrade: 0, registry_fact: 1088, by_person: 0, withdrawn: 0 },
  upgrade: { lane_on: true, admitted: 0, basic_profiles_held: 1088, queued_reads: 9, held_reads: 8,
    top_hold_rules: [{ rule: 'provider_name_not_proved', n: 6, example: "The page does not prove the provider's current full institutional identity; no AI call was made." }, { rule: 'no_about_page', n: 1, example: 'no About or Overview link on the home page' }, { rule: 'not_stated', n: 1, example: 'the page does not describe the institution' }] },
}
/** DATA_DELIVERY with the provider AI counts on the pdesc stream (or any other provider_ai value). */
export const withProviderAi = (provider_ai = PROVIDER_AI) => ({ ...DATA_DELIVERY, streams: DATA_DELIVERY.streams.map((s) => (s.stream === 'pdesc' ? { ...s, provider_ai } : s)) })

/** Answers admin_layer23('data_delivery') and passes every other action to the admin mock registered before it. Returns the call log and a switch to fail the read. */
export async function mockDataDelivery(page, payload = DATA_DELIVERY) {
  const state = { calls: 0, fail: null, hang: false, payload }
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer23', async (r) => {
    const b = r.request().postDataJSON?.() || {}
    if (b.p_action !== 'data_delivery') return r.fallback()
    state.calls += 1
    if (state.hang) return // never answered: the page must give up on its own
    if (state.fail) return r.fulfill({ status: 500, json: { message: state.fail } })
    return r.fulfill({ json: { ...state.payload, at: new Date().toISOString() } })
  })
  return state
}

/** Three action-needed notice cards above the page body (the default admin mock's Layer 2 notices): the Data Delivery panel must stay above them. */
export const THREE_ALERTS = '[data-layer-notices] [data-notice]'
