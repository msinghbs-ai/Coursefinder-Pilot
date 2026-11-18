// Guards: S670 AER shared-page rule for hand-bound courses (Platform Admin 18 Nov 2026 17:52, session S2-BOOST-AER): a binding the identity check refused is not a claim on the page of a course a person bound by hand or hand-locked; a page another course is bound or ambiguous on, and every variant twin, stays held; no AER v1 threshold changes.
// CF-247 S670. Migration 20261118220000_cf247_aer_shared_page_hand_bound; database scenarios tests/fixtures/aer-hand-bound (workflow aer-hand-bound-test.yml).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118220000_cf247_aer_shared_page_hand_bound.sql', 'utf8')
const PREV = fs.readFileSync('supabase/migrations/20261108030000_cf247_aer_shared_page_rejected_binding.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/aer-hand-bound/run.sh', 'utf8')
const sc = fs.readFileSync('tests/fixtures/aer-hand-bound/scenarios.sql', 'utf8')
const data = fs.readFileSync('tests/fixtures/aer-hand-bound/data.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/aer-hand-bound-test.yml', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('the function is replaced in place: one clause, under the live md5 of 18 Nov, exactly once, with the after md5 recorded and checked by the database run', () => {
  expect(M).toContain("v_before constant text := '7b43d0c61419ec08ea2fbb2889b1f444'")
  expect(PREV).toContain('7b43d0c61419ec08ea2fbb2889b1f444')  // the md5 the 8 Nov migration recorded as its result is the one this edit starts from
  expect(M).toMatch(/--   security\.course_entry_shared_page_v1\(uuid\) 7b43d0c61419ec08ea2fbb2889b1f444 -> [0-9a-f]{32}\n/)
  expect(M).toContain('the edit must apply exactly once')
  expect(M).toContain('already applied')
  expect(run).toContain('7b43d0c61419ec08ea2fbb2889b1f444 -> $AFTER')
  expect(run).toContain('shared_page_v1 differs from live')
  expect(M).toMatch(/-- Replaces: security\.course_entry_shared_page_v1/)
  expect(M).toContain('-- Retires: nothing')
  // G3 stays 75 functions and 48 tables: no new function, table, view or trigger
  expect(code(M)).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger|materialized)/i)
})

test('the hand-lock rule is a setting created at 0, and 1 restores the rule of 8 Nov; the basis list gains manual only where it still holds the 8 Nov default', () => {
  expect(M).toContain("'entry.shared_page_hand_lock_holds'")
  expect(M).toMatch(/'number', '0'::jsonb, 0, 1, 'on\/off'/)
  expect(M).toContain("or (security.pipeline_num_v1('entry.shared_page_hand_lock_holds', 0) >= 1")
  expect(M).toContain("and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = g1.course_id and l.field in ('official_url', 'course_url'))))")
  expect(M).toContain(`set value = '["cricos_code", "nzqa_code", "adapter_code", "exact_title", "title_level", "manual"]'::jsonb`)
  expect(M).toContain(`and value = '["cricos_code", "nzqa_code", "adapter_code", "exact_title", "title_level"]'::jsonb`)
  expect(sc).toContain('HB11 the switch at 1 restores the hand-lock rule of 8 Nov')
  expect(sc).toContain('HB12 the switch at 1 and the 8 Nov basis list restore 8 Nov exactly')
})

test('only refused bindings stop counting: a bound or ambiguous course on the page, a pace twin and a weak basis all stay held', () => {
  // the clause that counts bound and ambiguous bindings is not edited
  expect(M.split('do $edit$')[1].split('end $edit$')[0]).not.toContain('entry.shared_page_count_statuses')
  for (const n of ['HB1 after', 'HB2 ', 'HB3 ', 'HB4 ', 'HB5 ', 'HB6 ', 'HB7 ', 'HB8 ', 'HB9 ', 'HB10 ', 'HB13 ', 'HB14 ']) expect(sc).toContain(`'${n}`)
  expect(sc).toContain('a pace twin stays held: both twins are bound')
  expect(data).toContain("'Diploma of Business (Standard)', 'bound', 'cricos_code'")
  expect(data).toContain("'Diploma of Business (Accelerated)', 'bound', 'cricos_code'")
  expect(sc).toContain('another BOUND course on the page still counts for a hand-bound course')
  expect(sc).toContain('an AMBIGUOUS course on the page still counts for a hand-bound course')
  expect(sc).toContain('the refused course is not released')
})

test('AER v1 stays frozen: no threshold, reader, word list, decision or row is touched; the change is audited', () => {
  expect(code(M)).not.toMatch(/aer\.machine_min_confidence|aer\.machine_min_quote_chars|aer\.matrix_machine_min_confidence|aer\.machine_mode|aer\.machine_audit_pct/)
  expect(code(M)).not.toMatch(/layer4_decisions|update pipeline\.layer4_review_items|update catalogue\.|insert into catalogue\.|delete from|drop (table|function)|truncate/i)
  expect(code(M)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings|create (or replace )?(view|function) (public|api)\./i)
  expect(M).toContain('insert into pipeline.admin_control_events')
  expect(M).toContain("'authority', 'Platform Admin 18 Nov 2026 17:52 (S2-BOOST-AER)'")
  expect(sc).toContain('the migration wrote one audit event and decided nothing')
})

test('the database scenarios run on an isolated PostgreSQL only, twice-applied, in CI for this migration and its fixtures', () => {
  expect(run).toContain('refusing a Supabase project database')
  expect(run).toContain('DB=${AHB_DB:-g_aer_hand_bound}')
  expect(run).toContain('applied twice; the second run changed nothing')
  expect(code(run + sc + data)).not.toMatch(/openrouter|firecrawl|api\.anthropic|curl /i)
  expect(wf).toContain('supabase/migrations/20261118220000_cf247_aer_shared_page_hand_bound.sql')
  expect(wf).toContain('tests/fixtures/aer-hand-bound/**')
  expect(wf).toContain('bash tests/fixtures/aer-hand-bound/run.sh')
  expect(wf).toContain('postgres:16-alpine')
})
