// CF-247 HOTFIX (Platform Admin 24 Oct 2026 13:17): a person's Find course pages task reaches Firecrawl on accept and on the same path
// as the scheduled search; a stalled task names its blocking reason; Layer 4 "Enter another address" on a held-fee item goes through the
// standard bind path. Record: admin repo docs/platform/ui-audit/2026-10-24-hotfix-manual-task-and-layer4-entry.md.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024009000_cf247_hotfix_manual_task_and_layer4_entry.sql', 'utf8')
const inbox = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const tasks = fs.readFileSync('src/AdminTasks.jsx', 'utf8')

// the screen's own helpers, loaded without the JSX around them
const helpers = new Function(inbox.match(/export const isFeeItem=[^\n]+\nexport const urlOk=[^\n]+/)[0].replace(/export const /g, 'var ') + '\nreturn {isFeeItem,urlOk}')()
const statusSrc = tasks.match(/export function taskStatusLine\(st\)\{[\s\S]*?\n\}/)[0]
const taskStatusLine = new Function('fmtTime', 'fmtNumber', statusSrc.replace('export function', 'function') + '\nreturn taskStatusLine')(d => `T${new Date(d).toISOString().slice(11, 16)}`, n => String(n))

test('a Find course pages task forwards to the toolset on accept, on the same path as the scheduled search (within 30 seconds)', () => {
  // accept → fire: the task's prepare step asks the worker straight after commit
  expect(m).toContain("perform security.provider_task_fire_v1('link_search');  -- hotfix D2: forwarded on accept, not at the next minute")
  // the body is the minute job's body word for word: one path for the person's task and the schedule
  expect(m).toContain("when 'link_search' then jsonb_build_object('mode', 'link_search', 'limit', security.pipeline_num_v1('batch.link_search_worker', 120)::int) end;")
  // a lane an operator paused is not overridden
  expect(m).toMatch(/if p_mode = 'link_search'\s+and not exists \(select 1 from cron\.job j where j\.jobname = 'course-link-search-worker' and j\.active\)/)
  // the picker: a person's running task passes the search stop and the bulk-onboarding check only, behind a setting
  expect(m).toContain("and (not pv.stopped or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))")
  expect(m).toContain("when s.requested_at is not null and (not pv.bulk or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id))) then true")
  expect(m).toContain("'search.person_task_bypass'")
  expect(m).toMatch(/\$o\$       and q\.provider_id <> all \(v_stopped\)\n\$o\$, \$n\$\$n\$/)
  // no gate, budget or cap is changed (constraint): the picker's month cap, day share and target-only lines are not edited
  for (const kept of ["v_used + 2 * v_lim > v_cap", "fc_budget_left_v1('course_link_search') / 2", "firecrawl_setting('target_only')"]) {
    const edits = m.split('svc_course_link_search_next(integer)')[1].split("array[1, 1, 1, 1, 1]")[0]
    expect(edits).not.toContain(kept)
  }
  expect(m).not.toMatch(/update pipeline\.(course_link_search_settings|platform_toolset_settings)/)
  // the lane's wake-up test agrees with the picker
  expect(m).toContain("or (security.pipeline_num_v1('search.person_task_bypass', 1) >= 1 and security.link_search_person_task_v1(s.provider_id, s.course_id))))")
  // every edit is md5-guarded against the live definition
  for (const sig of ['public.svc_course_link_search_next(integer)', 'security.worker_mode_waiting_v1(text)', 'security.provider_task_fire_v1(text)', 'security.provider_task_prepare_v1(text,jsonb)',
                     'security.admin_job_watch_v1(uuid)', 'public.admin_jobs(text,jsonb)', 'public.admin_layer4_inbox(text,jsonb)', 'security.gap_causes_snapshot_v1()']) {
    expect(m).toMatch(new RegExp(`pg_temp\\.edit_n\\('${sig.replace(/[().]/g, '\\$&')}', '[0-9a-f]{32}'`))
  }
})

test('a stalled task surfaces its blocking reason: last forwarded, next attempt, and the gate that holds it after tasks.stall_seconds', () => {
  expect(m).toContain("'tasks.stall_seconds'")
  expect(m).toMatch(/'tasks\.stall_seconds', 'Tasks: blocked after'.*'60'::jsonb, '30', '3600', 'seconds'/)
  expect(m).toContain("make_interval(secs => v_stall)")
  expect(m).toContain("'status', security.admin_job_status_v1(j.id)) order by j.created_at desc)")
  // the stall taxonomy walks the picker's gates in its order
  const order = ['lane_paused', 'lane_idle_paused', 'search_off', 'month_cap', 'day_budget', 'provider_hidden', 'search_stopped', 'not_target', 'no_site', 'directory_site', 'skipped_provider']
  const at = order.map(c => m.indexOf(`'code', '${c}'`))
  expect(at.every(i => i > 0)).toBe(true)
  expect([...at].sort((a, b) => a - b)).toEqual(at)
  // the watcher names the gate instead of "the rest wait their turn"
  expect(m).toContain("v_note := 'Blocked: ' || (v_extra->'blocked'->>'words')")
  // the hourly gap causes name the stop and do not call it automatic
  expect(m).toContain("'no page: web search stopped for this university'")
  expect(m).toContain("'campus has no city', 'fee waiting in review', 'no page: web search stopped for this university')")
  // the Task manager shows it, in words
  expect(tasks).toContain('<TaskBlocked st={j.status}/>')
  expect(tasks).toContain('data-task-blocked={b.code}')
  expect(tasks).toContain("{j.state==='running'&&j.status&&<small className=\"sl-sub\" data-task-status>{taskStatusLine(j.status)}</small>}")
  expect(taskStatusLine({ last_forwarded_at: null, next_attempt_at: '2026-10-24T02:34:00Z', forwarded: 0 })).toBe('Last forwarded not yet · next attempt T02:34')
  expect(taskStatusLine({ last_forwarded_at: '2026-10-24T02:33:50Z', next_attempt_at: '2026-10-24T02:34:00Z', forwarded: 58 })).toBe('Last forwarded T02:33 (58 sent) · next attempt T02:34')
  expect(taskStatusLine(null)).toBe('')
})

test('Layer 4 "Enter another address" on a held-fee course-link item runs bind → read again → fee re-admit (mocked call chain); non-https gets the validation message', async () => {
  const feeItem = { kind: 'course_link', ref: 'c62b431b-c5b2-4805-8468-8cc714fc624a', detail: { field_code: 'provider_current_tuition', course_id: '4ec179da' } }
  expect(helpers.isFeeItem(feeItem)).toBe(true)
  expect(helpers.isFeeItem({ kind: 'course_link', detail: { field_code: 'official_course_url' } })).toBe(false)
  expect(helpers.urlOk('http://www.aut.ac.nz/courses/x', true)).toBe(false)
  expect(helpers.urlOk('https://www.aut.ac.nz/courses/x', true)).toBe(true)
  expect(helpers.urlOk('http://www.aut.ac.nz/courses/x', false)).toBe(true)
  // the screen: no "Use the new page" on a fee item, https only, the address box starts empty
  expect(inbox).toContain("const choices=(k.choices||[]).filter(c=>!(fee&&c.key==='use'))")
  expect(inbox).toContain("(open.input==='url'&&!urlOk(value,fee))")
  expect(inbox).toContain("c.input==='url'&&it.kind==='course_link'&&!fee?urlOf(d.proposed):''")
  // the server: a fee item no longer reaches layer4_review_decide (whose scalar fall-through refused it)
  expect(m).toContain("if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition' and v_choice in ('use', 'enter') then")
  expect(m).toContain("v_r := security.layer4_fee_item_rebind_v1(v_ref::uuid, v_value, v_reason);")
  expect(m).toContain("if v_url !~* '^https://[^\\s/]+\\.[^\\s]+$' then raise exception 'enter the full web address (https://…)'; end if;")
  expect(m).toContain("raise exception 'this page is not on the provider''s own website (%)', v_dom;")

  // mocked chain: replay the rebind function's calls against fakes, in the order the function makes them
  const body = m.split('create or replace function security.layer4_fee_item_rebind_v1')[1].split('end $$;')[0]
  const calls = [...body.matchAll(/perform public\.admin_course_edit\(|update pipeline\.layer4_review_items set status = 'edited_approved'|insert into pipeline\.layer4_decisions/g)].map(x => x[0])
  expect(calls).toEqual(['perform public.admin_course_edit(', "update pipeline.layer4_review_items set status = 'edited_approved'", 'insert into pipeline.layer4_decisions'])
  expect(body).toContain("'set_official_url'")
  // set_official_url (the standard path a person's page entry takes) binds manually, locks, and reads first in line; a manual binding
  // is exempt from the identity quarantine, so the fee reader's value admits. A fake of that contract:
  const db = { page: { basis: 'ai_match', status: 'mismatch' }, locks: [], read: [], fee: null, item: 'pending' }
  const fake = {
    admin_course_edit: (course, action, a) => { if (action !== 'set_official_url' || !/^https:\/\//.test(a.url)) throw new Error('refused'); db.page = { url: a.url, basis: 'manual', status: 'bound', next_read_at: 'now' }; db.locks.push('official_url', 'course_url'); db.read.push(course) },
    reader: course => { if (db.read.includes(course)) db.page.read_status = 'read' },
    fee_reader: () => { if (db.page.read_status === 'read' && (db.page.basis === 'manual' || db.page.identity_ok)) db.fee = 'active' },
  }
  fake.admin_course_edit(feeItem.detail.course_id, 'set_official_url', { url: 'https://www.aut.ac.nz/courses/postgraduate-certificate-in-science', reason: 'Layer 4: wrong page' }); db.item = 'edited_approved'
  fake.reader(feeItem.detail.course_id); fake.fee_reader()
  expect(db).toMatchObject({ page: { basis: 'manual', status: 'bound', read_status: 'read' }, locks: ['official_url', 'course_url'], fee: 'active', item: 'edited_approved' })
})
