// Decision 205: institution-level sources (fee schedules, English policies, academic calendars). Nothing is written to
// the catalogue by the worker; fee rows need the course code and the amount on the same row and a basis from the heading.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')

test('worker: provider_facts searches, reads as evidence, parses fee rows; budgets respected', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('if (mode === "provider_facts") {')
  expect(w).toContain('await useFc("provider_facts_search", it.provider_id, it.query)')
  expect(w).toContain('await useFc("provider_facts_scrape", it.provider_id, it.url)')
  expect(w).toContain('if (codes.length !== 1) continue;')
  expect(w).toContain('if (!basis) return;')
  expect(w).not.toMatch(/provider_facts[\s\S]{0,4000}svc_coursefacts_apply_record/)
})

test('database: sources, queue for top 150, fee rows kept (never deleted), no catalogue writes', () => {
  const m = read('supabase/migrations/20261001178000_cf247_provider_fact_sources.sql')
  expect(m).toContain('group by c.provider_id order by count(*) desc limit 150')
  expect(m).toContain("update pipeline.provider_fee_rows set current = false where source_id = p_id and current;")
  expect(m.toLowerCase()).not.toContain('delete from')
  expect(m).not.toContain('catalogue.course_fees')
  for (const f of ['svc_provider_facts_search_next(int)', 'svc_provider_facts_read_next(int)'])
    expect(m).toContain(`grant execute on function public.${f} to service_role;`)
})
