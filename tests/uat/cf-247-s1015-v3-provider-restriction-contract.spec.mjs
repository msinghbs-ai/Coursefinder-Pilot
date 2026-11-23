// Guards: Platform Admin 23 Nov 2026 23:47 AEDT (S1-RM-Design overnight brief item 2: REQ-118 restriction_mode and restriction_markets as an additive Website API v3 read; Decision 277 v3 open to additions; G3 v2 frozen)
// s1015: the v3 provider item adds restriction_mode and restriction_markets from pipeline.provider_representation, keeps every earlier key, and touches no v2 object.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124000000_cf247_s1015_v3_provider_restriction.sql', 'utf8')

test('s1015: v3 provider item adds the two restriction keys and keeps the earlier ones', () => {
  expect(MIG).toContain("|| security.provider_restriction_v3_v1(v_provider);")
  expect(MIG).toContain("'restriction_mode', r.restriction_mode, 'restriction_markets', to_jsonb(r.restriction_markets)")
  for (const k of ['scholarships_page_url', 'scholarships_last_reviewed_at', 'accreditations', 'accreditation_crown', "'locality'", "'campus_id'"]) expect(MIG).toContain(k)
  expect(MIG).toContain("md5(pg_get_functiondef('public.website_v3_provider_item(jsonb)'::regprocedure)) <> 'c3262f054919709d935989793b8297a9'")
  expect(MIG).not.toMatch(/representation_status'/)
})

test('s1015: G3 guarded before and after, locks and cron unchanged, nothing dropped or deleted', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('post-check: the number of active cron jobs changed')
  expect(MIG).not.toMatch(/website_v2|zoho_edge|cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
