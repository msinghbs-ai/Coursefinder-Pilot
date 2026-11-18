// Guards: S675 AER consumer data finding consumer_unadmitted (Platform Admin 18 Nov 2026 22:26 AEDT, alert batch 88e5ff5b-3fb9-4613-80db-3ff0c96a6b06): a provider-table row a person approved stays admitted when a later re-record re-points its run; a run a person approved is never recorded again; a row no approved item names is still a P0 finding; no Layer 4 decision, row or threshold is changed and nothing is created.
// CF-247 S675. Migration 20261118270000_cf247_s675_aer_admitted_run_link. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118270000_cf247_s675_aer_admitted_run_link.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('both functions are edited in place once, under their live md5 of 18 Nov', () => {
  expect(M).toContain("'security.aer_current_findings_v1()', '6bfcb39c7271343abf0139081f0d9a37'")
  expect(M).toContain("'public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', 'bbf3517e5eb8b40fa12ea3020a274ca4'")
  expect(M).toContain('the edit must apply exactly once')
  expect(M).toContain('already applied')
  expect(code(M)).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger)/i)
  expect(M).toMatch(/-- Replaces: security\.aer_current_findings_v1 and public\.svc_entry_matrix_record/)
  expect(M).toContain('Retires: nothing.')
})

test('an approval that names the run admits its rows; anything else stays a P0 finding', () => {
  expect(M).toContain("and not exists (select 1 from pipeline.layer4_review_items la where la.entity_id = m.provider_id and la.field_code in ('entry_matrix_first_run', 'entry_matrix_change')")
  expect(M).toContain("and la.status in ('approved', 'edited_approved') and la.proposed_value->>'run_id' = m.run_id::text)")
  // the original clause stays: the new condition only narrows it
  expect(M).toContain("coalesce(li.status, 'none') not in ('approved', 'edited_approved')")
})

test('a run a person approved is never recorded again, and nothing is quarantined, rewritten or deleted', () => {
  expect(M).toContain("if r.review_item_id is not null and exists (select 1 from pipeline.layer4_review_items d where d.id = r.review_item_id and d.status in ('approved', 'edited_approved')) then")
  expect(M).toContain("return jsonb_build_object('ok', false, 'status', 'already_decided', 'review_item_id', r.review_item_id);")
  const c = code(M)
  expect(c).not.toMatch(/update (catalogue|pipeline)\.(provider_entry_matrix|course_entry_requirements|layer4_review_items|layer4_decisions|entry_matrix_runs)|delete from|drop (table|function)|truncate/i)
  expect(c).toContain("'quarantined', 0")
  expect(c).toContain('consumer_api_functions_v1()) <> 75')
})
