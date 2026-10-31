// Guards: StudySearch decision D5a / SS-010 (Platform Admin 31 Oct 2026 13:30; admin 2026-10-31-studysearch-transformation.md §20, §25): the central enrichment hold (security.enrich_item_held_v1) also holds a course while its page binding is a mismatch (manual bindings excepted), so the standing gap queue stops re-queuing futile items; one md5-guarded edit, nothing else changes
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031040000_cf247_ss010_enrich_mismatch_hold.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('one md5-guarded edit of the central enrichment hold, before and after pinned', () => {
  expect(m).toContain("select pg_temp.edit_once('security.enrich_item_held_v1(uuid,text)', '66be0efc9fd32e4d7920499f90baca07', '688da7aedbb7ee3f09f629b497c25579', array[")
  expect(code(m).match(/select pg_temp\.edit_once\(/g)).toHaveLength(1)
  expect(m).toContain('-- Replaces: security.enrich_item_held_v1')
  expect(m).toContain('-- Retires: nothing')
})

test('a mismatch binding holds the course; a manual binding never does; the existing flag hold is kept as it was', () => {
  expect(m).toContain("select exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.status = 'mismatch' and coalesce(g.basis, '') <> 'manual')")
  expect(m).toContain('      or exists (select 1 from pipeline.enrichment_flags f')
})

test('nothing else changes: no data, schedule, setting, time-out or consumer object', () => {
  const c = code(m)
  const top = c.replace(/\$([a-z]*)\$[\s\S]*?\$\1\$/g, '')
  expect(top).not.toMatch(/^\s*(insert|update|delete)\b/im)
  expect(c).not.toMatch(/statement_timeout|cron\.(schedule|alter_job|unschedule)|platform_toolset_settings|\b(drop|truncate)\b/i)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\.|consumer_api_rebaseline_v1/)
})
