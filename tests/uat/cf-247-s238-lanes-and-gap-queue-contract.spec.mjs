// Guards: Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent C and §6 (stored-evidence work never held by paid acquisition; bounded resumable gap queue; honest outcomes)
// The behaviour runs on isolated fixtures by tests/fixtures/lanes-gap-queue/run.sh (scratch PostgreSQL; the live definitions loaded from their
// live text and checked against the live md5s; the defects reproduced on them; the migration applied twice; every case asserted; the tick as
// branch cf247-course-description-reader leaves it also edited). This spec holds the contract of the change and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261103160000_cf247_lanes_and_gap_queue.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/lanes-gap-queue'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']]', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf('$function$;', a)) }

const MD5 = {
  'public.svc_worker_report_v1(text,integer,integer,jsonb,text)': [['6f3b816265f1a517b9d79140041669bb'], ['b110a648a8149eede42cbc69cce43a77']],
  'security.field_gap_queue_tick_v1()': [['d909e54d6b6de0f8d2893fbb2d8553bd', '387f8edbe3363ea52317e024d96f2369'], ['200f3210c75a71e6e5f5f0eceb37ea66', '9bb80b419ee26a049b99a35fb278e272']],
  'public.svc_scholarship_ai_next(integer)': [['ddef1e3dd794e26f3588f73e9d51e6b5'], ['18e76dbc9984be55370434ca27066c7b']],
  'public.svc_scholarship_recheck_next(integer)': [['f35fa04f98a32d0ca4eb4064ea7db6eb'], ['ccfaf9a9c6bbba4ce5fde64a3d7738af']],
  'public.admin_pipeline_yield(jsonb)': [['a9d64bbca63b5e1c587edabf4e1fef59'], ['a38814324515b163a34129b7a9d01dbd']],
}

test('five live definitions are edited only from their live md5 (the tick also from the course-description branch) and checked after', () => {
  for (const [sig, [b, a]] of Object.entries(MD5)) {
    const e = edit(sig)
    expect(e).toContain(`array[${b.map((x) => `'${x}'`).join(', ')}]`)
    expect(e.replace(/\s+/g, ' ')).toContain(`array[${a.map((x) => `'${x}'`).join(', ')}]`)
    b.forEach((x, i) => expect(m).toContain(`${x} -> ${a[i]}`))
    for (const x of [...b, ...a]) expect(run).toContain(x)
  }
  expect(m).toContain("if k is null then raise exception 'live % differs from the definitions this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).toContain("raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_afters[k];")
  // the definitions the new code calls are checked, not edited
  for (const x of ['e979d2e3d7319d845a5149e40abe6987', '8c1419332ff503abd69539ccbad1121d', '8b256a6f7f9a9350927b4773c8a80304', '60c782e5aec7eb218c1149a3ad85dde2']) expect(m).toContain(`'${x}'`)
  expect(m).not.toMatch(/edit_once\('security\.(worker_call_outcome_v1|pipeline_yield_v1|fc_budget_left_v1)/)
  expect(m).not.toContain("('firecrawl', '")
})

test('honest outcomes: lane outcome and hold reason beside the unchanged outcome; counts read only when they are numbers', () => {
  expect(m).toContain("check (lane_outcome in ('done', 'idle', 'budget_held', 'source_limit', 'failed', 'switched_off'))")
  const rep = after(edit('public.svc_worker_report_v1(text,integer,integer,jsonb,text)'))
  expect(rep).toContain("security.jsonb_int_v1(p_body->'applied')")
  expect(rep).not.toMatch(/->>'(applied|done|failed)', ''\)::int/)
  expect(rep).toContain('security.worker_lane_outcome_v1(left(coalesce(p_mode, \'\'), 60), y.outcome, p_body)')
  const o = fn('security.worker_lane_outcome_v1')
  expect(o).toContain("if v_lane = 'paid_acquisition' then")
  expect(o).toContain("v_hold := security.lane_paid_hold_v1(v_purpose);")
  expect(o).toContain("'source_limit', 'today''s course-page search cap (search.daily_picked_cap) is reached'")
  const h = fn('security.lane_paid_hold_v1')
  expect(h).toContain('security.fc_month_refusal_v1(1)')
  expect(h).toContain('security.fc_budget_left_v1(p_purpose) < 1')
  expect(before).toContain('before D1 reproduced')
  for (const k of ['B1 ok', 'B2 ok', 'B3-B8 ok']) expect(fixtures).toContain(k)
})

test('stored copies first while the scholarship Firecrawl lane is held; the usual order otherwise; nothing raised', () => {
  for (const sig of ['public.svc_scholarship_ai_next(integer)', 'public.svc_scholarship_recheck_next(integer)']) {
    expect(after(edit(sig))).toContain("v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;")
  }
  expect(after(edit('public.svc_scholarship_ai_next(integer)'))).toContain('and (v_paid or security.scholarship_ai_has_copy_v1(q.id))')
  expect(after(edit('public.svc_scholarship_recheck_next(integer)'))).toContain('and (v_paid or r.storage_path is not null)')
  expect(m).toMatch(/'lanes\.stored_first_on'[\s\S]*?to_jsonb\(1\), 0, 1, 'on\/off'/)
  for (const k of ['before D2 reproduced', 'before D3 reproduced']) expect(before).toContain(k)
  for (const k of ['C1 ok', 'C2 ok', 'C3 ok', 'C4 ok']) expect(fixtures).toContain(k)
})

test('the gap queue: bounded slices from a durable checkpoint, the tick edited once, every run recorded with an honest outcome', () => {
  const tick = after(edit('security.field_gap_queue_tick_v1()'))
  expect(tick).toContain("v_x := v_x || jsonb_build_object('scan', security.field_gap_scan_v1(v_fields, v_days, v_cap));")
  { const t = m.slice(m.indexOf("edit_once('security.field_gap_queue_tick_v1()'")); expect(t.indexOf('$n$]], array[1]);')).toBeGreaterThan(0); expect(t.indexOf('$n$]], array[1]);')).toBeLessThan(t.indexOf('create or replace function security.field_gap_queue_run_v1')) }
  const scan = fn('security.field_gap_scan_v1')
  expect(scan).toContain("security.pipeline_num_v1('gaps.scan_courses_per_slice', 2000)")
  expect(scan).toContain("security.pipeline_num_v1('gaps.scan_seconds', 20)")
  expect(scan).toContain('where c.lifecycle_status = \'active\' and (v_last is null or c.id > v_last) order by c.id limit v_slice')
  expect(scan).toContain('where e.course_id = m.course_id and e.field = m.field and e.provider_id = m.provider_id order by e.id desc limit 1')
  expect(scan).not.toContain('distinct on')
  expect(scan).toContain('update pipeline.field_gap_queue_checkpoint set')
  const wrap = fn('security.field_gap_queue_run_v1')
  expect(wrap).toContain("when v_scan is not null and not coalesce((v_scan->>'cycle_complete')::boolean, true) then 'held'")
  expect(wrap).toContain('insert into pipeline.field_gap_queue_runs')
  expect(m).toContain("('field-gap-queue', $c$select security.field_gap_queue_tick_v1()$c$, $c$select security.field_gap_queue_run_v1()$c$)")
  expect(m).toContain("check (outcome in ('done', 'idle', 'held', 'switched_off'))")
  for (const k of ['A1 ok', 'A2 ok', 'A3 ok', 'A4 ok', 'A5 ok', 'A6 ok', 'A7 ok']) expect(fixtures).toContain(k)
  expect(run).toContain('enrich_course_text_gaps_v1')
})

test('switched-off lanes are not called; skipping held paid lanes ships off; jobs keep schedule and state', () => {
  const g = fn('security.worker_lane_call_v1')
  expect(g).toContain("if p_mode = 'link_search' and not coalesce((select s.enabled from pipeline.course_link_search_settings s where s.id = 1), false) then return false; end if;")
  expect(g).toContain("if security.pipeline_num_v1('lanes.skip_held_paid_calls', 0) < 1 then return true; end if;")
  expect(m).toMatch(/'lanes\.skip_held_paid_calls'[\s\S]*?to_jsonb\(0\), 0, 1, 'on\/off'/)
  for (const [job, mode] of [['course-link-search-worker', 'link_search'], ['central-find', 'central_find'], ['coverage-discover', 'discover'], ['coverage-discover-2', 'discover'], ['scholarship-listing', 'scholarship_listing'], ['scholarship-read', 'scholarship_read']]) {
    expect(m).toMatch(new RegExp(`\\('${job}', \\$c\\$[^$]+\\$c\\$,\\s*\\$c\\$[^$]+ where security\\.worker_lane_call_v1\\('${mode}'\\)\\$c\\$\\)`))
  }
  expect(m).toContain("if v_cmd <> r.old_cmd then raise exception 'lanes: job % runs a command this change was not written against: %', r.jobname, v_cmd; end if;")
  expect(m).not.toMatch(/cron\.(schedule|alter_job\([^)]*active)/)
  expect(fixtures).toContain('D ok')
})

test('lane status: five lanes, each with eligible work, processed, failed, held and cost; read-only; on Pipeline yield', () => {
  const s = fn('security.lane_status_v1')
  expect(s).toContain('language plpgsql stable security definer')
  expect(s).not.toMatch(/\b(insert|update|delete)\s+(into\s+)?pipeline\./)
  for (const lane of ['stored_evidence', 'paid_acquisition', 'ai_extraction', 'layer4_admission', 'gap_queue']) expect(s).toContain(`'${lane}'`)
  expect(after(edit('public.admin_pipeline_yield(jsonb)'))).toContain("|| jsonb_build_object('lane_status', security.lane_status_v1());")
  expect(fixtures).toContain('E ok')
})

test('Platform health › Integration queue › Pipeline yield shows each lane with its work, holds and cost', async ({ page }) => {
  await mockAdmin(page, { rank: 5 })
  await page.route('**/rest/v1/rpc/admin_integration_queue', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ mode: { mode: 1, set_by: 'x', set_at: '2026-11-02T06:00:00Z', reason: 'r' }, by_status: {}, by_severity: {}, by_workstream: {}, issues: [] }) }))
  const lane = (o) => ({ eligible: {}, processed: 0, failed: 0, held: {}, live_hold: null, cost: { firecrawl_credits_today: 0, ai_usd_today: 0 }, ...o })
  await page.route('**/rest/v1/rpc/admin_pipeline_yield', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ window_hours: 24, lanes: [], lane_status: { lanes: [
    lane({ lane: 'stored_evidence', label: 'Stored evidence and direct reads', eligible: { course_pages_due: 12 }, processed: 40 }),
    lane({ lane: 'paid_acquisition', label: 'New paid pages (Firecrawl)', held: { budget_held: 60 }, live_hold: { sch_scrape: 'budget_held: no room left in today\'s Firecrawl share for scholarships' }, cost: { firecrawl_credits_today: 120 } }),
    lane({ lane: 'gap_queue', label: 'Standing gap queue', last_run: { at: '2026-11-03T00:23:00Z', outcome: 'held', hold_reason: 'scan_continues', items: 0 } })] } }) }))
  await page.goto('/#platform-health?tab=integration')
  const t = page.locator('[data-lane-status]')
  await expect(t).toContainText('Lanes now: work, holds and cost, each lane on its own')
  await expect(t.locator('[data-lane-row="eligible"] [data-lane="stored_evidence"]')).toHaveText('12 course pages due')
  await expect(t.locator('[data-lane-row="held"] [data-lane="paid_acquisition"]')).toHaveText('60 budget held')
  await expect(t.locator('[data-lane-row="live_hold"] [data-lane="paid_acquisition"]')).toContainText('no room left in today\'s Firecrawl share for scholarships')
  await expect(t.locator('[data-lane-row="cost"] [data-lane="paid_acquisition"]')).toHaveText('120 firecrawl credits today')
  await expect(t.locator('[data-lane-row="last_run"] [data-lane="gap_queue"]')).toContainText('held (scan continues) · 0 items')
})
