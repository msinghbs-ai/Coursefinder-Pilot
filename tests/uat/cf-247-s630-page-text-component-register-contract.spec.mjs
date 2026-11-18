// Guards: telemetry flag UNREGISTERED on job page-text (Platform Admin 18 Nov 2026 11:54): the page-text job, its table and functions are in pipeline.component_register beside its catalogue row, and nothing else changes (the standing catalogue rule itself is guarded by s42).
// CF-247 S630. supabase/migrations/20261118142000_cf247_page_text_component_register.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118142000_cf247_page_text_component_register.sql', 'utf8')

test('page-text and its objects are registered once, additively', () => {
  for (const [k, n] of [['job', 'page-text'], ['table', 'pipeline.page_text_conversions'], ['function', 'public.svc_page_text_next_v1'], ['function', 'public.svc_page_text_record_v1']]) expect(M).toContain(`('${k}', '${n}',`)
  expect(M).toContain("where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);")
  expect(M).toContain("raise exception 'post-check: page-text catalogue row'")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate |update |alter )/im)
  expect(M).toMatch(/-- Replaces: nothing\./)
  expect(M).toMatch(/-- Retires: nothing\./)
})
