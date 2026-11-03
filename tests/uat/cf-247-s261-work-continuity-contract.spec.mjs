// Guards: CF-247 SS-021 work continuity (Platform Admin P0 mandate 3 Nov 2026 21:19 §2-§5, §7-§9): no single provider, course, source, reader
// failure or Layer 4 backlog stops unrelated eligible work. One work-item record per lane, entity and work kind (security.work_item_report_v1);
// recovery policies by failure class with every threshold a setting and no infinite retries; fair, admission-aware selection that never raises
// or bypasses a Layer 4 cap; per-item isolation in course-relink; one escalation per unchanged blocker through workstream A's controller (auto
// only for retry, park and release-claim); the §9 lane figures in the operations report. Recording, parking, claim release and fair selection
// ship on; handing parked AI reads back to the reader (AI spend) ships off. The behaviour runs on isolated fixtures by
// tests/fixtures/work-continuity/run.sh (scratch PostgreSQL 16; workstream A's controller loaded from its migration; the edited and called
// definitions checked against their live md5s; refused without A, applied, applied again unchanged; mandate §8 items 1-9 asserted).
// This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104170000_cf247_work_continuity.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/work-continuity'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const live = (f) => fs.readFileSync(`${FX}/live/${f}`, 'utf8')

test('codes against workstream A\'s live contract; edits only two live functions, md5-guarded, with their before and after md5s', () => {
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null then")
  for (const [sig, md5] of [['security.integration_issue_upsert_v1(jsonb,text)', 'c5ce0cb9c431a337789d67bc1878be62'],
    ['security.ops_root_cause_register_v1(text,jsonb)', '591616a6a0bd60d607f65c41c18e2968'], ['security.ops_remedy_register_v1(text,jsonb)', 'cec6cd2f6518b453fbc8ec3137ce39bd'],
    ['security.lane_paid_hold_v1(text)', '99ec517b8b51b0d1305b739e7f1562fb']]) {
    expect(m).toContain(`('${sig}', '${md5}')`)
    expect(run).toContain(`["${sig}"]=${md5}`)
  }
  expect(m).toContain("select pg_temp.edit_once('security.course_relink_tick_v1(integer)', '0cd20104a975c471ed4dd9060569f3b8', '656d308b1b12532a7e3e4335cf0f21ea',")
  expect(m).toContain("select pg_temp.edit_once('security.ops_report_v1(integer)', 'ff46a882b695539ca5cb7879a68ee578', '5a1e21cc42f8f54cbf0d9f3f7fe81c71',")
  expect(m).toContain('--   security.course_relink_tick_v1(integer) 0cd20104a975c471ed4dd9060569f3b8 -> 656d308b1b12532a7e3e4335cf0f21ea')
  expect(m).toContain('--   security.ops_report_v1(integer)         ff46a882b695539ca5cb7879a68ee578 -> 5a1e21cc42f8f54cbf0d9f3f7fe81c71')
  expect(m.match(/select pg_temp\.(edit_once|replace_once)\(/g)).toHaveLength(2)
  expect(live('course_relink_tick_v1.sql')).toContain('group by 1 order by count(*) desc loop')
  expect(m).toMatch(/^-- Replaces: security\.course_relink_tick_v1, security\.ops_report_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(run).toContain("without A's contract: refused, nothing left")
  expect(run).toContain('applied: only the two guarded edits changed existing functions')
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('§2 one work-item record keyed by lane, entity and work kind, written through one report function, reusing the controller\'s outcome codes', () => {
  expect(m).toContain('unique (lane, entity, work_kind)')
  for (const col of ['owner text not null', 'stage text not null', 'attempts int', 'failure_class text references pipeline.work_recovery_policies', 'evidence jsonb',
    'first_blocked_at timestamptz', 'last_attempt_at timestamptz', 'next_eligible_at timestamptz', 'recover_by timestamptz', 'escalation jsonb',
    'dependency_refs jsonb', 'lock_refs jsonb', 'evidence_version text', 'outcome text references pipeline.ops_outcome_codes(code)', 'unresolved_blocker jsonb'])
    expect(m).toContain(col)
  expect(m).toContain('create or replace function security.work_item_report_v1(p_lane text, p_entity text, p_kind text, p_event text, p_detail jsonb default')
  expect(m).toContain("comment on table pipeline.work_items is")
})

test('§3 policies by failure class: settings-governed, bounded, park with evidence, quarantine, defer, Layer 4, pause only the paid lane', () => {
  for (const [cls, action] of [['transient', 'retry_backoff'], ['ai_incomplete', 'retry_backoff'], ['ambiguity', 'park'], ['identity_conflict', 'quarantine'],
    ['site_unavailable', 'defer_recheck'], ['human_review', 'layer4_review'], ['review_full', 'defer_admission'], ['budget_exhausted', 'pause_lane'], ['manual_lock', 'hold_lock']])
    expect(m).toMatch(new RegExp(`\\('${cls}', '(?:[^']|'')+', '${action}'`))
  expect(m).toContain("least(security.pipeline_num_v1('wc.backoff_base_minutes', 10) * power(2, greatest(coalesce(p_attempts, 1), 1) - 1),")
  expect(m).toContain("when 'retry_backoff' then case when w.attempts >= v_max then 'parked' else 'retry_wait' end")
  expect(m).toContain("next_eligible_at = v_next, lease_until = null,")
  expect(fixtures).toContain('every policy threshold is a setting')
  expect(fixtures).toContain('every wc setting has label, range, unit and used_by')
  expect(fixtures).toContain('8.4 attempts used up: parked with evidence, no claim, no infinite retry')
  expect(fixtures).toContain('3 budget: the paid lane selects nothing; stored-evidence work continues')
  expect(fixtures).toContain('3 budget: resumes automatically when the budget allows')
})

test('§4 forward progress: fair selection, expired claims released, per-university isolation and time budget in course-relink', () => {
  expect(m).toContain('row_number() over (partition by ok.pid, ok.f order by ok.la nulls first, ok.pri desc, ok.n) turn')
  expect(m).toContain("perform security.work_item_report_v1(r.lane, r.entity, r.work_kind, 'failed', jsonb_build_object('class', 'lease_expired'")
  expect(m).toContain("if extract(epoch from clock_timestamp() - v_start) >= v_budget then v_stopped := 'time_budget'; exit; end if;")
  expect(m).toContain('exception when others then\n      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;')
  expect(m).toContain("    return jsonb_build_object('found', v_found, 'absent', v_absent) || security.course_relink_fair_run_v1(v_left);")
  expect(m).toContain("where j.jobname = 'course-relink' and d.runid > v_cursor and d.status = 'failed' and d.return_message ~* '(statement timeout|canceling statement)'")
  for (const s of ['8.1 relink: two universities relinked although the first in line failed', '8.1 the waiting university is skipped until it is due',
    'wc.relink_fair_on 0 behaves as before (the failure stops the run)', '8.5 the time-out is attributed to the university heading the order',
    '8.5 the next run relinks the others, not the timed-out head', '8.2 the other providers are selected', "4 fair: each provider''s first item before any second",
    '8.5 an expired claim does not hold the item', '8.5 the tick releases expired claims safely (transient attempt)'])
    expect(fixtures).toContain(s)
})

test('§5 admission-aware: existing caps are read, never raised; full categories defer without a review item; independent work continues', () => {
  expect(m).toContain("('aer', array['course_entry_first_read', 'entry_matrix_first_run'], 'aer.schedule_layer4_max', array['entry_requirements'],")
  expect(m).not.toMatch(/'(aer\.schedule_layer4_max|bind\.no_page_pending_max|pdesc\.pending_max)', '[^']+', '[^']*', 'number'/)
  expect(m).toContain('u.cat_turn <= (v_rooms->>u.cat)::numeric')
  expect(m).not.toMatch(/(insert into|update|delete from)\s+pipeline\.(layer4_|manual_locks)/)
  for (const s of ['8.3 fees and intakes still selected while AER is full', '8.3 AER work deferred without an attempt', '8.3 no review item raised by deferring',
    '5 room returned: deferred AER work is eligible again', '5 a category takes at most its room in one selection',
    '8.8 a pending human decision is waiting, not admitted, not eligible', '8.9 a manual lock is held, never retried',
    '8.8/8.9 Layer 4 items, decisions, admissions and manual locks unchanged by the whole run'])
    expect(fixtures).toContain(s)
})

test('§7 controller integration: auto only for retry, park and release-claim; authority, budget, identity and policy to the Platform Admin; one case per blocker', () => {
  for (const code of ['work_retry_parked', 'work_park_exhausted', 'work_release_claims']) expect(m).toMatch(new RegExp(`\\('${code}', '\\{[^\\n]*"authority": "auto"`))
  expect(m).toMatch(/\('work_blocker_decision', '\{[^\n]*"treats": \["work_site_unavailable", "work_identity_conflict", "work_budget_exhausted", "work_authority_required", "work_ambiguous_evidence"\], "authority": "admin"/)
  expect(m.match(/"authority": "auto"/g)).toHaveLength(3)
  expect(m).toContain("v_fp := 'work_blocked:' || g.lane || ':' || g.cls;")
  expect(m).toMatch(/perform security\.ops_remedy_register_v1\('work_continuity_adoption', jsonb_build_object\([\s\S]*?'authority', 'release',/)
  expect(fixtures).toContain("7 the audit''s live root causes route to the adopting release")
  for (const s of ['8.6 one issue for the blocker', '8.6 the unchanged blocker is not raised again when items join it', "7 the controller''s rule diagnoses the issue",
    '8.7 retry remedy re-arms the parked items (guard on)', '8.7 completed: done and counted as recovered', "8.7 the controller''s verification passes",
    '8.9 remedies never re-arm a locked or quarantined item'])
    expect(fixtures).toContain(s)
})

test('activation: recording, parking, release and fair selection ship on; AI recovery ships off; the job is catalogued', () => {
  for (const [k, v] of [['wc.on', 1], ['wc.escalate_on', 1], ['wc.relink_fair_on', 1], ['wc.ai_recovery_on', 0]])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}',[\\s\\S]*?'number', to_jsonb\\(${v}\\), 0, 1, 'on \\(1\\) or off \\(0\\)'`))
  expect(m).toContain("perform cron.schedule('work-continuity', '8,18,28,58 * * * *', $j$select security.work_continuity_tick_v1()$j$);")
  expect(m).toContain("('work-continuity', 'Platform upkeep', 18, 'Work continuity (release, resume, escalate)',")
  expect(fixtures).toContain('only the AI-spending switch ships off')
  expect(fixtures).toContain('8.4 not handed to the reader while wc.ai_recovery_on is 0 (AI spend ships off)')
})

test('§9 metrics: one read-only report, carried by the operations report', () => {
  expect(m).toContain('create or replace function security.work_continuity_report_v1() returns jsonb\nlanguage sql stable')
  for (const k of ["'eligible'", "'completed'", "'active'", "'blocked'", "'parked'", "'retry_due'", "'oldest_blocked_at'", "'recovery_success_pct'", "'repeated_root_causes'", "'awaiting_authority'"])
    expect(m).toContain(k)
  expect(m).toContain("    v_out := v_out || jsonb_build_object('work_continuity', security.work_continuity_report_v1());")
  expect(fixtures).toContain('9 ops_report_v1 carries the work_continuity section')
})
