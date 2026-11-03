// Guards: CF-247 Decision 263 rule executor bounded (Integration Controller 4 Nov 2026: sfu_no_term reached the statement time-out at 00:16 and
// 00:26): the executor takes the rule's item ids first, up to the limit, and validates each item on its own within a time budget; the strict level
// check reads the level alone, once per item, and stays a real check (an item whose level is not confirmed, or whose reading fails, stays waiting
// with its reason). The behaviour runs on isolated fixtures by tests/fixtures/l4-rule-sfu-perf/run.sh (scratch PostgreSQL; built from the Layer 4
// course-link fixture and v2.15.448; the two edited definitions checked against the live md5s; the migration applied, applied again unchanged;
// a deliberately slow and a failing level reading).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104330000_cf247_l4_rule_sfu_perf.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/l4-rule-sfu-perf'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')

const EDITS = {
  'security.layer4_course_link_rule_validate_v1(text,uuid)': ['31bd052cb7161008ef9452bd24eb0e75', '3a5d088e4aaf3ad1e1a5460524a2e70a'],
  'security.layer4_course_link_rule_execute_v1(text,integer,boolean)': ['86e1089a5e93e1e2cce9a0ffd29aa22b', '85c991e7b626e07f9777f7a65249fd81'],
}

test('two live definitions are edited, md5-guarded both ways, and the fixture starts from the live text', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}',`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m).not.toMatch(/create or replace function security\.(course_page_check_v1|layer4_review_decide_impl|layer4_course_link_apply_impl)\b/)
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('the executor takes ids first, up to the limit, and validates each item on its own within a time budget', () => {
  expect(m).toContain("for v in select i.id item_id from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id")
  expect(m).toContain("asc nulls first, i.id")
  expect(m).toContain("if clock_timestamp() - v_t0 > make_interval(secs => security.pipeline_num_v1(''layer4.rule_execute_time_budget_s'', 5)) then v_left := v_left + 1; continue; end if;")
  expect(m).toMatch(/'layer4\.rule_execute_time_budget_s', 'Layer 4 rules: time one executor call may spend',[\s\S]*?to_jsonb\(5\), 1, 7, 'seconds'/)
  expect(fixtures).toContain("raise notice 'B2 ok")
})

test('the strict level check reads the level alone, once per item, and never passes without it', () => {
  expect(m).toContain('create or replace function security.layer4_rule_level_v1(p_course uuid, p_url text) returns jsonb')
  expect(m).toContain("'case when m.strict then security.layer4_rule_level_v1(m.course_id, m.target_url) end chk'")
  expect(m).toContain('e as materialized (')
  expect(fixtures).toContain("raise notice 'B1 ok")
  expect(fixtures).toContain("raise exception 'B3: an unconfirmed level was decided'")
})

test('one slow item does not stop the batch; nothing dropped or deleted', () => {
  expect(fixtures).toContain('pg_sleep(1.2)')
  expect(fixtures).toContain("raise notice 'B3 ok")
  expect(m).not.toMatch(/\bdelete from\b|\bdrop (table|function|trigger)\b/i)
})
