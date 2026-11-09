// Mocked answer for public.admin_layer23('data_delivery') (F-OPS.03A). The shape follows security.data_delivery_v1 in
// supabase/migrations/20261109210000_cf247_fops03a_data_delivery.sql. Nothing reaches a real backend.
const ago = (m) => new Date(Date.now() - m * 60000).toISOString()
const soon = (m) => new Date(Date.now() + m * 60000).toISOString()
const meta = (m = 3) => ({ measured_at: ago(m), age_minutes: m, stale: false, took_ms: 400 })
const unknown = (reason) => ({ known: false, reason })
const job = (name, over = {}) => ({ job: name, scheduled: true, active: true, schedule: '26 * * * *', next_run: soon(14), last_start: ago(46), last_end: ago(45), last_status: 'succeeded', last_message: 'done', runs: 1, succeeded: 1, failed: 0, ...over })
const jobs = (list, over = {}) => ({ last_run_at: ago(46), next_run_at: soon(14), runs: 1, succeeded: 1, failed: 0, last_status: 'succeeded', last_message: 'done', active: list.length, total: list.length, history_hours: 48, known: true, reason: null, list, ...over })

export const STREAMS = [
  { stream: 'pdesc', title: 'Provider descriptions', unit: 'providers', what: 'Official About pages to provider descriptions.', lane: 'pdesc', net_basis: 'Machine admissions and Layer 4 approvals, by timestamp', stale: false,
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
  { stream: 'int', title: 'Intake dates and deadlines', unit: 'intake rows', what: 'Course page and calendar evidence to exact start dates.', lane: 'int', net_basis: 'Intake date events by run time', stale: false,
    drill: { screen: 'courses', filled: { hasIntake: 'true' }, missing: { hasIntake: 'false' }, website: null, zoho: null, needs_provider_filters: false, note: 'The Course Catalogue has no Website or Zoho state filter, so pending and missing courses are counted but not listed (follow-up gap).' },
    coverage: { known: true, n: 1563, total: 20000, pct: 7.8, by_country: [{ cc: 'AU', n: 1500, total: 18000 }], ...meta() },
    net_short: { known: true, window_hours: 24, added: 0, removed: 0, removed_known: true, net: 0, processed: 589, last_added_at: ago(60 * 30), since: ago(60 * 24 * 4.4), partial: true, ...meta() },
    net_long: { known: true, window_hours: 168, added: 120, removed: 3, removed_known: true, net: 117, processed: 2000, last_added_at: ago(60 * 30), since: ago(60 * 24 * 4.4), partial: true, ...meta() },
    website: { known: true, expected: 958, matched: 958, pending: 0, missing: 0, not_applicable: 0, ...meta() }, zoho: { known: true, expected: 958, matched: 958, pending: 0, missing: 0, not_applicable: 0, ...meta() },
    queue: { known: true, n: 16174, partial: false, parts: [{ stage: 'selected', title: 'Selected and evaluated', kind: 'eligible', n: 16174 }], reasons: [] },
    holds: { known: true, n: 575, partial: false, parts: [{ stage: 'held', title: 'Held, by cause', kind: 'held', n: 575 }], reasons: [{ reason: 'missing_application_deadline', n: 400, stage: 'Held, by cause' }] },
    speed: { known: true, processed: 589, window_hours: 24, per_hour: 24.5, basis: 'intake decisions in the window' },
    jobs: jobs([job('intake-dates-apply', { runs: 24, succeeded: 24 })], { runs: 24, succeeded: 24 }), recovery: { state: 'healthy', text: 'No open issues; the scheduled job retries on its next run', open_issues: 0, issue_refs: [], remedy_acted: 0, remedy_refused: 0 },
    flags: [{ code: 'green_no_admission', severity: 'warn', text: 'Ran OK 24 time(s) in 24 h, admitted nothing (missing_application_deadline)' }] },
  { stream: 'eng', title: 'English entry requirements', unit: 'courses', what: 'University English policies to course English rows.', lane: 'eng', net_basis: 'Layer 4 approvals of course English', stale: false,
    drill: { screen: 'courses', filled: { hasEnglish: 'true' }, missing: { hasEnglish: 'false' }, website: null, zoho: null, needs_provider_filters: false, note: null },
    coverage: { known: true, n: 16350, total: 36000, pct: 45.4, by_country: [], ...meta() },
    net_short: { known: true, window_hours: 24, added: 0, removed: null, removed_known: false, removed_reason: 'A withdrawn English row has no withdrawal time, so removals are not counted.', net: null, processed: null, last_added_at: null, since: ago(60 * 24 * 40), partial: false, ...meta() },
    net_long: { known: true, window_hours: 168, added: 4, removed: null, removed_known: false, removed_reason: 'A withdrawn English row has no withdrawal time, so removals are not counted.', net: null, processed: null, last_added_at: null, since: ago(60 * 24 * 40), partial: false, ...meta() },
    website: { known: true, expected: 100, matched: 99, pending: 1, missing: 0, not_applicable: 0, ...meta() }, zoho: unknown('The Zoho comparison for English is not built yet. Follow-up gap.'),
    queue: unknown('There is no English reader queue stage, so the queue is not counted.'),
    holds: { known: true, n: 1, partial: false, parts: [{ stage: 'human', title: 'Waiting for a person (course English)', kind: 'human_review', n: 1 }], reasons: [{ reason: 'Waiting for a person (course English)', n: 1, stage: 'x' }], causes_reason: 'English holds are not recorded by cause; only items waiting for a person are counted.' },
    speed: unknown('English reads have no timestamped ledger, so items per hour cannot be counted.'),
    jobs: jobs([job('central-attach')], { known: false, last_run_at: null, next_run_at: soon(20), reason: 'No run of central-attach in the last 48 hours of scheduler history' }),
    recovery: { state: 'failing', text: 'The last run failed; the job retries at its next scheduled run (9 Nov 22:48 Melbourne)', open_issues: 1, issue_refs: ['IQ-00111'], remedy_acted: 0, remedy_refused: 0 },
    flags: [{ code: 'job_failing', severity: 'bad', text: '2 failed run(s) in 24 h' }] },
  { stream: 'cdesc', title: 'Course descriptions', unit: 'courses', what: 'Source-backed course description proposals.', lane: 'cdesc', net_basis: 'Layer 4 approvals of the first reading', stale: true,
    drill: { screen: 'courses', filled: null, missing: null, website: null, zoho: null, needs_provider_filters: false, note: 'The Course Catalogue has no description filter yet, so the filled and missing courses cannot be listed (follow-up gap).' },
    coverage: { known: false, reason: 'Could not be counted: canceling statement due to statement timeout', ...meta(95), stale: true },
    net_short: { known: true, window_hours: 24, added: 0, removed: null, removed_known: false, removed_reason: 'A course description that is edited or cleared leaves no ledger event, so removals are not counted.', net: null, processed: 416, last_added_at: null, since: null, partial: true, ...meta() },
    net_long: { known: true, window_hours: 168, added: 0, removed: null, removed_known: false, removed_reason: 'x', net: null, processed: 3000, last_added_at: null, since: null, partial: true, ...meta() },
    website: unknown('Whether the course description reaches the Website and Zoho course feed items is not compared yet (no feed field check is built for it). Follow-up gap.'), zoho: unknown('Whether the course description reaches the Website and Zoho course feed items is not compared yet (no feed field check is built for it). Follow-up gap.'),
    queue: unknown('The description reader keeps no waiting state, so its queue is not counted.'), holds: { known: true, n: 4803, partial: true, parts: [], reasons: [{ reason: 'duplicate_of_another_course', n: 23, stage: 'Held by a check' }] },
    speed: { known: true, processed: 416, window_hours: 24, per_hour: 17.3, basis: 'description reader items updated in the window' },
    jobs: jobs([job('enrich-plan-run', { schedule: '*/5 * * * *' })]), recovery: { state: 'needs_attention', text: '1 open issue(s) and no automatic remedy has acted in the window', open_issues: 1, issue_refs: ['IQ-00200'], remedy_acted: 0, remedy_refused: 1 }, flags: [{ code: 'measure_unknown', severity: 'info', text: 'A headline measure could not be counted; see the reason in the cell' }] },
]

export const DATA_DELIVERY = {
  at: new Date().toISOString(), timezone: 'Australia/Melbourne', ui_refresh_seconds: 60, stale_after_minutes: 30, windows: { short_hours: 24, long_hours: 168 },
  snapshot: { oldest_measured_at: ago(9), newest_measured_at: ago(1), failed_measures: 1, job: { active: true, schedule: '* * * * *', last_status: 'succeeded' } },
  provider_filters_available: true, streams: STREAMS, meaning: { unknown: 'Unknown or Not measured means the figure is not counted here; it is never shown as 0' },
}

/** Answers admin_layer23('data_delivery') and passes every other action to the admin mock registered before it. Returns the call log and a switch to fail the read. */
export async function mockDataDelivery(page, payload = DATA_DELIVERY) {
  const state = { calls: 0, fail: null, payload }
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer23', async (r) => {
    const b = r.request().postDataJSON?.() || {}
    if (b.p_action !== 'data_delivery') return r.fallback()
    state.calls += 1
    if (state.fail) return r.fulfill({ status: 500, json: { message: state.fail } })
    return r.fulfill({ json: { ...state.payload, at: new Date().toISOString() } })
  })
  return state
}
