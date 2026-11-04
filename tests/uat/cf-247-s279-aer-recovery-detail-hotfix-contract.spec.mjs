// Guards: Platform Admin report 4 Nov 2026 11:13 (Layer 4 Review, UNSW Bachelor of Actuarial Studies: only Reject the read usable and
// "canceling statement due to statement timeout" above the buttons) under the 06:58 decision (E13-held AER reads gain governed recovery
// actions). The recovery panel of a held AER card must not run the completeness gate for every waiting read of the university, so its
// recovery choices load; the case key, deduplication, decide function and E13/D-R3 gates are unchanged and no time-out is raised.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104475000_cf247_aer_recovery_detail_hotfix.sql'
const m = fs.readFileSync(MIG, 'utf8')
const body = m.slice(m.indexOf('create or replace function security.layer4_aer_recovery_detail_v1'))

test('the hotfix edits only the recovery detail, guarded on the live definition it was written against', () => {
  expect(m).toContain("'a83f37a2a63c11cab82d66a124256c6e'")
  expect(m).toMatch(/^-- Replaces: security\.layer4_aer_recovery_detail_v1\(text\)/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect((m.match(/create or replace function /g) || []).length).toBe(1)
  for (const f of ['layer4_aer_recovery_state_v1', 'layer4_aer_recovery_decide_v1', 'course_entry_gate_v1', 'entry_matrix_gate_v1', 'admin_layer4_inbox'])
    expect(m).not.toMatch(new RegExp(`create or replace function [a-z]+\\.${f}\\(`))
  expect(m).not.toMatch(/statement_timeout/)
})

test('the case list no longer calls the completeness gate once per waiting read', () => {
  const list = body.slice(body.indexOf('into v_case') - 400, body.indexOf('into v_case') + 700)
  expect(list).not.toContain('layer4_aer_recovery_state_v1(li.id)')
  expect(body.match(/layer4_aer_recovery_state_v1\(/g)).toHaveLength(1)
  expect(list).toContain("c.provider_id = (st->>'provider_id')::uuid")
  expect(list).toContain("security.pipeline_num_v1('har.aer_case_items_max', 20)")
  expect(body).toContain("'Other waiting reads of this university and kind', v_case")
})

test('the four recovery actions and their rules are unchanged', () => {
  for (const k of ['reread_stored', 'request_evidence', 'ai_analyse', 'open_intervention']) expect(body).toContain(`'key', '${k}', 'allowed'`)
  expect(body).toContain("the stronger-model step is off (har.ai_escalate_on, ops.ai_diagnosis_on or no pinned model)")
})
