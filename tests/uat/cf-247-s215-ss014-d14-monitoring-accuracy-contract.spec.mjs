// Guards: SS-014 D14 and monitoring accuracy (Platform Admin 2 Nov 2026 07:41)
// "Fix the existing logic so the current in-flight attempt does not prevent an eligible idle pause" (§4), and the P2 monitoring findings of
// 2 Nov (the 03:00 false critical counted hidden-provider pages the reader skips; the watchdog called a configured daily cap "stuck").
// The idle guard counts only calls old enough to have answered (flag.answer_wait_seconds); the health check's coverage page reading rule
// and the watchdog count exactly what the readers take; a configured cap is "Paused: daily cap", not stuck. The behaviour is run on
// isolated fixtures by tests/fixtures/ss014-d14-monitoring/run.sh (scratch PostgreSQL; the edited functions are rebuilt from this
// repository's migrations and the readers from their live text, all checked against the live md5s; each defect is reproduced first on the
// live definitions). This spec holds the contract and the Work queues screen. G2, G3 and housekeeping are guarded centrally (s32, s57, s42).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261102040000_cf247_ss014_d14_monitoring_accuracy.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/ss014-d14-monitoring'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const fixtures = fx('fixtures.sql'), before = fx('fixtures-before.sql'), run = fx('run.sh')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('\n$$;', a)) }

const EDITS = [
  ['security.flag_jobs_v1()', 'a7a7427b4caeea2fa62d017695c3b54e', '2421dd1c132bd6460aa12c8dbdce3fa6'],
  ['security.queue_watch_run_v1(boolean)', '59c67cf1b496ab43c11c82491962b418', '5735193b0d93f4764502504617c55687'],
  ['security.platform_health_check_v1(boolean)', '964db44f6fbcf2cf4c6e6463f4860b40', '25ff04344e2a940a3132e7ba709f98aa'],
]

test('three md5-guarded edits checked after; the readers are guarded unchanged; the fixture run checks the same md5s', () => {
  const calls = [...m.matchAll(/select pg_temp\.edit_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(calls).toEqual(EDITS)
  expect(code).toContain("if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then")
  expect(code).toContain("if md5(v_def) = p_after then return p_sig || ': already applied'; end if;")
  expect(code).toContain("md5(pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure)) <> '2ac1114dd4a5da99d8ddb742f7d0c1be'")
  expect(code).toContain("md5(pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure)) <> '00f7add9839d659f7dfc7efe6bd82216'")
  expect(run).toContain('"a7a7427b4caeea2fa62d017695c3b54e 59c67cf1b496ab43c11c82491962b418 2ac1114dd4a5da99d8ddb742f7d0c1be 00f7add9839d659f7dfc7efe6bd82216"')
  expect(run).toContain('"2421dd1c132bd6460aa12c8dbdce3fa6 5735193b0d93f4764502504617c55687 2ac1114dd4a5da99d8ddb742f7d0c1be 00f7add9839d659f7dfc7efe6bd82216"')
  expect(run).toContain('"5b390eac539668d07ac8d539c26519c7 8843993088ad60515f7fbd72c6906b2b e52e47dcc4c92a212688eab5c63fc049"')  // live health check rule lines
  expect(run).toContain("grep -c 'already applied' | grep -qx 3")
  expect(m).toMatch(/^-- Replaces: security\.flag_jobs_v1, security\.queue_watch_run_v1, security\.platform_health_check_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})

test('D14: only calls old enough to have answered are counted; the window is a setting; nothing else in the guard changes', () => {
  expect(m).toContain("v_answered timestamptz := now() - make_interval(secs => security.pipeline_num_v1('flag.answer_wait_seconds', 120));")
  expect(m).toContain("and l2.created_at > coalesce(f.released_at, '-infinity') and l2.created_at <= v_answered")
  expect(m).toContain("('pipeline', 'flag.answer_wait_seconds', 'Idle guard: a run counts once it is this old',")
  expect(m).toContain("'number', to_jsonb(120), 10, 600, 'seconds', 786, 'Flags', 'security.flag_jobs_v1',")
  // the edit adds the window only: two pairs, each applied once
  const call = m.slice(m.indexOf("select pg_temp.edit_once('security.flag_jobs_v1()'"), m.indexOf("array[1, 1]);", m.indexOf("select pg_temp.edit_once('security.flag_jobs_v1()'")))
  expect([...call.matchAll(/\$o\$/g)].length).toBe(4)
})

test('D14 fixtures: the race reproduced first; pause after N; no permanent pause; no duplicate processing; no AI read; reporting', () => {
  expect(before).toContain("'before: the live guard does not pause (it sees 29 of 30)'")
  expect(before).toContain("raise notice 'PASS before: D14 race reproduced (29 of 30, never paused)';")
  for (const p of ['PASS D14 race: pauses with the call under way', 'PASS pause after N empty answered runs',
    'PASS no pause with work, an unanswered or failed run, or a never-paused mode', 'PASS no permanent pause (re-arm on waiting work)',
    'PASS no permanent pause (capped trial) and the back-off steps on', 'PASS no duplicate processing, no AI read by the guard',
    'PASS reporting: paused runs are paused, failures stay failures']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(fixtures).toContain("'the AI queue is untouched (the lease of the call under way is kept)'")
  expect(fixtures).toContain("'the guard makes no call (no AI read)'")
  expect(fixtures).toContain("'runs before the release are not counted again'")
  expect(fixtures).toContain("security.cron_run_outcome_v1('coverage-ai-match', 'failed', 'job canceled', v_at + interval '2 seconds') = 'paused'")
})

test('monitoring: the read count is the reader’s own conditions, used by the health check and the watchdog', () => {
  expect(fn('security.coverage_read_eligible_v1')).toContain("where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3\n     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)")
  // the post-check finds the same conditions in the live reader
  expect(code).toContain("if position($p$where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3$p$ in v_reader) = 0")
  expect(m).toContain("select greatest(max(read_at), (select min(e.due_at) from security.coverage_read_eligible_v1() e)) into v_ts from pipeline.coverage_course_pages;$n$]")
  expect(m).toContain("$q$select count(*) from security.coverage_read_eligible_v1()$q$);  -- SS-014 P2 (2 Nov 2026): the same pages the reader takes$n$]")
  expect(code).toContain("update pipeline.queue_watch set pending_sql = v_read where key = 'course_page_read';")
  expect(code).toContain("not in ('faa7842a12313124d61630df63e645b5', md5(v_read))")
})

test('monitoring: the search count is the picker’s conditions; a configured cap is "Paused: daily cap", no alert, no issue', () => {
  const e = fn('security.course_link_search_eligible_v1')
  for (const c of ["and security.search_stop_gate_v1(s.provider_id, s.course_id, pv.stopped) is null", "and (pv.focus or s.requested_at is not null)",
    "else security.site_list_match_done_v1(s.course_id, s.provider_id) end", "where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)",
    "and not security.third_party_host_v1('https://' || rc.search_domain)", "sk.key = 'search.skip_providers' and sk.value ? px.stable_key"]) expect(e).toContain(c)
  expect(e).not.toContain('daily_picked_cap')
  const cap = m.slice(m.indexOf('create or replace function security.course_link_search_cap_reason_v1('), m.indexOf('end $$;', m.indexOf('create or replace function security.course_link_search_cap_reason_v1(')))
  expect(cap).toContain("security.pipeline_num_v1('search.daily_picked_cap', 100)::int")
  expect(cap).toContain("return format('Paused: daily cap. %s of %s courses picked today (setting search.daily_picked_cap, counted per UTC day); picking resumes at %s'")
  expect(cap).toContain('security.link_search_person_task_v1(e.provider_id, e.course_id)')
  expect(m).toContain("alter table pipeline.queue_watch add column if not exists cap_sql text;")
  expect(m).toContain("elsif v_pending > 0 and v_cap is not null then\n        v_state := 'capped'; v_reason := v_cap;")
  expect(m).toContain("'paused_daily_cap', count(*) filter (where s.state = 'capped')")
  expect(code).toContain("update pipeline.queue_watch set pending_sql = v_search, cap_sql = v_cap where key = 'course_page_search';")
})

test('monitoring fixtures: the defects first, then counts equal to what the readers take', () => {
  for (const p of ['PASS before: waiting counts include pages and searches the readers skip', 'PASS before: a configured cap pause is reported as stuck']) expect(before).toContain(`raise notice '${p}';`)
  for (const p of ['PASS read counts: health = watchdog = eligible (31)', 'PASS read: the reader takes exactly what is counted; hidden pages alone are not a stall',
    'PASS search counts and the daily cap reported as a pause', 'PASS search: the picker takes exactly what is counted']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(fixtures).toContain("'the reader took exactly the eligible pages'")
  expect(fixtures).toContain("'the picker took exactly the eligible searches'")
  expect(fixtures).toContain("'no alert for a cap pause'")
})

test('Work queues shows a cap pause as "Paused: daily cap", apart from stuck', async ({ page }) => {
  await mockAdmin(page)
  await page.route('**/rest/v1/rpc/admin_queue_watch', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({
    settings: { stuck_minutes: 120 }, can_run: false,
    queues: [{ key: 'course_page_search', label: 'Find course pages (search)', area: 'Course pages', purpose: 'Searches the web for course pages.', state: 'capped', pending: 898,
      reason: 'Paused: daily cap. 200 of 200 courses picked today (setting search.daily_picked_cap, counted per UTC day); picking resumes at 03 Nov 11:00', tools_out: [], tools_waiting: [] },
    { key: 'course_page_read', label: 'Read course pages', area: 'Course pages', purpose: 'Reads each matched course page.', state: 'done', pending: 0, tools_out: [], tools_waiting: [] }] }) }))
  await page.goto('/#platform-health?tab=queues')
  const row = page.locator('[data-queue="course_page_search"]')
  await expect(row).toContainText('Paused: daily cap')
  await expect(row).toContainText('picking resumes at 03 Nov 11:00')
  await expect(row).not.toContainText('Stuck')
})
