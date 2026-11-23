// Guards: Platform Admin 23 Nov 2026 20:38 AEDT (S1-RM-Design: REQ-118 provider-level representation_status, restriction_mode and restriction_markets per the approved contract; REQ-110 grade scale rows only from an official source; G3 consumer API frozen)
// s1011: provider representation is an Admin-only, reason-logged table with the include/exclude/none rule; the grade scale seed holds only the seven CBSE rows from Circular 24/2010.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123220000_cf247_s1011_provider_representation_and_cbse_grade_scale.sql', 'utf8')

test('s1011: restriction mode and markets follow one rule, entered with a reason and logged', () => {
  expect(MIG).toContain("restriction_mode in ('include', 'exclude', 'none')")
  expect(MIG).toContain("restriction_mode = 'none' and cardinality(restriction_markets) = 0")
  expect(MIG).toContain("representation_status in ('represented', 'direct', 'not_represented')")
  expect(MIG).toContain('INVALID_INPUT: a reason is required')
  expect(MIG).toContain('pipeline.provider_representation_events')
  expect(MIG).toContain('unknown market code(s)')
})

test('s1011: Admin only, never served to a consumer, no anon access', () => {
  expect(MIG).toContain('revoke all on pipeline.provider_representation from public, anon, authenticated;')
  expect(MIG).toContain('revoke all on function public.admin_provider_representation_save_v1(uuid, jsonb) from public, anon;')
  expect(MIG).toContain('revoke all on function public.admin_provider_representation_read_v1(uuid) from public, anon;')
  expect(MIG).not.toMatch(/website_v\d|zoho_edge|create or replace function api\./i)
})

test('s1011: only the seven CBSE rows are seeded, each from the official circular', () => {
  expect(MIG).toContain('https://www.cbse.gov.in/circulars/cir24-2010.pdf')
  expect(MIG).toContain('round(v.gp * 9.5, 2)')
  expect((MIG.match(/\(\d+, '[A-D][12]?', '\d+-\d+'\)/g) || []).length).toBe(7)
  expect(MIG).toContain("post-check: the CBSE rows are not seven")
})

test('s1011: G3 guarded before and after, locks and cron unchanged, no job, nothing dropped or deleted', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('post-check: the number of active cron jobs changed')
  expect(MIG).not.toMatch(/cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
