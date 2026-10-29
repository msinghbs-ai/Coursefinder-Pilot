// Guards: CF-247 AER programme batch 2 (Platform Admin mandate 29 Oct 2026 12:23 B2 and B3): exactly the thirteen approved sources, one governed attempt each through the Read again mechanism, refusals recorded and not retried, earlier partial items superseded and never approved; one course batch through the programme (credit-floor refusal inside the function); DP020 read once through the existing one-course mechanism; logged; nothing admitted, dropped or deleted
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029050000_cf247_aer_programme_batch_2.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the thirteen approved sources, counted; one attempt each through the Read again mechanism; a refusal recorded, not retried', () => {
  expect((code.match(/'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/g) || []).filter((x) => !x.startsWith("'63ba56cb") && !x.startsWith("'b365fde8"))).toHaveLength(13)
  expect(code).toContain("if coalesce(array_length(v_ids, 1), 0) <> 13 then raise exception 'expected exactly the thirteen named sources")
  expect(code).toContain('v_res := security.aer_reread_v1(r.id, v_reason, v_pa);')
  expect(code).toContain("v_res := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried")
  expect(code.match(/security\.aer_reread_v1\(/g)).toHaveLength(1)
})

test('one course batch through the programme, DP020 once through the one-course mechanism; logged; nothing approved or admitted', () => {
  expect(code.match(/security\.course_entry_batch_v1\(/g)).toHaveLength(1)
  expect(code).toContain("security.course_entry_read_enqueue_v1('b365fde8-d003-4ef6-80c3-4136fbd5587a'::uuid, v_pa,")
  expect(code).toContain("if not exists (select 1 from pipeline.field_enrich_items f where f.course_id = 'b365fde8-d003-4ef6-80c3-4136fbd5587a' and f.field = 'entry_requirements') then")
  expect(code).toContain("values ('entry_matrix', 'programme_batch', 'migration 20261029050000',")
  expect(code).not.toMatch(/layer4_review_decide|review_apply|status = 'active'|status = 'approved'|credit_floor_usd'\s*,\s*to_jsonb/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
