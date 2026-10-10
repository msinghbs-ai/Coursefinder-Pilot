import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('per-field 80% coverage panel and its hourly snapshot are wired end to end', () => {
  const ui = fs.readFileSync('src/course-coverage.jsx', 'utf8')
  expect(ui).toContain('export const COVERAGE_TARGET=80')
  expect(ui).toContain('data-field-target')
  expect(ui).toContain("['intakes','Intakes / start dates'],['english','English requirements'],['fee','Provider tuition (fee year)']")
  expect(ui).toContain('data?.field_sources')
  const read = fs.readFileSync('supabase/migrations-archive/20261006001884_cf247_course_coverage_read_field_sources.sql', 'utf8')
  expect(read).toContain('76426134291383868b10c64a677f2a0c')
  expect(read).toContain("'field_sources'")
  const build = fs.readFileSync('supabase/migrations-archive/20261006001882_cf247_course_field_source_build_function.sql', 'utf8')
  expect(build).toContain('on conflict (course_id) do update')
  const sched = fs.readFileSync('supabase/migrations-archive/20261006001883_cf247_course_field_source_prune_and_schedule.sql', 'utf8')
  expect(sched).toContain("'55 * * * *'")
  const table = fs.readFileSync('supabase/migrations-archive/20261006001880_cf247_course_field_source_snapshot.sql', 'utf8')
  expect(table).toContain('enable row level security')
  expect(table).toContain('revoke all on pipeline.course_field_source from public, anon, authenticated')
})
