// Guards: SS-Programme-Control 26 Nov 2026 15:09 AEDT, P0 item 3 (first applicable live production verification of Holmesglen lean-md-v3), on the Platform Admin 25 Nov 2026 18:26 AEDT converter fix
// s1197: one stored Holmesglen case is re-checked by the existing recall job under worker v1.0.47; stored copies only, $0, nothing admitted; s1198 switches the job off again.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129124500_cf247_s1197_lean_md_v3_live_check.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1197: the one Holmesglen case recorded by s1152 is copied into a new run of the existing recall check', () => {
  expect(MIG).toContain("v_run constant text := 's1197-lean-md-v3-holmesglen-2026-11-26'; v_from constant text := 's1152-entry-miss-detail-2026-11-25';")
  expect(MIG).toContain("where (d->>'raw') ~* '&lt;br')")
  expect(MIG).toContain("if v_n <> 1 then raise exception")
  expect(MIG).toContain("perform cron.alter_job(job_id := v_job, active := true);")
})

test('s1197: no AI, route, admission, setting or new job, and nothing dropped', () => {
  expect(code).not.toMatch(/ai_service_routes|on_demand_open|layer4_review_items|course_entry_requirements|platform_toolset_settings|cron\.schedule|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: a cron job was created', 'post-check: more than 140 active cron jobs', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
