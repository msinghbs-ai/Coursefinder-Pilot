// Guards: Layer 4 rule l4-link-refusal-v1 and the reconcile window (Platform Admin 16 Nov 2026 16:47 AEDT, report section 3.2 option 1): closes only official-link items the finder already refused, through Refuse this proposal, never the live official page, with an audit sample; layer4_reconcile_v1 never starves behind older items
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations-archive/20261116143000_cf247_l4_link_refusal_rule_reconcile_window.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const check = code.slice(code.indexOf('create or replace function security.layer4_course_link_refusal_check_v1'), code.indexOf('create or replace function security.layer4_course_link_refusal_rule_v1'))
const rule = code.slice(code.indexOf('create or replace function security.layer4_course_link_refusal_rule_v1'), code.indexOf('do $g$'))
const recon = code.slice(code.indexOf('create or replace function security.layer4_reconcile_v1'), code.lastIndexOf('do $g$'))

test('scope: only negative-evidence official-link holds whose refusal is already recorded, never the live official page', () => {
  expect(check).toContain("i.field_code = 'official_course_url' and i.entity_type = 'course'")
  expect(check).toContain("i.escalation_reason like 'The page found automatically was not linked: %'")
  for (const p of ["another course''s at this provider", 'another qualification level', 'another version of the award', 'handbook entry', 'another campus']) expect(check).toContain(p)
  expect(check).not.toMatch(/do not name this programme|shared by several courses|CRICOS code is a different address|archived handbook/)
  expect(check).toContain('from pipeline.page_rejections pr where pr.course_id = g.entity_id')
  expect(check).toContain("the proposed page is the course''s active official page (a person decides)")
  expect(check).toContain("l.link_type = 'official_course' and l.status = 'active'")
  expect(check).toContain("o.owner = 'chatgpt' and o.closed_at is null")
  expect(check).toContain("security.pipeline_num_v1('layer4.link_refusal_audit_pct', 5)")
  expect(check).toMatch(/language sql stable security definer/)
})

test('decisions go through Refuse this proposal under the system automation account, item by item, behind the switch', () => {
  expect(rule).toContain('security.layer4_course_link_refuse_v1(v.item_id, v_reason)')
  expect(rule).toContain("v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed:")
  expect(rule).toContain('for update nowait')
  expect(rule).toContain('security.layer4_course_link_refusal_check_v1(v.item_id)')
  expect(rule).toContain("layer4.link_refusal_rule_on is 0: the rule only counts")
  expect(rule).toContain("'audit sample of rule l4-link-refusal-v1 (a person decides)'")
  expect(rule).toContain("security.pipeline_num_v1('layer4.link_refusal_batch', 200)")
  expect(rule).toContain("security.pipeline_num_v1('layer4.link_refusal_time_budget_s', 7)")
  expect(rule).not.toMatch(/'approve'|edit_and_approve|course_links|catalogue\.courses\s+set/i)
  expect(rule).not.toMatch(/update\s+pipeline\.layer4_review_items\s+set\s+status/i)
})

test('the migration decides nothing itself and adds no job; settings carry label, range, unit and used_by', () => {
  expect(code).not.toMatch(/cron\.schedule|automation_catalogue/)
  expect(code).not.toMatch(/select\s+security\.layer4_course_link_refusal_rule_v1\(/i)
  expect(code).toContain("raise exception 'post-check: the migration decides nothing (no run recorded)'")
  for (const k of ['layer4.link_refusal_rule_on', 'layer4.link_refusal_batch', 'layer4.link_refusal_time_budget_s', 'layer4.link_refusal_audit_pct', 'layer4.reconcile_examine_max']) expect(code).toContain(`'${k}'`)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).toMatch(/^-- Replaces: security\.layer4_reconcile_v1\(text,integer\)/m)
  expect(sql).toMatch(/^-- Retires: nothing\./m)
  for (const t of ['layer4_link_refusal_runs', 'layer4_link_refusal_run_items', 'layer4_reconcile_cursor']) expect(code).toContain(`comment on table pipeline.${t} is`)
  expect(code).toContain("security.consumer_api_check_v1() - 'checked_at'")
})

test('reconcile: p_limit caps items settled, a setting caps items examined, and a cursor wraps so nothing starves', () => {
  expect(code).toContain("v_md5 not in ('5ec45998c27babfb92d024b0c60d1265', ")
  expect(recon).toContain("security.pipeline_num_v1('layer4.reconcile_examine_max', 5000)")
  expect(recon).toContain('limit v_max loop')
  expect(recon).not.toMatch(/limit greatest\(coalesce\(p_limit/)
  expect(recon).toContain('exit when v_n >= v_cap;')
  expect(recon).toContain('(i.created_at, i.id) <= (v_cur.last_created_at, v_cur.last_item_id)')
  expect(recon).toContain('insert into pipeline.layer4_reconcile_cursor')
  expect(recon).toContain('if v_cap = 0 then')
  expect(recon).toContain("security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) >= 1")
  expect(code).toContain("set value = '200'::jsonb")
})
