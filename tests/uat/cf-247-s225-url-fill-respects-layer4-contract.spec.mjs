// Guards: Course link fill respects Layer 4 (Platform Admin direction 2 Nov 2026 23:24, Workstream E; housekeeping finding H05)
// The nightly course link fill (job course-url-fill, security.course_url_fill_v1) must not write course_url for a course with a pending
// official_course_url Layer 4 review: on 2 Nov 13:23 (event #28612) it wrote 25 pages that were still under review. The skips are counted in
// the run's event and, when the integration queue exists, recorded as one queue issue by fingerprint. The switch is a setting (G2).
// The behaviour runs on isolated fixtures by tests/fixtures/url-fill-layer4/run.sh (scratch PostgreSQL; the function rebuilt from this repository
// and checked against the live md5, the migration applied twice); this spec holds the contract and the fixture coverage.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103030000_cf247_url_fill_respects_layer4.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/url-fill-layer4'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/before.mjs`, 'utf8')
const edit = m.slice(m.indexOf("select pg_temp.edit_once('security.course_url_fill_v1()'"), m.indexOf('], array[1, 1, 1, 1, 1, 1]);'))

test('the fill is edited only from its live md5 and checked after; the fixtures rebuild it and check live first', () => {
  expect(m).toContain("select pg_temp.edit_once('security.course_url_fill_v1()', '9ae50ba49eea0a30ecd8da20eef7f97b', '270be3f52e98b58a1153b7c1170fd57e'")
  expect(code).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(code).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(m).toContain('], array[1, 1, 1, 1, 1, 1]);')
  expect(before).toContain('20261024001000_cf247_course_url_fill.sql')
  expect(run).toContain('[ "$(md5of)" = "9ae50ba49eea0a30ecd8da20eef7f97b" ]')
  expect(run).toContain('[ "$(md5of)" = "270be3f52e98b58a1153b7c1170fd57e" ]')
  expect(run).toContain("grep -c 'already applied' | grep -qx 1")
})

test('a course with a pending official_course_url review is neither filled nor re-filled while the switch is on, and is counted', () => {
  expect(edit).toContain("v_respect boolean := security.pipeline_num_v1('course_url.fill_respects_layer4', 1) = 1;")
  // the fill's candidate set excludes them (a hashed sub-plan over the pending items, never a per-row scan)
  expect(edit).toContain("and c.id not in (select i.entity_id from pipeline.layer4_review_items i\n                         where v_respect and i.entity_type = 'course' and i.field_code = 'official_course_url' and i.status = 'pending' and i.entity_id is not null)")
  // the count uses the same eligibility as the fill, plus the pending review
  expect(edit).toContain("select count(*), coalesce(array_agg(c.id order by c.id), '{}') into v_skipped, v_skip_ids")
  expect(edit).toContain("and c.id in (select i.entity_id from pipeline.layer4_review_items i\n                     where i.entity_type = 'course' and i.field_code = 'official_course_url' and i.status = 'pending' and i.entity_id is not null);")
  // retractions (guard 3) and locks are untouched: nothing already filled is emptied by this change
  expect(edit).not.toContain('retracted_at = now()')
  expect(edit).not.toContain('course_url = null')
})

test('skips are in the run event and the return value; a skip-only run still writes its event', () => {
  expect(edit).toContain('if v_filled > 0 or v_retracted > 0 or v_skipped > 0 then')
  expect(edit).toContain("'skipped_pending_layer4', v_skipped, 'respects_layer4', v_respect, 'integration_queue', v_iq), null);")
  expect(edit).toContain("'skipped_pending_layer4', v_skipped, 'respects_layer4', v_respect, 'integration_queue', v_iq);")
})

test('the integration queue gets one issue by a deterministic fingerprint, only when the queue exists, and never stops the fill', () => {
  expect(edit).toContain("if v_skipped > 0 and to_regprocedure('security.integration_issue_upsert_v1(jsonb,text)') is not null then")
  expect(edit).toContain("execute 'select security.integration_issue_upsert_v1($1, $2)' into v_iq")
  expect(edit).toContain("using jsonb_build_object('fingerprint', 'course-url-fill:skipped-pending-layer4',")
  expect(edit).toContain("'workstream', 'A4', 'severity', 'P2', 'root_cause_class', 'human_decision'")
  expect(edit).toContain("exception when others then\n      v_iq := jsonb_build_object('error', left(sqlerrm, 300));")
  // the payload fits the queue's own contract (v2.15.409): the function signature and the allowed workstream, root cause and validation layer
  const q = fs.readFileSync('supabase/migrations/20261102120000_cf247_integration_queue.sql', 'utf8')
  expect(q).toContain("create or replace function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb")
  expect(q).toContain("workstream in ('A1', 'A2', 'A3', 'A4'")
  expect(q).toContain("'human_decision'")
  expect(q).toContain("validation_layer in ('V1', 'V2', 'V3', 'V4', 'manual')")
})

test('the switch and the old pause threshold are settings with label, range, unit and used_by (G2)', () => {
  expect(m).toContain("('pipeline', 'course_url.fill_respects_layer4', 'Official link: wait for Layer 4',")
  expect(m).toContain("'number', '1'::jsonb, '0', '1', 'on/off', 604, 'Official link', 'job course-url-fill; security.course_url_fill_v1',")
  expect(m).toContain("('pipeline', 'course_url.retraction_min_fills', 'Official link: fills before the pause check',")
  expect(m).toContain("'number', '50'::jsonb, '10', '1000', 'links', 605, 'Official link', 'security.course_url_fill_v1',")
  expect(edit).toContain("$o$(v_rate->>'filled')::int >= 50 and$o$")
  expect(edit).toContain("$n$(v_rate->>'filled')::int >= security.pipeline_num_v1('course_url.retraction_min_fills', 50) and$n$")
  expect(m).toContain('on conflict (toolset_key, key) do nothing;')
  // the job's catalogue note says the rule, once
  expect(m).toContain("where jobname = 'course-url-fill' and description not like '%Official link: wait for Layer 4%'")
})

test('the fixtures cover the cases', () => {
  for (const c of ['ok 1 pending course-link review left and counted', 'ok 2 skip-only run is recorded in its event',
    'ok 3 one integration-queue issue by fingerprint, updated in place on the next run', 'ok 4 queue error recorded, fill completed',
    'ok 5 switch off: the old behaviour', 'ok 6 pause threshold read from course_url.retraction_min_fills',
    'ok 7 two settings with label, range, unit and used_by']) expect(fixtures).toContain(c)
  // a pending review of another field, and a decided course-link review, do not hold the fill back
  expect(fixtures).toContain("'provider_current_tuition_validation', 'pending'")
  expect(fixtures).toContain("'official_course_url', 'approved'")
})
