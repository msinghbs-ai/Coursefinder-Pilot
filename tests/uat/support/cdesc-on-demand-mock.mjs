// Mocked server for the Fill / Recheck description screens (CF-247 F-CDESC.06). The shapes are the ones public.admin_course_description_state_v1 and
// public.admin_enrich_fields('preview' | 'start' | 'verify' | 'description_tasks') return (proved on isolated PostgreSQL by tests/fixtures/cdesc-on-demand).
// Nothing reaches a real backend. Every call is recorded in `calls`.
const BASE = 'https://example.supabase.co/rest/v1/rpc/'
const INFO = {
  no_source: { label: 'No stored course page that is proved to be this course', next: 'Wait for the course page to be found and read, or add a course link. Nothing is read from a generic page.' },
  recent_attempt: { label: 'Tried recently', next: 'The standing queue tries again on its own date; use Recheck description to read it now.' },
  nothing_to_recheck: { label: 'Not tried yet', next: 'Use Fill description.' },
  already_has_description: { label: 'Already has a description', next: 'Nothing to fill.' },
  locked: { label: 'Locked by hand', next: 'A person removes the lock first; a read never overwrites a hand-held value.' },
}
// state by position in the page: the same course always gets the same state, so a spec can name it
export const ORDER = ['source_ready', 'missing', 'held', 'machine_admitted', 'human_decision', 'ai_read']
function row(id, i, force = null) {
  const state = force || ORDER[i % ORDER.length]
  const has = ['machine_admitted', 'human_decision'].includes(state)
  const fill_block = has ? 'already_has_description' : state === 'missing' ? 'no_source' : state === 'held' || state === 'failed' ? 'recent_attempt' : state === 'ai_read' ? 'waiting_for_person' : null
  const recheck_block = has ? 'already_has_description' : state === 'missing' ? 'no_source' : state === 'source_ready' ? 'nothing_to_recheck' : state === 'ai_read' ? 'waiting_for_person' : null
  return { course_id: id, provider_id: 'p-1', title: `Course ${i + 1}`, provider: 'RMIT University', active: true, has_description: has, state, source_ready: state !== 'missing', source_reason: state === 'missing' ? 'no_page' : null,
    source_url: state === 'missing' ? null : `https://example.edu.au/course/${i + 1}`, evidence_id: state === 'missing' ? null : '11111111-2222-4333-8444-555555555555', page_read_at: '2026-11-01T01:00:00Z', page_next_read_at: null,
    last_item_id: state === 'held' ? 7 : state === 'failed' ? 8 : null, last_state: state === 'held' ? 'skipped' : state === 'failed' ? 'failed' : null, last_reason: state === 'held' ? 'held: the words copy the page' : state === 'failed' ? 'the page timed out' : null, last_attempt_at: state === 'held' || state === 'failed' ? '2026-11-05T01:00:00Z' : null,
    last_job_id: state === 'held' || state === 'failed' ? 'abcdef12-0000-4000-8000-000000000001' : null,
    held_kind: state === 'held' ? 'check' : null, locked: false, hidden: false, waiting_for_person: state === 'ai_read', rejected_same_evidence: false, machine_admitted: state === 'machine_admitted' ? true : null,
    human_decision: state === 'human_decision', next_retry_at: state === 'held' ? '2026-12-26T01:00:00Z' : null, fill_block, recheck_block,
    fill_info: INFO[fill_block] || (fill_block ? { label: fill_block, next: '' } : null), recheck_info: INFO[recheck_block] || (recheck_block ? { label: recheck_block, next: '' } : null) }
}
export async function mockOnDemand(page, { cap = 20, startError = null, verify = null, forceState = null, withdraw = null, itemOverride } = {}) {
  const calls = []
  const index = new Map()
  const idx = (id) => { if (!index.has(id)) index.set(id, index.size); return index.get(id) }
  // public.admin_course_description_item_v1: the latest description item as stored. `itemOverride` replaces the item (for example attempts 0: never tried)
  await page.route(BASE + 'admin_course_description_item_v1', async (route) => {
    const b = route.request().postDataJSON() || {}; calls.push({ name: 'item', ...b })
    const ids = b.p_course_ids || []
    return route.fulfill({ json: { read_at: '2026-11-10T01:00:00Z', courses: ids.map((id) => {
      const r = row(id, idx(id), forceState)
      const item = itemOverride !== undefined ? itemOverride : r.last_item_id ? { id: r.last_item_id, state: r.last_state, reason: r.last_reason, attempts: r.last_state === 'failed' ? 3 : 1, source: 'ai_stored', evidence_id: r.evidence_id, storage_path: 'evidence/ab12cd34/page.html', reading_chars: r.last_state === 'skipped' ? 812 : 0, at: r.last_attempt_at } : null
      return { course_id: id, field: 'description', catalogue_chars: r.has_description ? 420 : 0, item }
    }) } })
  })
  await page.route(BASE + 'admin_course_description_state_v1', async (route) => {
    const b = route.request().postDataJSON() || {}; calls.push({ name: 'state', ...b })
    const ids = b.p_course_ids || []
    return route.fulfill({ json: { read_at: '2026-11-10T01:00:00Z', machine_ledger: true, recheck_days: 60, courses_per_request: cap, courses: ids.map((id, i) => row(id, idx(id), forceState)) } })
  })
  // public.admin_course_description_machine_withdraw_v1(p_course, p_reason): `withdraw` is the answer ({ ok: true } by default; { ok: false, rule, reason } is a refusal) or { status, message } for an error
  await page.route(BASE + 'admin_course_description_machine_withdraw_v1', async (route) => {
    const b = route.request().postDataJSON() || {}; calls.push({ name: 'withdraw', ...b })
    if (withdraw?.status) return route.fulfill({ status: withdraw.status, json: { code: '42501', message: withdraw.message } })
    return route.fulfill({ json: withdraw || { ok: true, course_id: b.p_course, admission_id: 'a1', restored: null, withdrawn_by: 'u1' } })
  })
  await page.route(BASE + 'admin_enrich_fields', async (route) => {
    const b = route.request().postDataJSON() || {}; const a = b.p_args || {}
    calls.push({ name: b.p_action, ...a })
    const mode = a.mode
    if (b.p_action === 'preview' || b.p_action === 'start') {
      if (b.p_action === 'start' && startError) return route.fulfill({ status: 400, json: { code: 'P0001', message: startError } })
      let list
      if (a.course_ids) list = a.course_ids.map((id) => row(id, idx(id)))
      else list = ORDER.map((_, i) => row(`u-${i}`, i))
      list = list.map((c) => { const block = mode === 'recheck' ? c.recheck_block : c.fill_block; return { ...c, block, block_info: block ? (INFO[block] || { label: block, next: '' }) : null, will_queue: !block } })
      const blocked = {}; for (const c of list) if (c.block) blocked[c.block] = (blocked[c.block] || 0) + 1
      const n = list.filter((c) => c.will_queue).length
      if (b.p_action === 'preview') return route.fulfill({ json: { mode, scope: a.course_ids ? 'courses' : 'university', selected: a.course_ids ? a.course_ids.length : null, missing: [], total: list.length, eligible: n, to_queue: n, left_for_later: 0, blocked,
        blocked_info: Object.fromEntries(Object.keys(blocked).map((k) => [k, INFO[k] || { label: k, next: '' }])), limit: { courses_per_request: cap, room_today: 480, items_per_day: 500 },
        estimate: { items: n, usd_per_item: 0.0031, usd: Number((n * 0.0031).toFixed(4)), scraper_credits: 0 }, courses: list } })
      return route.fulfill({ json: { job_id: 'abcdef12-0000-4000-8000-000000000001', items: n, repeat: false, mode, scope: a.course_ids ? 'courses' : 'university', blocked, idempotency_key: a.idempotency_key } })
    }
    if (b.p_action === 'verify') return route.fulfill({ json: verify || { verified_at: '2026-11-10T01:00:00Z', courses: (a.course_ids || []).map((id) => ({ course_id: id, stable_key: 'sk', country: 'AU', catalogue: { state: 'present', chars: 412 },
      website: { state: 'matched', note: 'The Website API returns the same words as the catalogue.' }, zoho: { state: 'not_applicable', note: 'The country is not synced to Zoho (zoho.sync_countries).' },
      http: { state: 'not_checked', note: 'The database cannot call the website.' } })), missing: [], summary: {} } })
    if (b.p_action === 'description_tasks') return route.fulfill({ json: { tasks: [{ id: 'abcdef12-0000-4000-8000-000000000001', title: 'Recheck description · 2 course(s)', state: 'running', progress: { done: 1, total: 2 }, reason: 'Checking the new pages', created_at: '2026-11-10T01:00:00Z', finished_at: null,
      mode: 'recheck', scope: 'courses', by_state: { filled: 1, queued: 1 }, described_now: 1 }] } })
    return route.fulfill({ json: {} })
  })
  return calls
}
