// Guards: CF-247 (S68) 19 Oct 2026: prepare removal of replaced course-page snapshots ("Archive, then remove");
// CF-247 (S68) 19 Oct 2026: prepare removal of replaced course-page snapshots ("Archive, then remove"); nothing is removed by the change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql = fs.readFileSync('supabase/migrations/20261019020000_cf247_evidence_purge_prepare.sql', 'utf8')

test('newest snapshot per course page never a candidate; referenced snapshots kept; cascade-only references ignored', () => {
  expect(sql).toContain('where s.rn > 1')
  expect(sql).toContain("update pipeline.evidence_purge set state = 'kept'")
  expect(sql).toContain("k.confdeltype = 'c'")
  expect(sql).toContain("security.pipeline_num_v1('batch.evidence_purge_check', 3000)")
})

test('housekeeping: nothing removed, catalogued job, comment, guards', () => {
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/delete from pipeline\.evidence_artifacts/i)
  expect(sql).toMatch(/-- Replaces: nothing\n-- Retires: nothing/)
  expect(sql).toContain('comment on table pipeline.evidence_purge')
  expect(sql.indexOf('insert into pipeline.automation_catalogue')).toBeLessThan(sql.indexOf("select cron.schedule('evidence-purge-prepare'"))
})
