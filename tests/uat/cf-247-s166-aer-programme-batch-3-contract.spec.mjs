// Guards: CF-247 AER programme batch 3 (Platform Admin mandate 29 Oct 2026 12:23 B1 and B3): exactly the four corrected sources (Federation, Wollongong, Otago Polytechnic, UWA), one governed attempt each through the Read again mechanism after worker v0.52.0, refusals recorded and not retried, earlier incomplete items superseded and never approved; one course batch through the programme (credit-floor refusal inside the function); logged; nothing admitted, dropped or deleted
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029090000_cf247_aer_programme_batch_3.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the four corrected sources, counted; one attempt each through the Read again mechanism; a refusal recorded, not retried', () => {
  expect((code.match(/'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/g) || []).filter((x) => !x.startsWith("'63ba56cb"))).toHaveLength(4)
  expect(code).toContain("if coalesce(array_length(v_ids, 1), 0) <> 4 then raise exception 'expected exactly the four named sources")
  expect(code).toContain('v_res := security.aer_reread_v1(r.id, v_reason, v_pa);')
  expect(code).toContain("v_res := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried")
  expect(code.match(/security\.aer_reread_v1\(/g)).toHaveLength(1)
  expect(m).toContain('coverage-sweep-worker-v0.52.0')
})

test('one course batch through the programme; logged; nothing approved or admitted', () => {
  expect(code.match(/security\.course_entry_batch_v1\(/g)).toHaveLength(1)
  expect(code).not.toContain('course_entry_read_enqueue_v1')
  expect(code).toContain("values ('entry_matrix', 'programme_batch', 'migration 20261029090000',")
  expect(code).not.toMatch(/layer4_review_decide|review_apply|status = 'active'|status = 'approved'|credit_floor_usd'\s*,\s*to_jsonb/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
