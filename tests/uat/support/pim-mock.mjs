// Mock for the Autonomous PIM block (s1217): a `pim` snapshot shaped like the live one (security.pim_progress_v1, counted by the data-delivery job), and the field
// register read the block uses for domain grouping. Figures are a trimmed copy of the live read of 26 Nov 2026. Nothing reaches a real backend.
import { DATA_DELIVERY, mockDataDelivery } from './data-delivery-mock.mjs'

const row = (country, field, o = {}) => ({
  country, field, applicable: 0, not_applicable: 0, unconfirmed: 0, held: 0, backlog: 0, queued: 0, running: 0, review: 0, failed: 0, no_source_found: 0,
  expired_leases: 0, canonical_gain_window: 0, published_gain_window: 0, gain_basis: ENRICH_BASIS, throughput_per_hour: 0, clearance_hours: null,
  oldest_outstanding: null, ...o,
})

// The live snapshot measures academic entry on its own basis (courses whose first active entry row was created in the window); every other field counts enrich items filled.
export const ENTRY_BASIS = 'canonical: courses whose first active entry row was created in the window'
export const ENRICH_BASIS = 'enrich items filled in the window'

export const PIM_FIELDS = [
  row('AU', 'academic_entry', { gain_basis: ENTRY_BASIS, applicable: 25639, held: 10206, backlog: 15433, canonical_gain_window: 547, published_gain_window: 547, throughput_per_hour: 22.79, clearance_hours: 677.1 }),
  row('AU', 'english', { applicable: 25639, held: 16840, backlog: 8799, no_source_found: 12929 }),
  row('AU', 'description', { applicable: 25703, held: 12685, backlog: 13018, review: 94, failed: 3326, no_source_found: 35262, canonical_gain_window: 54, published_gain_window: 54, throughput_per_hour: 2.25, clearance_hours: 5785.8, oldest_outstanding: '2026-11-04T04:23:00+00:00' }),
  row('AU', 'intakes', { applicable: 25703, held: 9658, backlog: 16045, failed: 543, no_source_found: 23303, canonical_gain_window: 1, published_gain_window: 1, throughput_per_hour: 0.04, clearance_hours: 385080 }),
  row('AU', 'campus', { applicable: 25703, held: 25672, backlog: 31, review: 1, failed: 1, no_source_found: 90, oldest_outstanding: '2026-10-20T21:19:35+00:00' }),
  row('AU', 'duration', { applicable: 25703, held: 25703 }),
  row('NZ', 'academic_entry', { gain_basis: ENTRY_BASIS, applicable: 2111, held: 325, backlog: 1786, unconfirmed: 4269, not_applicable: 140 }),
  row('NZ', 'english', { applicable: 2111, held: 1490, backlog: 621, no_source_found: 6636 }),
  row('NZ', 'description', { applicable: 6520, held: 1812, backlog: 4708, review: 54, failed: 1088, no_source_found: 9300, oldest_outstanding: '2026-11-03T03:45:00+00:00' }),
  row('NZ', 'intakes', { applicable: 6520, held: 2234, backlog: 4286, failed: 107, no_source_found: 6574 }),
  row('NZ', 'campus', { applicable: 6498, held: 2693, backlog: 3805, queued: 1, review: 759, failed: 117, no_source_found: 9108, oldest_outstanding: '2026-10-14T00:18:46+00:00' }),
  row('NZ', 'duration', { applicable: 6520, held: 2611, backlog: 3909, failed: 107, no_source_found: 7684 }),
  row('CA', 'academic_entry', { gain_basis: ENTRY_BASIS, applicable: 3829, held: 0, backlog: 3829 }),
  row('CA', 'english', { applicable: 3829, held: 2085, backlog: 1744, no_source_found: 4251 }),
  row('CA', 'description', { applicable: 3829, held: 1604, backlog: 2225, review: 9, failed: 715, no_source_found: 6446, oldest_outstanding: '2026-11-15T05:23:00+00:00' }),
  row('CA', 'intakes', { applicable: 3829, held: 1789, backlog: 2040, failed: 127, no_source_found: 3992 }),
  row('CA', 'campus', { applicable: 3814, held: 2310, backlog: 1504, queued: 4, review: 300, failed: 81, no_source_found: 4881, oldest_outstanding: '2026-10-14T01:09:16+00:00' }),
  row('CA', 'duration', { applicable: 3829, held: 1737, backlog: 2092, failed: 165, no_source_found: 7167 }),
  row('CA', 'registered_tuition', { applicable: 0, not_applicable: 3829 }),
]

export const REGISTER = [
  { field: 'official_url', label: 'Official course page', group: 'Course page' }, { field: 'description', label: 'Course description', group: 'Course page' },
  { field: 'intakes', label: 'Intakes / start dates', group: 'Dates' }, { field: 'english', label: 'English requirements', group: 'Entry' },
  { field: 'academic_entry', label: 'Academic entry requirements', group: 'Entry' }, { field: 'campus', label: 'Campus linked', group: 'Location' },
  { field: 'registered_tuition', label: 'Registered tuition (register)', group: 'Cost' }, { field: 'duration', label: 'Duration', group: 'Study' },
]

// s1220: `pim.operations` shaped like the live s1175 read (security.pim_progress_v1 `operations`, counted into the same snapshot). Zoho is null for stream `sch`.
const cons = (cc, expected, w, z) => ({ cc, expected, w_matched: w[0], w_missing: w[1], w_pending: w[2], w_not_served: w[3], z_matched: z ? z[0] : null, z_missing: z ? z[1] : null, z_pending: z ? z[2] : null, z_not_served: z ? z[3] : null })
export const OPERATIONS = {
  as_at: '2026-11-26T02:03:09+00:00', jobs_summary_at: '2026-11-26T02:02:30+00:00',
  meaning: 'Worker status is read from the scheduled-job summary; a worker is stalled when its last success is older than the stall window or it has never succeeded.',
  workers: [
    { job: 'enrich-plan-run', running: true, stalled: false, schedule: '*/5 * * * *', failed_24h: 0, last_start: '2026-11-26T02:00:00+00:00', last_success: '2026-11-26T02:00:04+00:00' },
    { job: 'field-gap-queue', running: false, stalled: false, schedule: '35 * * * *', failed_24h: 2, last_start: '2026-11-26T01:35:00+00:00', last_success: '2026-11-26T01:35:41+00:00' },
    { job: 'enrich-plan-auto', running: false, stalled: true, schedule: '41 * * * *', failed_24h: 5, last_start: '2026-11-25T13:41:00+00:00', last_success: null },
  ],
  stalled_workers: 1, expired_leases: 0,
  consumer: [
    { stream: 'disc', measured_at: '2026-11-26T02:01:00+00:00', error: null, rows: [cons('AU', 1200, [1100, 20, 60, 20], [1090, 25, 65, 20]), cons('NZ', 300, [250, 10, 30, 10], [240, 12, 38, 10])] },
    { stream: 'int', measured_at: '2026-11-26T02:01:00+00:00', error: null, rows: [cons('AU', 5000, [4000, 500, 400, 100], [3900, 550, 450, 100])] },
    { stream: 'sch', measured_at: '2026-11-26T02:01:00+00:00', error: null, rows: [cons('AU', 800, [700, 40, 40, 20], null)] },
    { stream: 'fee', measured_at: '2026-11-25T20:00:00+00:00', error: 'read timed out', rows: null },
  ],
  freshness_by_country: [
    { country: 'AU', field: 'description', held: 12685, refresh_due: 40 }, { country: 'AU', field: 'academic_entry', held: 10206, refresh_due: 0 },
    { country: 'NZ', field: 'description', held: 1812, refresh_due: 12 }, { country: 'CA', field: 'campus', held: 0, refresh_due: 0 },
  ],
  requests: { status: 'not_projected', reason: 'No registered database source holds the StudySearch request register; it is kept by the requirements register outside the database.' },
}
// The same operations with every worker on time (no stalled processing).
export const OPERATIONS_HEALTHY = { ...OPERATIONS, stalled_workers: 0, workers: OPERATIONS.workers.map((w) => ({ ...w, stalled: false, last_success: w.last_success || '2026-11-26T01:41:00+00:00' })) }

export const PIM = {
  as_at: '2026-11-26T02:03:09+00:00', snapshot_at: '2026-11-26T02:03:09+00:00', snapshot_ms: 41000, snapshot_error: null, snapshot_failed_at: null, window_hours: 24,
  fields: PIM_FIELDS,
  source_findings: [],
  jobs: [
    { job: 'enrich-plan-auto', active: true, schedule: '41 * * * *', next_run: '2026-11-26T02:41:00+00:00' },
    { job: 'enrich-plan-run', active: true, schedule: '*/5 * * * *', next_run: '2026-11-26T02:05:00+00:00' },
    { job: 'field-gap-queue', active: true, schedule: '35 * * * *', next_run: '2026-11-26T02:35:00+00:00' },
  ],
  gap_queue: { cycle: 525, cycle_found: 2053, last_run_at: '2026-11-26T01:35:00+00:00', cycle_scanned: 36052, cycle_started_at: '2026-11-26T01:35:00+00:00' },
  ai: { failed: 648, attempts: 8554, cost_usd: 4.5028 }, firecrawl: { calls: 781, credits: 1189 },
  human_required: { enrich_review: 1838, layer4_waiting: [
    { field: 'course_entry_first_read', oldest: '2026-10-29T20:37:40+00:00', waiting: 766 }, { field: 'official_course_url', oldest: '2026-10-31T06:20:00+00:00', waiting: 178 },
  ] },
  leases: { expired: 0, recovery: 'A lease past its time is taken back by the next worker claim; nothing is restored by hand.' },
  drill: { layer4: 'Layer 4 Review', operations: 'Layer 2/3 Build & enrich › Operations', queues_and_lanes: 'Scheduled jobs › Queue & lane control' },
  meaning: { applicable: 'fields the register says apply', published_gain: 'canonical gains for courses of a published provider', clearance_hours: 'backlog divided by the measured hourly gain in the window; null when nothing was gained, never a guess' },
  refresh: { as_at: '2026-11-26T02:03:09+00:00', window_days: 365, meaning: 'Held values past their refresh window are due to be verified again; the old value stays until a verified successor replaces it.',
    fields: [{ field: 'academic_entry', held: 11230, refresh_due: 0, oldest_verified: '2026-08-17T09:29:15+00:00' }, { field: 'description', held: 16101, refresh_due: 40, oldest_verified: '2026-08-17T09:29:15+00:00' }],
    sources: [{ outcome: 'blocked', pages: 146, due_for_reread: 0, protected_hold: true }, { outcome: 'fetch_failed', pages: 1732, due_for_reread: 1679, protected_hold: false }, { outcome: 'read', pages: 22323, due_for_reread: 24, protected_hold: false }] },
  excluded: { as_at: '2026-11-26T02:03:09+00:00', totals: { eligible: 147495, eligible_unconfirmed: 7637, closed_to_international: 199, recorded_not_applicable: 37, no_source_revisit_pending: 209 },
    meaning: 'Non-admitted course field gaps by why they are or are not worked now. Excluded gaps are workload, not delivered data.',
    by_field: [{ field: 'campus', reason: 'eligible', gaps: 5340, next_revisit: null }, { field: 'description', reason: 'no_source_revisit_pending', gaps: 209, next_revisit: '2026-11-26T09:49:58+00:00' }] },
  lifecycle: {
    scholarships: { owner: 'scholarship lanes', providers: [{ country: 'AU', providers: 70, disposition: 'published', reviews_pending: 32, scholarships_published: 889 }, { country: 'NZ', providers: 13, disposition: 'published', reviews_pending: 17, scholarships_published: 120 }] },
    academic_entry: { stages: [{ stage: 'admitted', country: 'AU', courses: 10206 }, { stage: 'no_page', country: 'NZ', courses: 3433 }], next_owner: { admitted: 'refresh (PIM step 5)', no_page: 'course pages (S1-Build)' } },
    replacement_check: { checked: 2153, flagged: 1773, meaning: 'Guarded supersessions in the window tested again: flagged ones need a person; nothing is reversed automatically.', window_hours: 168 },
  },  operations: OPERATIONS,
}

// What the read carried before s1175: no `operations`, so every operations figure is labelled not available.
export const PIM_NO_OPERATIONS = (() => { const { operations, ...rest } = PIM; return rest })()
export const SNAPSHOTS = {
  aer: { as_at: '2026-11-26T02:02:00+00:00', error: null, took_ms: 410, failed_at: null }, pdesc: { as_at: '2026-11-26T02:02:00+00:00', error: null, took_ms: 120, failed_at: null },
  intake: { as_at: '2026-11-26T00:10:00+00:00', error: 'statement timeout', took_ms: null, failed_at: '2026-11-26T02:00:00+00:00' }, cdesc_stages: { as_at: '2026-11-26T02:02:00+00:00', error: null, took_ms: 90, failed_at: null },
}
export const withPim = (pim = PIM) => ({ ...DATA_DELIVERY, pim, snapshots: SNAPSHOTS })

/** Mock the Data Delivery read (with `pim`) and the field register read. `register: 'fail'` makes the register read fail. */
export async function mockPim(page, { pim = PIM, register = REGISTER } = {}) {
  const dd = await mockDataDelivery(page, withPim(pim))
  const reg = { calls: 0 }
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_field_coverage', async (r) => {
    const b = r.request().postDataJSON?.() || {}
    if (b.p_action !== 'overview') return r.fallback()
    reg.calls += 1
    if (register === 'fail') return r.fulfill({ status: 500, json: { message: 'register unavailable' } })
    return r.fulfill({ json: { register } })
  })
  return { dd, reg }
}
