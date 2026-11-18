// Guards: grouped Layer 4 decisions (Platform Admin 18 Nov 2026 13:02): only AER items held for a shared stored page (by provider and page) and refused study loads with the same quote (by provider) are grouped; the AER audit sample, identity and page problems, campus postcodes and other kinds are never grouped; each item is decided through admin_layer4_inbox at the single item's rank, with one reason, a typed confirmation and a refusal when the group changed.
// CF-247 S639. supabase/migrations-archive/20261118162000_cf247_layer4_grouped_decisions.sql (study-load groups fixed in 20261118164000), src/Layer4GroupDecide.jsx.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118162000_cf247_layer4_grouped_decisions.sql', 'utf8')
const F = fs.readFileSync('supabase/migrations-archive/20261118164000_cf247_layer4_grouped_decisions_study_load_fix.sql', 'utf8')

test('groups: shared-page AER items by provider and page, study loads by provider and quote; audit samples and identity problems never', () => {
  expect(M).toContain("and security.aer_e13_class_v1(x.gate) = 'shared_page'")
  expect(M).toContain("where coalesce(l.reason_code, '') not in ('audit_sample', 'identity_not_admitted', 'no_bound_page'))  -- never grouped")
  expect(F).toContain("group by o.provider_id, o.q")
  expect(F).toContain("perform count(*) from security.layer4_decision_groups_v1('boost_study_load');")
  expect(M).toContain("raise exception 'an AER audit sample was grouped';")
  expect(M).toContain("if v_kind not in ('aer_review', 'boost_study_load') then raise exception 'this kind is decided one item at a time'; end if;")
})

test('a grouped decision goes item by item through the Inbox, at the single item rank, confirmed and never on a stale group', () => {
  expect(M).toContain("v_r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice,")
  expect(M).toContain("if v_rank < v_need then raise exception 'your role cannot make this choice (rank % needed, as for one item)'")
  expect(M).toContain("raise exception 'the group has changed since it was shown (% now waiting); refresh and check it again', g.n;")
  expect(M).toContain("if v_confirm <> upper(v_choice) || ' ' || g.n then raise exception 'type % to confirm'")
  expect(M).toContain("values ('review_batch', v_choice, auth.uid(),")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})

test('the grid offers Grouped decisions beside the saved views and keeps the operational groups screen', () => {
  const G = fs.readFileSync('src/Layer4Grid.jsx', 'utf8')
  expect(G).toContain('data-l4g-view="grouped"')
  expect(G).toContain('{grouped&&<Layer4GroupDecide onDecided=')
  const D = fs.readFileSync('src/Layer4GroupDecide.jsx', 'utf8')
  expect(D).toContain("call('admin_layer4_group_decide_v1',{p_args:{kind,group_key:g.group_key,refs:g.refs,choice,reason:reason.trim(),confirm:`${choice.toUpperCase()} ${g.n}`}})")
  expect(fs.readFileSync('src/Layer4Groups.jsx', 'utf8')).toContain("supabase.rpc('admin_layer4_groups'")
})
