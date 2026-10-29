// Guards: CF-247 decision W30 (enrichment reliability incident, hourly health report 29 Oct 2026 23:20 AEDT): the course source finder's candidate scan is worked out once per set (same candidates, same order) so it stays inside the 8-second limit; a course page is claimed by exactly one read call (lease re-checked on the locked row); an onboarding step tracks its own university's job; adapter capture and proposal calls are counted in the worker ledger with explicit failures; a slow course-list read records every list it took; md5-guarded edits only, no new status, setting, job or binding, consumer API untouched, nothing dropped
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261030010000_cf247_enrich_reliability.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const fx = (n) => JSON.parse(fs.readFileSync(`tests/uat/fixtures/cf-247-s172/${n}.json`, 'utf8'))

// The live ledger rule (public.svc_worker_report_v1 md5 11e82a3abcefc6ff7c16541a6d71f9cf, security.worker_call_work_v1 md5
// 4bfdbbccdca1cd3481fd7011d38154af): items are the sum of these keys, failed adds 1 for an HTTP error or ok:false.
const WORK_KEYS = ['providers', 'items', 'rows', 'found', 'read', 'searched', 'pages', 'picked', 'discover', 'applied', 'done', 'checked']
export function ledger(status, body) {
  const items = Object.entries(body).filter(([k]) => WORK_KEYS.includes(k)).reduce((a, [, v]) => a + (typeof v === 'number' ? v : Array.isArray(v) ? v.length : 0), 0)
  const failed = (Number(body.failed) || Number(body.tally?.failed) || 0) + (Number(body.tally?.fetch_failed) || 0) + (Number(body.tally?.scrape_failed) || 0)
    + (status >= 400 || body.ok === false ? 1 : 0)
  const ok = Math.max(0, body.done ?? body.applied ?? items - failed)
  return { items, ok, failed }
}
const editOf = (sig) => {
  const i = code.indexOf(`select pg_temp.edit_n('${sig}'`)
  expect(i, sig).toBeGreaterThan(-1)
  const end = code.indexOf('\n\n', i)
  return code.slice(i, end === -1 ? undefined : end)
}

test('total source-finder failure is a database time-out in svc_source_find_next, not the sites or Firecrawl', () => {
  const f = fx('source-finder-total-failure')
  for (const c of f.calls) {
    expect(c.status).toBe(500)
    expect(c.body.error).toBe('svc_source_find_next: canceling statement due to statement timeout')
    expect(ledger(c.status, c.body)).toEqual({ items: 0, ok: 0, failed: 1 })
  }
  expect(f.scan_before.ms_idle * 2.9).toBeGreaterThan(f.statement_timeout_ms) // under load the old scan crossed the limit
  expect(f.scan_after.candidates).toBe(f.scan_before.candidates)
  expect(f.scan_after.same_order).toBe(true)
  expect(f.scan_after.buffers * 20).toBeLessThan(f.scan_before.buffers)
})

test('the source finder scan is worked out once per set; picking, lease, shape and settings unchanged', () => {
  const e = editOf('public.svc_source_find_next(integer,uuid[])')
  expect(e).toContain("'57a32d94f5c70321a207a39683260a64'")
  const added = e.split('$n$')[1]
  for (const cte of ['with excl as materialized (', 'prov as materialized (', 'cand as materialized (']) expect(added).toContain(cte)
  expect(added).toContain('group by c.provider_id)')
  expect(added).not.toContain('security.coverage_country(p.id)') // no per-provider country call
  expect(added).not.toMatch(/\(select count\(\*\) from catalogue\.courses c where c\.provider_id = p\.id/) // no per-provider counts
  expect(added).toContain('select c.id from cand c') // the rest of the statement (eligibility, order, cap, lease) is kept as it is live
  expect(e).toContain('order by (c.active - c.paged) desc, c.all_courses desc, c.id') // a stable tie-break, same order otherwise
  expect(e).toContain('array[1, 1]')
  expect(code).not.toMatch(/source_find\.(min_links|min_recall|max_files|max_locs|max_list_tries)'?,\s*\d/) // settings untouched here
})

test('one claim per course page: the lease is re-checked on the locked row', () => {
  const e = editOf('public.svc_coverage_read_next(integer)')
  expect(e).toContain("'a8bfed7cfbf67741b8891ffadadf73e5'")
  expect(e).toContain("from pick where p.course_id=pick.course_id and coalesce(p.leased_until,'-infinity')<now()")
  expect(code).toContain("!~ 'pick\\.course_id and coalesce\\(p\\.leased_until'") // post-check
})

test('an onboarding step tracks its own university\'s job', () => {
  const e = editOf('security.provider_onboarding_job_v1(text,uuid,jsonb)')
  expect(e).toContain("'ab742e1eb06da68fa0d795229e505737'")
  expect(e).toContain("and (j.scope = p_provider::text or j.args->>'provider_id' = p_provider::text or j.args->'provider_ids' ? p_provider::text)")
})

test('adapter capture failure: a boot failure is named, a working capture is no longer read as 0 of 0', () => {
  const f = fx('adapter-capture-failure')
  expect(f.not_started.body.code).toBe('BOOT_ERROR')
  expect(f.not_started.ledger_row).toBe(false) // the worker never ran: no ledger row, no credits, the draft waits in capturing
  expect(f.not_started.draft.credits).toBe(0)
  const old = f.worked_but_read_as_nothing[0]
  expect(ledger(old.status, old.body_v0_53_0)).toEqual(old.ledger_v0_53_0)
  // v0.53.1 response shapes, taken from the worker source
  expect(worker).toMatch(/(const WORKER = "coverage-sweep-worker-v0\.53\.1"; |\/\/ was v0\.53\.1 )\/\/ v0\.53\.1 \(30 Oct 2026, CF-247 decision W30/) // v0.54.0 (W30 with W32) keeps the v0.53.1 note
  expect(worker).toContain('const capFailed = caps.filter((x) => x.error).length;')
  expect(worker).toContain('return j({ ok: true, mode, items: caps.length, failed: capFailed, captured: caps.length - capFailed, worker: WORKER });')
  expect(worker).toContain('return j({ ok: true, mode, items: 1, cost, dropped: dropped.length, worker: WORKER });')
  expect(ledger(200, { ok: true, mode: 'adapter_capture', items: 3, failed: 0, captured: 3 })).toEqual({ items: 3, ok: 3, failed: 0 })
  expect(ledger(200, f.partly_failed_v0_53_1.body)).toEqual({ items: 3, ok: 2, failed: 1 }) // a partial capture is not complete
  expect(ledger(200, { ok: true, mode: 'adapter_capture', items: 2, failed: 2, captured: 0 })).toEqual({ items: 2, ok: 0, failed: 2 })
  // the capture's Firecrawl spend is still recorded per page before the call, as before
  const cap = worker.slice(worker.indexOf('if (mode === "adapter_capture") {'), worker.indexOf('if (mode === "adapter_propose") {'))
  expect(cap.indexOf('svc_coverage_usage')).toBeGreaterThan(-1)
  expect(cap).toContain('outcome: rec.success ? "captured" : "fc_error"')
})

test('slow course-list reads: the 110-second budget plus one in-flight scrape; every list taken is recorded', () => {
  const f = fx('slow-list-reads')
  for (const c of f.calls) {
    expect(c.read).toBe(c.lists) // nothing left half done, even when pg_net stopped waiting
    expect(c.ms).toBeLessThan(f.worker_budget_ms + 60000 + 5000)
  }
  expect(f.calls.filter((c) => c.pg_net.timed_out)).toHaveLength(1)
  const clr = worker.slice(worker.indexOf('if (mode === "course_list_read") {'), worker.indexOf('if (mode === "source_find") {'))
  // a list not started inside the budget goes back as due (never recorded as read), and every path records its list
  expect(clr).toContain('if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_course_list_record", { p_id: it.id, p_status: "due"')
  expect(clr).toContain('signal: AbortSignal.timeout(60000)')
})

test('md5-guarded edits only; no new status, setting, job or binding; consumer API untouched; nothing dropped', () => {
  expect(code).toContain('if md5(v_def) <> p_md5 then raise exception')
  expect(code.match(/select pg_temp\.edit_n\('/g)).toHaveLength(3)
  expect(m).toMatch(/^-- Replaces: public\.svc_source_find_next, public\.svc_coverage_read_next, security\.provider_onboarding_job_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(code).not.toMatch(/platform_toolset_settings|automation_catalogue|cron\.schedule|create table/i)
  expect(code).not.toMatch(/course_link_bind|manual_locks|layer4_review_items|status = '[a-z_]+'\s*,/)
})
