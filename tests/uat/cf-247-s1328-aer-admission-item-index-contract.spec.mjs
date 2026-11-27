// Guards: SS-Programme-Control 28 Nov 2026 07:05 AEDT item 3 (zero-yield course-admission pass resolved through DR-19, eligibility verified first); Standing Mandate 21 Nov 2026 (a verified fix ships live); no drop or delete by an applied migration
// CF-247 s1328. supabase/migrations/20261130223500_cf247_s1328_aer_admission_item_index.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130223500_cf247_s1328_aer_admission_item_index.sql', 'utf8')

test('the course pass reads each item\'s latest machine decision through an index on (review_item_id, created_at desc)', () => {
  expect(sql).toContain('create index if not exists aer_machine_admissions_item_created_idx\n  on pipeline.aer_machine_admissions (review_item_id, created_at desc);')
  expect(sql).not.toMatch(/create (or replace )?function|alter function|pipeline_num_v1|cron\.schedule/)
})

test('it changes no decision, drops nothing and checks the frozen surface, locks, Layer 4 and cron', () => {
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|\btruncate\s+/i)
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  for (const s of ['active cron jobs changed', 'manual locks changed', 'Layer 4 decisions changed']) expect(sql).toContain(s)
  expect(sql).toMatch(/-- Replaces: nothing\.\n-- Retires: nothing\./)
})
