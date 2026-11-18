// Guards: destination editions are fixed once published (security.destination_row_guard_v1) and page facts are read monthly (Platform Admin 18 Nov 2026 15:32 and 17:55): a published edition is never written to; a new fact or a changed value goes into a complete successor edition; an unchanged JSA file loads nothing.
// CF-247 S692. supabase/migrations/20261118256000_cf247_destination_page_facts_successor_editions.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118256000_cf247_destination_page_facts_successor_editions.sql', 'utf8')

test('pass 1 reads every fact and writes no rule; pass 2 decides per edition', () => {
  const p1 = M.slice(M.indexOf('-- pass 1'), M.indexOf('-- pass 2'))
  expect(p1).not.toMatch(/insert into destination\.study_rules|update destination\.study_rules/)
  expect(M).toContain('continue;  -- a published edition with nothing new: no row is touched')
})

test('a change on a published edition opens a complete successor edition and moves the facts to it', () => {
  expect(M).toContain("v_label := e.edition_label || ' (read ' || v_day || ')';")
  expect(M).toContain("values (e.country_id, e.domain, v_label, current_date, 'draft', e.source_url, e.source_owner, e.attribution_text, e.terms_status, now())")
  expect(M).toContain('-- a copy of each published rule not read this time, quote and evidence kept, so the successor is complete')
  expect(M).toContain("update destination.page_facts set edition_label = s.edition_label, updated_at = now() where edition_label = e.edition_label and status = 'active';")
})

test('the JSA workbook: an unchanged file loads nothing; a changed file goes into a successor', () => {
  expect(M).toContain("elsif v_je.status = 'published' and exists (select 1 from pipeline.evidence_artifacts a where a.source_url = j->>'file_url' and a.content_hash = j->>'sha256') then")
  expect(M).toContain("v_jsa := v_jsa || jsonb_build_object('status', 'unchanged', 'reason', 'the published edition was loaded from this same file; nothing written');")
})

test('nothing dropped or deleted, a dry run writes nothing, the consumer API untouched', () => {
  expect(M).toContain("raise exception 'post-check: a dry run wrote rows'")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/website_v2_|website_edge_|zoho_edge_|website_api_v2_/)
})

test('regression (fifth live run): no SQL alias shares the loop variable fd, and pass 2 is exercised by a rolled-back post-check', () => {
  const F = fs.readFileSync('supabase/migrations/20261118265000_cf247_destination_page_facts_alias_fix.sql', 'utf8')
  expect(F.replace(/--[^\n]*/g, '')).not.toMatch(/jsonb_array_elements\(v_found\) fd\b/)  // code only, not the header that tells the story
  expect(F).toContain("raise exception 'post-check rollback' using errcode = 'P0001';")
  expect(F).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
