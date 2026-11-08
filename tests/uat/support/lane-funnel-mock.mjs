// Mocked answers for public.admin_lane_funnel_v1 and public.admin_firecrawl_acceptance_v1 (OPS/UI lane). Shapes follow the server functions in
// supabase/migrations/20261108170000_cf247_lane_funnels.sql. Nothing reaches a real backend.
const NOW = new Date().toISOString()
const ago = (h) => new Date(Date.now() - h * 3600000).toISOString()
const soon = (m) => new Date(Date.now() + m * 60000).toISOString()

export const LANES = {
  at: NOW, window_hours: 24,
  lanes: [
    { lane: 'fee', title: 'Tuition and other fees', what: 'Fee schedules read into fee rows, checked, admitted and held as active course fees.', screen: 'Layer 2/3 > Enrich fields > Fee reader',
      verdict: 'green_no_transfer', jobs_total: 2, jobs_active: 2, jobs_failing: 0, jobs_green: 2, transfer_24h: 0, published_24h: null,
      jobs: [
        { job: 'fee-reader', label: 'Fee reader', scheduled: true, active: true, schedule: '*/10 * * * *', control_rank: 5, next_run: soon(6), running: false, runs: 12, succeeded: 12, failed: 0, last_start: ago(0.2), last_status: 'succeeded', first_run: null },
        { job: 'fee-period-settle', label: 'Fee period settle', scheduled: true, active: false, schedule: '0 * * * *', control_rank: 5, next_run: null, running: false, runs: 1, succeeded: 1, failed: 0, last_start: ago(30), last_status: 'succeeded', first_run: null }],
      switches: [{ key: 'fees.course_pages', on: false, label: 'Read course pages for fees' }, { key: 'fees.identity_gate_on', on: null }],
      settings: [{ key: 'fees.batch', label: 'Fee reader batch', value: 20, min: 1, max: 200, unit: 'items', used_by: 'fee-reader', updated_at: ago(80), reason: 'Platform Admin' }],
      stages: [
        { key: 'queued', title: 'Waiting for the fee reader', kind: 'queued', what: 'Fee reader queue items not yet done or failed.', n: 0, oldest_at: null, gain: null, n_prev: 4, measured_at: ago(0.1), stale: false, source: 'count' },
        { key: 'read', title: 'Fee rows read', kind: 'in_flight', what: 'Rows the reader extracted.', n: 310, oldest_at: ago(500), gain: 12, n_prev: 298, measured_at: ago(0.1), stale: false, source: 'count' },
        { key: 'human', title: 'Waiting for a person (tuition)', kind: 'human_review', what: 'Layer 4 tuition items pending a decision.', n: 7, oldest_at: ago(70), gain: 1, n_prev: 6, measured_at: ago(0.1), stale: false, source: 'count', drill: 'layer4/inbox' },
        { key: 'withdrawn', title: 'Fee rows withdrawn', kind: 'withdrawn', what: 'Fee rows made inactive.', n: 3, oldest_at: null, gain: 3, n_prev: 0, measured_at: ago(0.1), stale: false, source: 'count' },
        { key: 'uncounted', title: 'Not yet counted stage', kind: 'eligible', what: 'This stage has no reading yet.', n: null, oldest_at: null, gain: null, n_prev: null, measured_at: null, stale: false, error: null, source: 'count' }] },
    { lane: 'aer', title: 'Academic entry requirements (AER)', what: 'Official sources to read rows, review, active entry rows and Website publication.', screen: 'Layer 4 > Inbox (Entry requirements)',
      verdict: 'transferring', jobs_total: 1, jobs_active: 1, jobs_failing: 0, jobs_green: 1, transfer_24h: 14, published_24h: 14,
      budget: { label: 'Reading pages', credits_window: 153, used_today: 153, share_today: 1200, refused_today: 90 },
      jobs: [{ job: 'aer-scheduled-read', label: 'AER scheduled read', scheduled: true, active: true, schedule: '*/15 * * * *', control_rank: 6, next_run: soon(9), running: false, runs: 4, succeeded: 4, failed: 0, last_start: ago(0.3), last_status: 'succeeded', first_run: { status: 'operationally_verified', release: '2.15.480' } }],
      switches: [{ key: 'aer.replay_on', on: true }], settings: [],
      issues: [{ ref: 'IQ-00313', status: 'open', severity: 'P0' }],
      stages: [{ key: 'active', title: 'Active entry rows', kind: 'published', what: 'Active entry rows.', n: 9120, oldest_at: null, gain: 14, n_prev: 9106, measured_at: ago(0.1), stale: false, source: 'count' }] },
    { lane: 'sch', title: 'Scholarships', what: 'Coverage cases to published scholarships.', screen: 'Layer 2/3 > Scholarships', verdict: 'stalled', jobs_total: 1, jobs_active: 1, jobs_failing: 0, jobs_green: 1, transfer_24h: 0, published_24h: 0,
      jobs: [], switches: [], settings: [],
      stages: [{ key: 'sch_eligibility', title: 'Eligibility', kind: 'eligible', what: 'Eligible cases.', n: 120, oldest_at: ago(300), gain: 0, n_prev: 120, measured_at: ago(0.1), stale: false, stalled: true, zero_reason: 'no_progress', source: 'progress contract' }] },
  ],
}

export const FIRECRAWL = {
  at: NOW, unit: 'credits', note: 'Credits are counted by the platform; the vendor bill is not shown here and credits are not money.',
  allowance: { plan_credits: 100000, monthly_limit_credits: 100000, stop_at_remaining_credits: 3000, plan_tier: 'standard', period_start: ago(24 * 20), period_end: soon(60 * 24 * 10) },
  vendor: { remaining_credits: 100228, read_at: ago(0.2), age_minutes: 12, fresh: true, estimated_now_credits: 100190, used_since_reading_credits: 38, above_plan: true },
  sync: { job: 'firecrawl-credit', schedule: '*/15 * * * *', active: true, next_run: soon(3), last_start: ago(0.2), last_status: 'succeeded' },
  floor: { setting: 'firecrawl / priority_floor_course_search', credits: 20000, applies: true, room_credits: 80190, under_floor: false, switched_off: false },
  daily: { budget_on: true, total_credits: 4000, used_today: 2020, billed_today: 40,
    groups: [{ group: 'course_search', label: 'Finding course pages', share: 800, used: 1776, refused: 209, left: 0 }, { group: 'reads', label: 'Reading pages', share: 1200, used: 153, refused: 90, left: 1047 },
      { group: 'scholarships', label: 'Scholarships', share: 800, used: 0, refused: 864, left: 800 }],
    days: [{ day: '2026-11-08', group: 'reads', credits: 153 }, { day: '2026-11-07', group: 'reads', credits: 900 }, { day: '2026-11-07', group: 'course_search', credits: 760 }], days_shown: 7 },
  usage: { window_hours: 24, by_group: [{ group: 'reads', credits_window: 153, credits_period: 5100, on_demand_window: 0 }, { group: 'scholarships', credits_window: 0, credits_period: null, on_demand_window: 0 }],
    by_purpose: [{ purpose: 'scrape', group: 'reads', credits_window: 153, calls_window: 51, last_at: ago(0.5) }] },
}

// controls: the audited control calls the page made are collected in `calls`
export async function mockLaneFunnels(page, { lanes = LANES, firecrawl = FIRECRAWL } = {}) {
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_lane_funnel_v1', (r) => r.fulfill({ json: lanes }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_firecrawl_acceptance_v1', (r) => r.fulfill({ json: firecrawl }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_automation_control', async (r) => { calls.push(r.request().postDataJSON()); await r.fulfill({ json: { ok: true } }) })
  return calls
}
