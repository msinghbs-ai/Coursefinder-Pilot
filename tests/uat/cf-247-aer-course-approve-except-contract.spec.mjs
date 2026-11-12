// Guards: Platform Admin 12 Nov 2026 22:25 ("Procced with automatic approve") and 13 Nov 2026 09:30 (fix the shared cause): machine Approve except for course entry reads holds back only the rows that fail a row rule or that the completeness gate names at row level; every other rule still holds the whole read
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113271500_cf247_aer_course_machine_approve_except.sql', 'utf8')

test('only row-level failures are held back; other gate classes and every item rule still hold the read', () => {
  expect(M).toContain("'1eb645492dd067e699decef07da6402f'")
  expect(M).toContain("'3a5de30e542b3fdff123bbe90bda7dda'")
  expect(M).toContain("'aer.machine_except_on'")
  expect(M).toContain("security.aer_e13_class_v1(v_gate) = 'row_level'")
  expect(M).toContain('v_gate := security.course_entry_gate_v1(i.id, v_ex);')
  expect(M).toContain("'rule', 'all_rows_held'")
  expect(M).not.toMatch(/\$o\$[^$]*(manual_lock|earlier_rejection|no_bound_page|identity_not_admitted|audit_sample|page_changed_since_read)/)
  expect(M).toContain("jsonb_build_object('exclude_row_ids', v->'checks'->'exclude_row_ids')")
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
