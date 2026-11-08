// Guards: Platform Admin directive 8 Nov 2026 (AER: resolve QUT matrix mapping and the shared-page cases through source and identity validation; locked courses and ambiguous matches held; history preserved; nothing auto-admitted; no paid recovery; no AI calls in tests), G2, G3 via s57, "a passing qualification never switches anything on by itself".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const A = fs.readFileSync('supabase/migrations/20261108030000_cf247_aer_shared_page_rejected_binding.sql', 'utf8')
const B = fs.readFileSync('supabase/migrations/20261108030100_cf247_aer_course_table_matrix_route.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const run = fs.readFileSync('tests/fixtures/aer-qut-shared/run.sh', 'utf8')
const sc = fs.readFileSync('tests/fixtures/aer-qut-shared/scenarios.sql', 'utf8')
const sc2 = fs.readFileSync('tests/fixtures/aer-qut-shared/scenarios2.sql', 'utf8')
const paste = fs.readFileSync('docs/paste/AER-20261108-shared-page-44-classification.md', 'utf8')

test('the shared-page function is edited once, under its live md5, with a recorded after md5 and an exact-once check', () => {
  expect(A).toContain("v_before constant text := 'cc037bb72a83595406b1246570d1e977'")
  expect(A).toMatch(/--   security\.course_entry_shared_page_v1\(uuid\) cc037bb72a83595406b1246570d1e977 -> [0-9a-f]{32}/)
  expect(A).toContain('the edit must apply exactly once')
  expect(A).toContain('already applied')
  expect(run).toContain('shared_page_v1 differs from live')
  expect(run).toContain('cc037bb72a83595406b1246570d1e977')
  expect(A).toMatch(/Replaces: security\.course_entry_shared_page_v1/)
  expect(A).toContain('-- Retires: nothing')
})

test('a refused binding stops counting only for a strongly identified, unlocked course; the lists are settings and an empty list restores the old rule', () => {
  for (const k of ['entry.shared_page_count_statuses', 'entry.shared_page_own_bases']) expect(A).toContain(`'${k}'`)
  expect(A).toContain("g1.status is distinct from 'bound'")
  expect(A).toContain("pipeline.manual_locks l where l.entity = 'course' and l.entity_id = g1.course_id and l.field in ('official_url', 'course_url')")
  for (const n of ['SP4', 'SP5', 'SP6', 'SP7', 'SP11', 'SP12', 'SP13']) expect(sc).toContain(`'${n} `)
  expect(sc).toContain('an AMBIGUOUS course on the page still counts')
  expect(sc).toContain('a course with a hand lock keeps the old rule')
  expect(sc).toContain('an empty own-basis list restores the old rule exactly')
  expect(code(A)).not.toMatch(/layer4_decisions|status = 'approved'|update pipeline\.layer4_review_items|delete from|drop (table|function)/i)
})

test('the QUT move maps stored pages held, under a count and md5 guard, by a Platform Admin function, with an audit event and no fetch, AI or spend', () => {
  expect(B).toContain("v_n = 23 and v_md5 = 'e132941111515af718e4822f24275a03'")
  expect(B).toContain("'inactive'")
  expect(B).toContain("read_via")
  expect(B).toContain("'stored'")
  expect(B).toContain("'fetch', false, 'ai', false")
  expect(B).toContain('count and md5 guard')
  expect(B).toContain("current_user <> 'postgres'")
  expect(B).toContain("insert into pipeline.admin_control_events")
  expect(B).toContain('revoke all on function security.aer_matrix_route_attach_v1')
  expect(code(B)).not.toMatch(/firecrawl|openrouter|entry_matrix_fire_v1|http_post|net\.http/i)
  expect(code(B)).not.toMatch(/update pipeline\.layer4_review_items|delete from|drop (table|function|trigger)|truncate/i)
  for (const n of ['R2 ', 'R2b ', 'R3 ', 'R4 ', 'R5 ', 'R5b ', 'QA1 ', 'QA2 ', 'QA3 ']) expect(sc + sc2).toContain(n)
})

test('locked courses are never mapped unless named; the 8-row read is not a candidate; the old waiting items are untouched', () => {
  expect(B).toContain("p_include_items")
  expect(B).toContain("l.field in ('official_url', 'course_url')")
  expect(B).toContain("x.cut >= security.pipeline_num_v1('aer.row_limit_matrix_rows', 30)")
  expect(sc).toContain('a locked course is a candidate only when named')
  expect(sc).toContain('no waiting item was changed')
  expect(sc2).toContain('none of the 14 locked and not the 8-row read')
  expect(sc2).toContain('all 38 QUT-shaped waiting items are still pending, unchanged')
})

test('reading a mapped page is a separate, capped, deliberate step guarded by the AI stop; the cap is a setting', () => {
  expect(B).toContain("'aer.matrix_route_activate_max'")
  expect(B).toContain("security.ai_use_allowed_v1('entry_matrix')")
  expect(B).toContain('count guard: % held pages would be activated')
  expect(sc).toContain('activation while the AI guard is stopped raises')
  expect(sc).toContain('exactly the cap (2) sources are now read')
  // the migration does not call the activation
  expect(code(B)).not.toMatch(/perform security\.aer_matrix_route_activate_v1/)
})

test('a row from a mapped source is that course\'s row; the stamp runs before the identity hash and changes no consumer object', () => {
  expect(B).toContain("create trigger provider_entry_matrix_a_route before insert")
  expect(B).toContain("new.matrix_kind := 'course_minimum'")
  expect(sc).toContain('the row hash includes the course')
  expect(sc).toContain('a row that already names a course keeps it')
  expect(sc).toContain('the consumer API is untouched')
  expect(code(A + B)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings|create (or replace )?(view|function) (public|api)\./i)
  expect(code(A + B)).not.toMatch(/alter table catalogue\./i)
})

test('housekeeping: new table commented, RLS on, nothing deleted, fixtures mirror live and run on a scratch server only', () => {
  expect(B).toContain('comment on table pipeline.aer_matrix_route')
  expect(B).toContain('enable row level security')
  expect(B).toContain('-- Retires: nothing')
  expect(run).toContain('refusing a Supabase project database')
  expect(run).toContain("DB=${AQS_DB:-g_aer_qut_shared}")
  expect(run).toContain('applied twice; the second run changed nothing')
  expect(code(run + sc + sc2)).not.toMatch(/openrouter|firecrawl|api\.anthropic|curl /i)
})

test('the classification for the Platform Admin lists every class with counts and keeps the locked and ambiguous items held', () => {
  expect(paste).toContain('19 + 11 + 14 = 44')
  expect(paste).toContain('Stay held unless individually authorised')
  expect(paste).toContain('near-duplicate')
  expect(paste).toContain('Nothing in this file has been applied')
})
