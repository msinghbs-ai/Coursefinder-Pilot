// Guards: CF-247 SS-021 work continuity §4 (Platform Admin mandate 3 Nov 2026 21:19 "a failed item must not cause an otherwise valid batch to be
// discarded"; Integration Controller 22:16: course-relink still timed out at 22:04 and 22:14 inside one university after v2.15.443): each
// university's relink step is bounded below the run's limit (its address lists and title forms prepared once a university, a per-university
// deadline checked between courses), a university that settles nothing is recorded as a transient failure and parked after its attempts, and the
// statement limit firing inside one university is caught explicitly (query_canceled) as the last resort so the other universities' work commits.
// The behaviour runs on isolated fixtures by tests/fixtures/relink-isolation/run.sh (scratch PostgreSQL 16; the edited definitions checked
// against their live md5s; the live step's answers recorded first and compared; a deliberately slow university). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104240000_cf247_relink_isolation.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/relink-isolation'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')

test('two guarded changes from the live definitions; the work-continuity contract is required and unchanged', () => {
  expect(m).toContain("select pg_temp.edit_once('security.course_relink_provider_v1(uuid,integer)', '776844024ca5ee99011ad73dfd36360b', '07bd965bac8b7cd7b41a3092c447d677',")
  expect(m).toContain("select pg_temp.replace_once('security.course_relink_fair_run_v1(integer)', 'cd5a842d0f87bbe5439934eec66af4ac', '772a488ece3dc0bc9dc21cd8a9dc9f64', $def$")
  expect(m).toContain("('security.course_relink_tick_v1(integer)', '656d308b1b12532a7e3e4335cf0f21ea')")
  expect(m).toContain("('security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e')")
  expect(m.match(/select pg_temp\.(edit_once|replace_once)\(/g)).toHaveLength(2)
  expect(m).toMatch(/^-- Replaces: security\.course_relink_provider_v1, security\.course_relink_fair_run_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  for (const [sig, md5] of [['security.course_relink_provider_v1(uuid,integer)', '776844024ca5ee99011ad73dfd36360b'], ['security.course_relink_fair_run_v1(integer)', 'cd5a842d0f87bbe5439934eec66af4ac'],
    ['security.course_relink_tick_v1(integer)', '656d308b1b12532a7e3e4335cf0f21ea'], ['security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e']])
    expect(run).toContain(`["${sig}"]=${md5}`)
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('bounded per university: address lists and title forms prepared once, a deadline between courses, same answers', () => {
  expect(m).toContain("v_sl := security.course_relink_slugs_v1(r.ttl);")
  expect(m).toContain("select l.url, 'url_list', 3 from unnest(v_u, v_usl) l(url, sl)")
  expect(m).toContain("select l.url, 'url_list_variant', 3.5 from unnest(v_u, v_useg, v_utn) l(url, seg, tn)")
  expect(m).toContain("from unnest(v_ou, v_oc, v_ok1, v_ok2) o(url, course_id, k1, k2)")
  expect(m).toContain("security.pipeline_num_v1('relink.urls_per_university', 50000)")
  expect(m).toContain("if v_deadline is not null and clock_timestamp() >= v_deadline then v_stopped := 'deadline'; exit; end if;")
  expect(m).toMatch(/\('pipeline', 'wc\.relink_university_seconds',[\s\S]*?'number', to_jsonb\(20\), 5, 100, 'seconds'/)
  expect(before).toContain("ok: before: the live step works out the title forms % times for 6 courses and 305 addresses")
  for (const s of ['R1 title forms worked out once a course (6), not once an address and course', 'R1 the same candidates, sources and states as the live step',
    'R1 the same binds as the live step', 'R2 the slow university stopped at its deadline after settling some courses',
    'R2 the universities before and after it were relinked in the same run', 'R3 settled nothing in its time: transient failure, backoff, evidence'])
    expect(fixtures).toContain(s)
})

test('isolation: a slow university is recorded and parked after its attempts; the statement limit is caught explicitly as the last resort', () => {
  expect(m).toContain('    exception\n      when query_canceled then')
  expect(m).toMatch(/when query_canceled then[\s\S]*?v_stopped := 'statement_timeout';\n        exit;\n      when others then/)
  expect(m).toContain("'message', 'no course settled within the university''s time (wc.relink_university_seconds)'")
  expect(m).toContain("perform set_config('cf247.relink_deadline', '', true);")
  for (const s of ['R4 the run ended at the slow university without failing', 'R4 the university before it stays committed',
    "R4 the slow university''s partial work is rolled back", 'R4 the slow university is recorded (57014) and waits for its backoff',
    'R4 the next run relinks the next university and skips the slow one', 'R4 after its attempts the slow university is parked with evidence'])
    expect(fixtures).toContain(s)
})
