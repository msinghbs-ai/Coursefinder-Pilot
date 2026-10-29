// Guards: CF-247 AER course-level programme batch 4 (Platform Admin mandate 29 Oct 2026 12:23 B3): one course batch through the programme, the credit-floor refusal inside the function recorded and not retried; logged; nothing read again, approved, admitted, dropped or deleted
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029100000_cf247_aer_course_batch_4.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('one course batch through the programme; a refusal recorded, not retried; logged; nothing else', () => {
  expect(code.match(/security\.course_entry_batch_v1\(/g)).toHaveLength(1)
  expect(code).toContain("v_batch := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried")
  expect(code).not.toMatch(/aer_reread_v1|course_entry_read_enqueue_v1/)
  expect(code).toContain("values ('entry_matrix', 'programme_batch', 'migration 20261029100000',")
  expect(code).not.toMatch(/layer4_review_decide|review_apply|status = 'active'|status = 'approved'|credit_floor_usd'\s*,\s*to_jsonb/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
