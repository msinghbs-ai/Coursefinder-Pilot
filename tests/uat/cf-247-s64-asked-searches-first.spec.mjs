// Guards: CF-247 (S64) v2.15.290: course-page searches a person asked for run for any provider and go first (Platform Admin 18 Oct 2026 22:25 "proceed with recommended choice");
// CF-247 (S64) v2.15.290: course-page searches a person asked for run for any provider and go first (Platform Admin 18 Oct 2026 22:25
// "proceed with recommended choice"); the Adapter builder guide reads whether they will run.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql = fs.readFileSync('supabase/migrations/20261018140000_cf247_asked_searches_first.sql', 'utf8')

test('server: guarded edits, asked-for searches exempt from the focus rule and first, every other check kept', () => {
  expect(sql).toContain("'8b6c6f829d6269a0448ed9e6faff5aa0'")
  expect(sql).toContain("'9c20438a5f48d19e7d163a8ad2e3b603'")
  expect(sql).toContain('(security.enrich_focus_v1(s.provider_id) or s.requested_at is not null)')
  expect(sql).toContain('order by (s.requested_at is null), s.requested_at, security.fc_provider_tier_v1(s.provider_id), ')
  expect(sql).toContain("update pipeline.course_link_search set requested_at = now() where provider_id = v_c.provider_id and state = ''queued'' and requested_at is null;")
  expect(sql).toContain('CREATE OR REPLACE FUNCTION public.admin_course_search_queue(p_provider_id uuid)')
  expect(sql).toMatch(/-- Replaces: .+\n-- Retires: nothing/)
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/website_v2_|website_edge_|zoho_edge_|\bapi\./)
})

test('source: the guide reads the queue', () => {
  expect(fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')).toContain("supabase.rpc('admin_course_search_queue',{p_provider_id:b.provider_id})")
})
