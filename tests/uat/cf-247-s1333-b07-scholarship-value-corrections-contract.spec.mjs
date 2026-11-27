// Guards: SS-Programme-Control 28 Nov 2026 07:21 and 08:46 AEDT P0 (Batch 07 scholarship value corrections, safely revised); CLAUDE.md no drop or delete by an applied migration; manual locks immutable
// CF-247 s1333. supabase/migrations/20261201014000_cf247_s1333_b07_scholarship_value_corrections.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201014000_cf247_s1333_b07_scholarship_value_corrections.sql', 'utf8')

test('each award changes only from its exact wrong state; a corrected award is skipped; anything else stops', () => {
  for (const s of ['award_percentage = 65', 'award_percentage = 80', 'award_percentage = 85', 'award_amount = 36000', 'award_duration_basis is null']) expect(sql).toContain(s)
  for (const n of ['#1', '#2', '#3', '#4', '#5', '#7']) expect(sql).toContain(`'b07 ${n}: unexpected state`)
})

test('it deletes nothing, stops on a manual lock, keeps Griffith Academic Merit withdrawn and publication unchanged', () => {
  expect(sql).not.toMatch(/\bdelete\s+from\b|\bdrop\s+(table|function|view|column|index)\b|\btruncate\s+/i)
  expect(sql).toContain('manual lock(s) on these awards; nothing changed')
  expect(sql).toContain("is distinct from 'withdrawn' then")
  expect(sql).toContain('a lifecycle or publication status changed')
})

test('savings refreshed and one audit row; frozen surface, cron and locks checked', () => {
  expect(sql).toContain('perform scholarship.refresh_course_financial_calculations(null, v_ids[n])')
  expect(sql).toContain("'b07_value_corrections_migration'")
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toMatch(/-- Replaces: nothing\.\n-- Retires: nothing\./)
})
