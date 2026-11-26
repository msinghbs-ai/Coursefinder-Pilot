// Guards: DR-19 slice 2 (SS-Programme-Control 26 Nov 2026 21:36 AEDT): operational failures classified by configurable rows and handed back once to the existing AI worker (3-attempt cap kept, manual locks honoured, nothing deleted); realised gain measured; resolution history and field-level consumer delivery in the record trace (presence, not accuracy)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130010000_cf247_s1277_pim_operational_recovery.sql', 'utf8')

test('s1277: refusal wording is configuration, read by one classifier', () => {
  expect(sql).toContain("insert into pipeline.recovery_error_classes (pattern, error_class, root_cause_class, owner, title, repeat_setting, sort)")
  expect(sql).toContain("e.root_cause_class = 'service_limit' and p_reason ilike e.pattern")
  expect(sql).toContain("elsif security.pim_operational_reason_v1(")
})

test('s1277: recovery uses the existing worker, keeps the attempt cap and locks, and deletes nothing', () => {
  expect(sql).toContain("set state = 'ai', attempts = least(e.attempts, 2)")
  expect(sql).toContain("not exists (select 1 from pipeline.manual_locks m where m.entity_id = a.course_id and m.field = a.field)")
  expect(sql).toContain("update pipeline.course_field_absence a set resolved_at = now()")
  expect(sql).not.toMatch(/\bdelete\s+from\b/i)
  expect(sql).not.toMatch(/cron\.schedule/i)
})

test('s1277: the trace reports history and field-level delivery as presence, not accuracy', () => {
  expect(sql).toContain("'resolved_absences'")
  expect(sql).toContain("'change_control_ref', x.change_control_ref")
  for (const d of ['served_and_verified', 'verified_not_served', 'served_not_verified', 'neither']) expect(sql).toContain(`'${d}'`)
  expect(sql).toContain("elsif v_last.state in ('waiting', 'ai', 'leased')")
})
