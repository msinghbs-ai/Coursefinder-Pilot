// Guards: CF-247 s813/s814 (Platform Admin 20 Nov 2026 09:55, chat S1-Build): Layer 4 decisions do not time out — the Held scholarship decision
// applies without rebuilding the AI screen, and the decision guard, fee outcome, held description promotion and keyed item reads use indexes
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120110000_cf247_s813_s814_layer4_decision_speed.sql', 'utf8')

test('Held scholarship: the decision and its audit row, without public.admin_scholarship_ai and its dashboard', () => {
  expect(MIG).toContain("select pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, 'c179c26dca4107946ab57e5191143c51',")
  const fresh = MIG.slice(MIG.indexOf("array[$n$  elsif v_kind = 'held_scholarship' then"), MIG.indexOf("select pg_temp.cf_edit_def('security.layer4_decision_outcome_v1"))
  expect(fresh).toContain('security.scholarship_ai_review_apply_v1(v_ref::bigint, case when v_choice = \'publish\' then \'admit\' else \'refuse\' end,')
  expect(fresh).toContain("values ('scholarship_ai', 'review_decide', '', jsonb_build_object('review_id', v_ref::bigint,")
  expect(fresh).not.toContain('public.admin_scholarship_ai(')
})

test('the guard, the fee outcome and the held description promotion read through indexes', () => {
  expect(MIG).toContain("create index if not exists admin_control_events_l4_guard_idx on pipeline.admin_control_events ((detail->>'provider_id'), (detail->>'kind'), (detail->>'choice'), id desc)")
  expect(MIG).toContain("create index if not exists field_enrich_items_desc_held_idx on pipeline.field_enrich_items (provider_id, id) where field = 'description' and state = 'skipped';")
  expect(MIG).toContain("create index if not exists course_fees_layer4_decision_note_idx on catalogue.course_fees (substr(notes, 1, 80))")
  expect(MIG).toContain("and substr(f.notes, 1, 80) = 'CF-247 Layer 4 human decision; review item ' || (p_result->>'review_item_id') || ';'")
  // the note head is exactly the old LIKE prefix plus the uuid and ';' (43 + 36 + 1 = 80)
  expect('CF-247 Layer 4 human decision; review item '.length + 36 + 1).toBe(80)
})

test('keyed item reads match the id as its type and keep the text match, so the rows are the same', () => {
  expect(MIG).toContain("select pg_temp.cf_edit_def('security.layer4_inbox_items_v2(uuid,text,text[],boolean)'::regprocedure, '26283b7b330d74a86122307e2ab8b7f7',")
  expect(MIG).toContain("(p_keys is null or (r.id = any (array(select split_part(k, ':', 2)::uuid from unnest(p_keys) k where split_part(k, ':', 2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) and z.k || ':' || r.id::text = any (p_keys)))")
  expect(MIG).toContain('array[1, 1, 2, 1]);')
  expect(MIG).toContain("raise exception 'post-check: the keyed read differs from the full read'")
})

test('the migration decides real items of every slow kind in rolled-back blocks and refuses a slow held scholarship decision', () => {
  for (const s of ["['held_scholarship', 'not_international']", "['nothing_ready', 'rebuild']", "['course_link', 'use']", "['provider_description', 'approve']", "['aer_review', 'approve']",
    "if v_hs > 1000 then raise exception 'post-check: a held scholarship decision took % ms', v_hs; end if;", "raise exception 'cf-s813-undo';"])
    expect(MIG).toContain(s)
  expect(MIG).not.toMatch(/create (or replace )?(function|view|table) (public|api)\./)
})
