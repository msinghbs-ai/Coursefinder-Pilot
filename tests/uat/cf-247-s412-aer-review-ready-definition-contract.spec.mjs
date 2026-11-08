// Guards: Platform Admin directive 8 Nov 2026 (reconcile the AER review pack with the Layer 4 Inbox: one definition of ready to decide, Approve except and stale items included; new replayed items assessed promptly; no decision, approval or admission by the platform)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261108040000_cf247_aer_review_ready_single_definition.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/aer-review-ready/run.sh', 'utf8')
const fx = fs.readFileSync('tests/fixtures/aer-review-ready/fixtures.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)

test('three live functions are edited under their live md5 with a recorded after md5, and nothing else is edited', () => {
  expect(M).toMatch(/--   security\.layer4_readiness_tick_v1\(\) 06e5f4394b0c2831404fc7a766d669c4 -> [0-9a-f]{32}/)
  expect(M).toMatch(/--   security\.work_review_ready_v1\(text\) 6d90b76b58f0593f7a8d6af038c8c916 -> [0-9a-f]{32}/)
  expect(M).toMatch(/--   security\.aer_provider_load_v1\(\) 3f0aede5f6f670fa75aeeb8640f4dc63 -> [0-9a-f]{32}/)
  expect(M).not.toContain('00000000000000000000000000000000')
  expect(C).toContain("pg_temp.edit_once('security.layer4_readiness_tick_v1()', '06e5f4394b0c2831404fc7a766d669c4'")
  expect(C).toContain("pg_temp.replace_def('security.work_review_ready_v1(text)', '6d90b76b58f0593f7a8d6af038c8c916'")
  expect(C).toContain("pg_temp.replace_def('security.aer_provider_load_v1()', '3f0aede5f6f670fa75aeeb8640f4dc63'")
  // the Inbox's own source and the Controller's replay are called or left alone, never edited
  expect(C).toContain("('security.aer_settlement_v1(uuid)', '49fb7e5071453b7eff4cf343d80b5737')")
  expect(C).not.toMatch(/create or replace function security\.(aer_settlement_v1|aer_route_v1|layer4_aer_queue_v1|layer4_aer_university_summary_v1|aer_replay_[a-z_0-9]+|course_entry_max_rows_v1)/)
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(run).toContain('definitions this change edits or calls (loaded = live 8 Nov 2026)')
})

test('one definition: the scheduling counts read the Inbox settlement through aer_review_ready_v1; Approve except counts, stale does not, a matrix run from another page is not a duplicate', () => {
  expect(C).toContain('with s as (select * from security.aer_settlement_v1(p_provider))')
  expect(C).toContain('w.settlement = \'ready\'')
  expect(C).toMatch(/when w\.route = 'review' then 'complete' else 'approve_except'/)
  expect(C).toContain("array['flagged', 'same_identity']")
  expect(C).toContain("array['audience', 'not_requirement', 'other_programme', 'joined']")
  // duplicates: a course is one decision; a matrix run is one decision per source page
  expect(C).toContain("partition by i.entity_id, i.field_code, case when i.field_code = 'course_entry_first_read' then null else i.proposed_value->>'url' end")
  expect(C).toContain("from security.aer_review_ready_v1(null) r, c where p_category = 'aer'")
  expect(C).toContain("when q.settlement = 'stale' then 'stale'")
  expect(C).toContain("from security.aer_review_ready_v1(null) q join pipeline.work_review_categories rc on rc.category = 'aer'")
  // the part that is a person's ruling stays a ruling: a lock is reported, ready is not changed by it
  expect(C).toContain("security.pipeline_list_v1('entry.supersede_lock_fields'")
  expect(fx).toContain('a lock on the course page address is reported (url_locked) and does not change whether the item is ready')
  expect(fx).toContain('the counter and the Inbox differ only by true duplicates')
  expect(fx).toContain('a second matrix run of the university from another page is NOT a duplicate')
  expect(fx).toContain('a read of a page the course is no longer bound to is stale, not ready')
  expect(fx).toContain('every university\'\'s "ready to decide" equals the single definition')
  // the 600 limit and every setting are untouched
  expect(C).not.toMatch(/aer\.schedule_layer4_max|aer\.schedule_daily_max|insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/)
  expect(fx).toContain('the limit (aer.schedule_layer4_max) is unchanged')
})

test('readiness for new items: the run and the replay path classify through one function; settings, not numbers; records only', () => {
  expect(C).toContain('perform security.layer4_readiness_item_v1(r.id, v_use_gate, v_pace, v_kinds);')
  expect(C).toContain('create or replace function security.layer4_readiness_items_v1(p_items uuid[])')
  expect(C).toContain("security.pipeline_num_v1('layer4.gate_batch', 20)")
  expect(C).toContain("security.pipeline_num_v1('layer4.readiness_on', 1) < 1")
  expect(C).toContain("security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)")
  expect(C).not.toMatch(/insert into pipeline\.layer4_decisions|insert into catalogue\.course_entry_requirements|update catalogue\.course_entry_requirements|update pipeline\.layer4_review_items|status = 'active'/)
  expect(run).toContain('every item classified identically before and after the change')
  expect(fx).toContain('one call classifies it and evaluates its gate')
  expect(fx).toContain('a second call within the recheck time does not run the gate again')
  expect(fx).toContain('no admission and no decision was written')
  expect(fx).toContain('no item was approved or rejected')
})

test('the fixtures mirror live: NOT NULL columns of the tables read or written are enforced, nulls the seed left are filled, and the consumer API is not touched', () => {
  for (const col of ["'coverage_course_pages', 'provider_id'", "'layer4_item_readiness', 'readiness'", "'manual_locks', 'entity_id'", "'aer_read_supersessions', 'source_url'"]) expect(run).toContain(col)
  expect(run).toContain('live NOT NULL columns mirrored')
  expect(C).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
})

test('the pack for the Platform Admin is issued with the change and keeps suggestions apart from decisions', () => {
  const pack = fs.readFileSync('docs/paste/aer-review-pack-20261108.md', 'utf8')
  expect(pack).toContain('Nothing here is a decision')
  expect(pack).toContain('held unless individually authorised')
  expect(pack).toMatch(/Approve except/)
  expect(pack).toMatch(/Stale/)
})
