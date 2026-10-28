// Guards: CF-247 AER programme re-read of ANU after the numeric-table reader correction (Platform Admin consolidated mandate 28 Oct 2026 23:22; deploy-order lesson 28 Oct): merged only after worker v0.50.1 is live; only runs with no row and no Layer 4 item, bounded; the earlier reading kept in the run history. And no endless retrying: a read cut by call time after spending on the model uses a try
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029004000_cf247_aer_reread_and_time_budget.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('ANU only, no row and no Layer 4 item, bounded, history kept; nothing else', () => {
  expect(code).toContain("where provider_id = 'e47a940d-186f-4a17-bb22-2b794b73248c' and state = 'done' and review_item_id is null and coalesce(rows_admitted, 0) = 0;")
  expect(code).toContain("if v_n > 20 then raise exception")
  expect(code).toContain("previous_results = previous_results || jsonb_build_array(jsonb_build_object('held', false, 'reason', 'read again after worker v0.50.1 (numeric tables named)',")
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/create or replace function public\./i)
})

test('a cut read that spent on the model uses a try; one cut before any call still waits free; slice size a setting change with a reason', () => {
  expect(code).toContain("select pg_temp.edit_n('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', 'e1a130e278ff535e33eade3c2e0b9aa2'")
  expect(code).toContain("when p_error = 'time budget' and coalesce(p_cost, 0) = 0 then 'queued' when attempts")
  expect(code).toContain("attempts = case when p_error = 'time budget' and coalesce(p_cost, 0) = 0 then greatest(attempts - 1, 0) else attempts end,")
  expect(code).toContain("update pipeline.platform_toolset_settings set value = to_jsonb(20000), updated_at = now(),")
  expect(code).toContain("where toolset_key = 'pipeline' and key = 'entry.matrix_slice_chars';")
})
