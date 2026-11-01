// SS-016 role simulation (Platform Admin mandate 1 Nov 2026 §3): isolated fixtures for the six roles. Each mocked server function refuses
// exactly where its LIVE definition refuses, with the live words (read-only from project fxcwkweaxjtknorudmwp, 1 Nov 2026):
//   security.admin_automation_control_v1 (md5 71951aa2): rank < 5 -> PIM_FLOOR; rank < control_rank -> HIGHER_ROLE; a retiring or retired job
//     cannot be switched on, run or changed (RETIRED); an area resume skips retiring and retired jobs.
//   public.admin_layer4_inbox (md5 417f181d): rank < 3 -> 'Curator role or above required'; a choice without its own rank needs rank 4
//     (coalesce((v_c->>'rank')::int, 4)) -> 'your role cannot make this choice'.
//   security.layer4_review_decide_impl (md5 67966ceb): rank < 3 -> 'curator role required'; an AER item needs rank 6 (AER_PA).
//   public.admin_aer (md5 5e58f5d6): read from rank 1; update, add and lifecycle (withdraw, quarantine, restore) from rank 3
//     ('Curator role or above required'); reread rank 6 ('Platform Admin role required').
//   public.admin_jobs (md5 f75cc75f): rank < 4 -> 'Operator or above required'.
// Nothing here reaches a real backend; it only lets the browser journeys meet the server's boundary.
import { mockAdmin } from './admin-mock.mjs'

export const ROLE = { 1: ['viewer', 'Viewer'], 2: ['counsellor', 'Counsellor'], 3: ['curator', 'Curator'], 4: ['pipeline_operator', 'Pipeline Operator'], 5: ['pim_admin', 'PIM Admin'], 6: ['platform_admin', 'Platform Admin'] }
export const LIVE = {
  PIM_FLOOR: 'PIM Admin role or above required to change automations. A Pipeline Operator records the issue and raises it with the PIM Admin',
  HIGHER_ROLE: 'this automation needs a higher role to change',
  RETIRED: (by) => `this automation is retired (${by ? `replaced by ${by}` : 'no replacement recorded'}); it cannot be switched on, run or changed`,
  INBOX_FLOOR: 'Curator role or above required',
  CHOICE: 'your role cannot make this choice',
  AER_PA: 'Platform Admin role required: AER items are admitted or rejected by the Platform Admin (decision A3)',
  AER_CURATOR: 'Curator role or above required',
  AER_PA_ONLY: 'Platform Admin role required',
  JOBS_FLOOR: 'Operator or above required',
}
const refuse = (route, message, code = '42501') => route.fulfill({ status: 400, json: { code, message, details: null, hint: null } })

/** Signed in at a rank with that rank's role name; the admin mock serves everything else. */
export async function asRole(page, rank, opts = {}) {
  await mockAdmin(page, { rank, role: ROLE[rank][0], ...opts })
  // Settings › API usage (rank 4) is the tab a lower role is shown in place of a Platform Admin tab: its read, empty
  // Platform health › Storage & retention (rank 6): its read, empty
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_retention', r => r.fulfill({ json: { database_bytes: 0, runs: [], categories: [] } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_usage', r => r.fulfill({ json: { days: 14, keys: [], daily: [], recent_errors: [], last_hour: [], can_manage_keys: rank >= 6 } }))
}

// The automations catalogue as admin_automations_read returns it, with a retiring job and a retired one (UR-07)
export function automationJobs() {
  const last = { at: '2026-11-01T10:00:00Z', status: 'succeeded', seconds: 1.2 }
  return [
    { job: 'coverage-read', area: 'Course pages', sort: 10, label: 'Read course pages', description: 'Fetches matched course pages.', schedule: '1-59/2 * * * *', active: true, control_rank: 5, batch: 60, last, runs_24h: 720, failed_24h: 0 },
    { job: 'coverage-discover', area: 'Course pages', sort: 20, label: 'Discover course pages', description: 'Maps each provider website.', schedule: '3-59/10 * * * *', active: false, control_rank: 5, batch: 8, last, runs_24h: 0, failed_24h: 0 },
    { job: 'l4-rule-low-agreement', area: 'Course pages', sort: 30, label: 'Review rule: sources disagree', description: 'Retired rule 4.', schedule: '7 * * * *', active: false, control_rank: 5, batch: null, last, runs_24h: 0, failed_24h: 0,
      retirement: { status: 'retired', replaced_by: 'l4-rule-v2', retire_after: '2026-11-15' } },
    { job: 'cron-history-trim', area: 'Platform upkeep', sort: 10, label: 'Trim job history', description: 'Old job history.', schedule: '41 3 * * *', active: false, control_rank: 5, batch: null, last, runs_24h: 0, failed_24h: 0,
      retirement: { status: 'retiring', replaced_by: 'hygiene-check', retire_after: '2026-11-15' } },
    { job: 'consumer-api-guard', area: 'Platform upkeep', sort: 20, label: 'Consumer API guard', description: 'Checks the frozen API daily.', schedule: '11 2 * * *', active: true, control_rank: 6, batch: null, last, runs_24h: 1, failed_24h: 0 },
  ]
}

/** admin_automations_read and admin_automation_control, refusing as the live function does. Returns the calls and the job list. */
export async function mockAutomations(page, rank, { jobs = automationJobs(), staleRank = {}, staleRetired = [] } = {}) {
  const calls = []
  // staleRank / staleRetired: what an old tab still shows (a lower control rank, no retirement); the server decides on the current values
  const read = () => ({ generated_at: '2026-11-01T10:00:00Z', rank, jobs: jobs.map(j => ({ ...j, control_rank: staleRank[j.job] ?? j.control_rank, ...(staleRetired.includes(j.job) ? { retirement: undefined } : {}) })), events: [] })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_automations_read', r => r.fulfill({ json: read() }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_automation_control', async route => {
    const b = route.request().postDataJSON(); calls.push(b)
    if (rank < 5) return refuse(route, LIVE.PIM_FLOOR)
    if (b.p_action === 'pause_area' || b.p_action === 'resume_area') {
      for (const j of jobs) if (j.area === b.p_args?.area && j.control_rank <= rank && !(b.p_action === 'resume_area' && j.retirement)) j.active = b.p_action === 'resume_area'
      return route.fulfill({ json: read() })
    }
    const j = jobs.find(x => x.job === b.p_job)
    if (!j) return refuse(route, 'unknown automation', 'P0001')
    if (rank < j.control_rank) return refuse(route, LIVE.HIGHER_ROLE)
    if (b.p_action !== 'pause' && j.retirement) return refuse(route, LIVE.RETIRED(j.retirement.replaced_by), 'P0001')
    if (b.p_action === 'pause' || b.p_action === 'resume') j.active = b.p_action === 'resume'
    return route.fulfill({ json: read() })
  })
  return { calls, jobs }
}

// Layer 4 inbox kinds with their live choices and ranks (security.layer4_inbox_kinds_v1, 1 Nov 2026)
export const INBOX_KINDS = {
  course_link: { label: 'Course link', order: 1, choices: [{ key: 'use', label: 'Use the new page', input: 'url', returns: 'The new page becomes the course link' }, { key: 'enter', label: 'Enter another address', input: 'url', returns: 'That page is read' }, { key: 'keep', label: 'Keep the page we hold', returns: 'Closed; the course keeps its page' }] },
  website_needed: { label: 'Website needed', order: 3, choices: [{ key: 'cricos_only', label: 'CRICOS data only', returns: 'Kept with register data only' }, { key: 'website', label: 'Enter the website', input: 'url', returns: 'Onboarding starts' }, { key: 'archive', rank: 5, label: 'Archive the university', returns: 'Unpublished and hidden from the consumer API; reviewable on Archived' }] },
  counsellor_report: { label: 'Counsellor report', order: 12, choices: [{ key: 'report_fixed', label: 'Fixed', returns: 'Zoho shows Fixed' }, { key: 'report_not_changed', label: 'Not changed', returns: 'Zoho shows Not changed' }, { key: 'course', link: 'course', label: 'Open the course', returns: 'Correct the value on the course, then close the report here' }] },
  provider_departure: { label: 'Provider left the register', order: 14, choices: [{ key: 'reviewed', rank: 6, label: 'Still operating: keep it', returns: 'Closed' }, { key: 'closed', rank: 6, label: 'Closed: archive it', returns: 'Archived' }] },
  aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [{ key: 'approve', rank: 6, label: 'Approve all rows', returns: 'Every waiting row becomes active once the checks pass' }, { key: 'approve_except', rank: 6, input: 'rows', label: 'Approve except…', returns: 'The ticked rows stay unadmitted' }, { key: 'reject', rank: 6, label: 'Reject the read', returns: 'No row is admitted' }] },
}
export function inboxItems() {
  const at = (m) => new Date(Date.UTC(2026, 9, 20) + m * 60000).toISOString()
  return [
    { kind: 'course_link', ref: 'cl-0001', o: 1, provider_id: 'p1', provider: 'RMIT University', subject: 'Bachelor of Design', why: 'A new page was found', created_at: at(1), detail: { course_id: 'c1', before: 'https://www.rmit.edu.au/old', proposed: 'https://www.rmit.edu.au/study/bachelor-of-design' } },
    { kind: 'website_needed', ref: 'wn-0001', o: 3, provider_id: 'p2', provider: 'Example College', subject: 'Example College', why: 'No website held', created_at: at(2), detail: {} },
    { kind: 'counsellor_report', ref: 'cr-0001', o: 12, provider_id: 'p1', provider: 'RMIT University', subject: 'Tuition fee', why: 'Reported by a counsellor', created_at: at(3), detail: { course_id: 'c1', issue: 'wrong_value', field: 'tuition', suggested_value: 'AUD 41,000' } },
    { kind: 'provider_departure', ref: 'pd-0001', o: 14, provider_id: 'p3', provider: 'Gone Institute', subject: 'Gone Institute', why: 'Left CRICOS', created_at: at(4), detail: {} },
    { kind: 'aer_review', ref: '81d14690-0000-4000-8000-000000000001', o: 17, provider_id: 'p1', provider: 'RMIT University', subject: 'Entry matrix read', why: 'Rows waiting', created_at: at(5), detail: {} },
  ]
}

/** admin_layer4_inbox with the live floor (rank 3), the default choice rank (4) and the AER rule (6). */
export async function mockInbox(page, rank, { items = inboxItems(), kinds = INBOX_KINDS } = {}) {
  const calls = []
  let left = [...items]
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => {
    const b = route.request().postDataJSON(); calls.push(b)
    if (rank < 3) return refuse(route, LIVE.INBOX_FLOOR)
    const by_kind = Object.fromEntries(Object.keys(kinds).map(k => [k, { n: left.filter(x => x.kind === k).length }]))
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank, total: left.length, universities: 3, late: 0, by_kind } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'RMIT University', country: 'AU', by_kind: { course_link: 1 } }] } })
    if (b.p_action === 'items') { const a = b.p_args || {}; const l = left.filter(x => (!a.kind || x.kind === a.kind) && (!a.provider_id || x.provider_id === a.provider_id)); return route.fulfill({ json: { total: l.length, before: 0, items: l } }) }
    if (b.p_action === 'decided') return route.fulfill({ json: { items: [] } })
    if (b.p_action === 'decide') {
      const a = b.p_args || {}, c = (kinds[a.kind]?.choices || []).find(x => x.key === a.choice)
      if (!c) return refuse(route, `unknown choice ${a.choice} for ${a.kind}`, 'P0001')
      if (rank < Number(c.rank ?? 4)) return refuse(route, LIVE.CHOICE)
      left = left.filter(x => x.ref !== a.ref)
      const outcome = a.kind === 'aer_review' ? { class: 'admitted', rows: { active: 2 }, decision_id: 'dec00001-aaaa' } : { class: 'applied', decision_id: 'dec00002-bbbb' }
      return route.fulfill({ json: { ok: true, returns: c.returns, outcome, event_id: 41001 } })
    }
    return route.fulfill({ json: {} })
  })
  return calls
}

const aerRow = (o = {}) => ({ kind: 'matrix', id: 'm1', provider_id: 'p-rmit', provider_name: 'RMIT University (RMIT)', country: 'IN', country_name: 'India', level_label: 'Bachelor degrees', level_code: 'BA', level_name: 'Bachelor',
  matrix_kind: 'band_ladder', qualification: 'CBSE Year 12', band: '65%', min_grade: '75%', min_value: null, scale: 'percentage', conditions: { best_n: 4, subject_minimums: [], alternatives: [] }, audience: 'international',
  edition: '2027', intake_year: null, as_at: '2026-10-26', status: 'active', status_reason: null, quote: 'CBSE Year 12 | 65% | 75%', source_url: 'https://www.rmit.edu.au/india', evidence_id: 'ev1', version: 3, manual: false,
  run_id: 'r1', review_item_id: 'li1', review_status: 'approved', created_at: '2026-10-26T10:00:00Z', updated_at: '2026-10-27T10:00:00.123456+00:00', ...o })

/** public.admin_aer: reads from rank 1, corrections and withdrawal from rank 3, re-reading at rank 6 (live boundary). */
export async function mockAer(page, rank) {
  const calls = []
  let current = aerRow()
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer', async route => {
    const b = route.request().postDataJSON() || {}, a = b.p_args || {}
    calls.push({ action: b.p_action, args: a })
    const j = json => route.fulfill({ json })
    if (['update', 'add', 'lifecycle'].includes(b.p_action) && rank < 3) return refuse(route, LIVE.AER_CURATOR)
    if (b.p_action === 'reread' && rank < 6) return refuse(route, LIVE.AER_PA_ONLY)
    if (b.p_action === 'summary') return j({ matrix: { active: 1, proposed: 0, unverified: 0, inactive: 0, superseded: 0 }, course: { proposed: 0 }, sources: { total: 1, held: 0, fetch_failed: 0, reading: 0, read: 1 }, can_edit: rank >= 3, can_reread: rank >= 6 })
    if (b.p_action === 'options') return j({ providers: [{ id: 'p-rmit', name: 'RMIT University (RMIT)' }], countries: [{ code: 'IN', name: 'India' }], all_countries: [{ code: 'IN', name: 'India' }], levels: [{ code: 'BA', name: 'Bachelor' }], level_labels: [], bands: ['65%'], editions: ['2027'], intake_years: [], matrix_kinds: ['band_ladder'], requirement_kinds: [], scales: ['percentage'], audiences: ['international'], statuses: ['active', 'inactive'] })
    if (b.p_action === 'matrix_list') return j({ total: 1, offset: 0, page_size: 50, rows: [current] })
    if (b.p_action === 'row') return j({ ...current, evidence: { id: 'ev1', source_url: current.source_url, captured_at: '2026-10-26T09:00:00Z', mime: 'text/html', stored: true, content_hash: 'abc123' }, history: [], can_edit: rank >= 3 && current.status === 'active', can_restore: rank >= 3 && current.status === 'inactive' })
    if (b.p_action === 'sources_list') return j({ total: 1, can_reread: rank >= 6, ai_allowed: true, rows: [{ id: 's1', provider_id: 'p-rmit', provider_name: 'RMIT University (RMIT)', url: 'https://www.rmit.edu.au/india', type: 'Web page', status: 'read', read_via: 'direct', in_scope: true, hold_state: 'read', evidence_id: 'ev1', captured_at: '2026-10-26T09:00:00Z', run: { id: 'r1', state: 'done', attempts: 1 } }] })
    if (b.p_action === 'lifecycle') { current = { ...current, status: a.lifecycle === 'withdraw' ? 'inactive' : a.lifecycle === 'quarantine' ? 'unverified' : 'active', status_reason: a.reason, version: current.version + 1, updated_at: '2026-11-01T09:30:00+00:00' }; return j({ ok: true, row: current, changed: 1 }) }
    return j({})
  })
  return calls
}
