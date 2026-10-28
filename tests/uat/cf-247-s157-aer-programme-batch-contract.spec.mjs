// Guards: CF-247 AER programme batch (Platform Admin decision 29 Oct 2026 09:57 items 2 and 3): exactly the ten named sources, one governed attempt each through the Read again mechanism (security.aer_reread_v1), a refusal recorded and never retried, earlier partial reads superseded and never approved; one bounded course-level batch through security.course_entry_batch_v1; logged; nothing admitted, dropped or deleted
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029040000_cf247_aer_programme_batch.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the ten named sources, counted; one attempt each through the Read again mechanism; a refusal recorded, not retried', () => {
  for (const u of ['INTL0910_Entry_Qualifications_v07.pdf', 'uwa.edu.au/study/how-to-apply/pathways-and-eligibility/international-and-overseas-qualifications', 'academic-entry-requirements-by-country-guide2.pdf',
    'academic-entry-requirements-listed-by-country.pdf', 'manukau.ac.nz', 'uow.edu.au', 'wintec.ac.nz', 'op.ac.nz', 'lincoln.ac.nz', 'nmit.ac.nz']) expect(code).toContain(u)
  expect(code).toContain("if coalesce(array_length(v_ids, 1), 0) <> 10 then raise exception 'expected exactly the ten named sources")
  expect(code).toContain('v_res := security.aer_reread_v1(r.id, v_reason, v_pa);')
  expect(code).toContain("v_res := jsonb_build_object('refused', sqlerrm);  -- recorded, not retried")
  expect(code.match(/security\.aer_reread_v1\(/g)).toHaveLength(1)
})

test('one bounded course-level batch through the programme; logged; nothing approved, admitted, dropped or deleted', () => {
  expect(code.match(/security\.course_entry_batch_v1\(/g)).toHaveLength(1)
  expect(code).toContain("security.course_entry_batch_v1(null, null, 'AER course-level programme, first batch")
  expect(code).toContain("values ('entry_matrix', 'programme_batch', 'migration 20261029040000',")
  expect(code).not.toMatch(/layer4_review_decide|review_apply|status = 'active'|status = 'approved'/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
