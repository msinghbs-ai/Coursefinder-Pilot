// Guards: PC-20261128-NO-ROUTINE-DATA-PR (one reusable configuration-first route, not per-provider patches) and the on-demand rule (Pilot CLAUDE.md: work a session asks for is opened with security.on_demand_open_v1)
// CF-247 s1365. A provider page added with public.admin_provider_central_page (a next-year academic calendar) is read on demand by mode
// provider_facts_read: only the named sources, claimed with read_next's rules, through the read, storage, parse and proposal path mode
// provider_facts uses. No search, no new job or setting, D11 jobs untouched; each Firecrawl call still needs an open on-demand request.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261201171000_cf247_s1365_provider_facts_read_named.sql'
const WORKER = 'supabase/functions/coverage-sweep/index.ts'

test('the named claim keeps every claim rule of svc_provider_facts_read_next and adds only the id filter', () => {
  const m = fs.readFileSync(MIG, 'utf8')
  expect(m).toMatch(/create or replace function public\.svc_provider_facts_read_ids_v1\(p_ids uuid\[\]\)/)
  expect(m).toMatch(/where f\.id = any\(p_ids\)/)
  for (const rule of [
    "f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id)",
    "f.kind in ('english_policy', 'intake_calendar')",
    "security.pipeline_num_v1('retry.provider_facts_attempts', 3)",
    'security.provider_fact_refusal_v1',
    "security.pipeline_num_v1('retry.provider_facts_refusal_hours', 6)",
    'security.provider_hidden_v1',
    'for update skip locked',
    "set status = 'reading', attempts = f.attempts + 1",
  ]) expect(m).toContain(rule)
  expect(m).toMatch(/'service_role required'/)
  expect(m).toMatch(/revoke all on function public\.svc_provider_facts_read_ids_v1\(uuid\[\]\) from public, anon, authenticated/)
  expect(m).toMatch(/grant execute on function public\.svc_provider_facts_read_ids_v1\(uuid\[\]\) to service_role/)
})

test('the migration changes no job, schedule, setting or data and asserts locks and active jobs unchanged', () => {
  const m = fs.readFileSync(MIG, 'utf8')
  expect(m).toMatch(/^-- Replaces: nothing\.$/m)
  expect(m).toMatch(/^-- Retires: nothing\.$/m)
  expect(m).not.toMatch(/cron\.(schedule|alter_job|unschedule)/)
  expect(m).not.toMatch(/platform_toolset_settings/)
  expect(m).not.toMatch(/^\s*(insert|update|delete)\s/im)
  expect(m).toMatch(/active jobs or manual locks changed/)
})

test('mode provider_facts_read reads only named ids, with no search, through the shared reader', () => {
  const w = fs.readFileSync(WORKER, 'utf8')
  const start = w.indexOf('if (mode === "provider_facts_read") {')
  expect(start).toBeGreaterThan(0)
  const block = w.slice(start, w.indexOf('\n    }\n', start))
  expect(block).toContain('rpc("svc_provider_facts_read_ids_v1", { p_ids: ids })')
  expect(block).toContain('await readFactDocs(docs)')
  expect(block).toMatch(/ids required/)
  expect(block).not.toMatch(/fcx\.search|svc_provider_facts_search_next|svc_provider_facts_read_next/)
  // the scheduled mode uses the same reader, so the two cannot drift apart
  const sched = w.slice(w.indexOf('if (mode === "provider_facts") {'), start)
  expect(sched).toContain('await readFactDocs(docs)')
  expect(w.match(/const readFactDocs = async/g)).toHaveLength(1)
})

test('the shared reader keeps the on-demand Firecrawl gate, Layer 2 storage and the calendar proposal for a person', () => {
  const w = fs.readFileSync(WORKER, 'utf8')
  const r = w.slice(w.indexOf('const readFactDocs = async'), w.indexOf('if (mode === "provider_facts") {'))
  expect(r).toContain('await useFcWhy("provider_facts_scrape", it.provider_id, it.url)')
  expect(r).not.toMatch(/useFcWhy\("provider_facts_scrape", it\.provider_id, it\.url, true\)/)  // never anyProvider: an on-demand request must cover it
  expect(r).toMatch(/layer2\/\$\{it\.country \|\| "XX"\}\/provider-facts\//)
  expect(r).toContain('rpc("svc_provider_policy_record"')
  expect(r).toContain('calendarStarts(md)')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v1\.0\.6[6-9]"/)  // s1372 moved the worker to v1.0.67; the s1365 line stays in its history
  expect(w).toMatch(/\/\/ v1\.0\.66 \(28 Nov 2026, CF-247 s1365/)
})
