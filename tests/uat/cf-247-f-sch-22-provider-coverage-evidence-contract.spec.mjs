// Guards: F-SCH per-provider coverage evidence export (Platform Admin S2-Scholarship directive 13 Nov 2026 14:50 §1, §6; Developer Requirements v2.26 F-SCH.11): one read-only, reproducible, dated CSV per run, distinct provider IDs, one disposition per provider from a closed list, never a mutable task register
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('scripts/export/sch-provider-coverage-evidence.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/sch-provider-coverage-evidence.yml', 'utf8')

test('the query is read-only and covers every classified university and every provider with scholarship activity', () => {
  expect(sql).not.toMatch(/\b(insert|update|delete|truncate|alter|create|drop)\b/i)
  expect(sql).toContain('select p.id from catalogue.providers p where security.scholarship_university(p.id)')
  for (const t of ['pipeline.scholarship_discovery_providers', 'pipeline.scholarship_page_candidates', 'pipeline.scholarship_listing_pages', 'scholarship.scholarships'])
    expect(sql).toContain(`union select provider_id from ${t}`)
})

test('one disposition per provider from the closed list, with next action and next retry', () => {
  for (const d of ['published', 'admitted_not_published', 'protected_hold', 'source_found_unprocessed', 'evidence_insufficient', 'current_awards_ineligible_or_domestic', 'searched_none_evidenced', 'website_unknown', 'not_yet_attempted_or_vendor_failure'])
    expect(sql).toContain(`'${d}'`)
  expect(sql).toContain('end disposition')
  expect(sql).toContain('end next_action')
  expect(sql).toContain('least(d.next_discover_at, k.next_read, cv.next_recovery) next_retry')
})

test('the workflow confirms the project, reads in one READ ONLY transaction, and commits only the dated CSV and its md5 to the evidence branch', () => {
  expect(wf).toContain('if [ "$PROJECT_REF" != "${{ vars.SUPABASE_PROJECT_REF }}" ]')
  expect(wf).toContain('-c default_transaction_read_only=on')
  expect(wf).toContain('psql -X -v ON_ERROR_STOP=1 --csv -f scripts/export/sch-provider-coverage-evidence.sql')
  expect(wf).toContain('git push origin sch-coverage-evidence')
  expect(wf).not.toMatch(/git push( -f)? origin (main|HEAD)/)
})
