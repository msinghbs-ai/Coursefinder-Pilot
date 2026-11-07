// Guards: Platform Admin mandate 7 Nov 2026 21:57 (AER technical holds: classify and correct the actual blockers; a printed requirement is not lost to its score field; held reads are recovered from stored records through the existing E13 and D-R2 checks with no AI read and no spend; a cut read is eligible only when the university's row limit fits it; Layer 4 admission authority is kept; aer.schedule_layer4_max and every switch are unchanged). The behaviour runs on PostgreSQL 16 by tests/fixtures/aer-technical-holds/run.sh (live md5s checked, applied twice). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const A = fs.readFileSync('supabase/migrations/20261107130000_cf247_aer_stored_read_recovery.sql', 'utf8')
const B = fs.readFileSync('supabase/migrations/20261107130100_cf247_aer_row_limit_rule.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const run = fs.readFileSync('tests/fixtures/aer-technical-holds/run.sh', 'utf8')
const fx = fs.readFileSync('tests/fixtures/aer-technical-holds/fixtures.sql', 'utf8')
const rule = fs.readFileSync('tests/fixtures/aer-technical-holds/rule.sql', 'utf8')

test('the two live functions are edited under their live md5 with a recorded after md5, and nothing else is edited', () => {
  expect(A).toMatch(/edit_once\('security\.enrich_entry_record_v1\(bigint,jsonb\)', '7faf2de4c2afe0a671f8f54c4a140fe4', '[0-9a-f]{32}'/)
  expect(A).toMatch(/--   security\.enrich_entry_record_v1\(bigint,jsonb\) 7faf2de4c2afe0a671f8f54c4a140fe4 -> [0-9a-f]{32}/)
  expect(B).toMatch(/edit_once\('security\.aer_recovery_rule_v1\(uuid\)', 'b194475a46186bc674a3364816a8b06b', '[0-9a-f]{32}'/)
  expect(B).toMatch(/--   security\.aer_recovery_rule_v1\(uuid\) b194475a46186bc674a3364816a8b06b -> [0-9a-f]{32}/)
  expect(run).toContain('rebuilt enrich_entry_record_v1 differs from live')
  expect(run).toContain('loaded rule differs from live')
  // PR #875 is not depended on: its functions are not edited here
  expect(A + B).not.toMatch(/edit_once\('security\.(aer_schedule_held_v1|progress_measure_v1)/)
})

test('a requirement is never dropped for its score field; a repeated requirement is one row', () => {
  expect(A).toContain("'note', 'score_without_basis'")
  expect(A).toContain('v_score := null; v_basis := null;')
  expect(fx).toContain('the number without a printed basis is not stored')
  expect(fx).toContain('nothing is dropped as score_without_basis')
  expect(fx).toContain('the repeated requirement is one row')
})

test('recovery from stored records goes through the existing governed path: no AI, no fetch, nothing approved, history kept, caps from settings', () => {
  expect(A).toContain('security.course_entry_correction_check_v1(p_item, r.entity_id, pgp.url, v_all, v_rest)')
  expect(A).toContain('security.enrich_entry_record_v1(v_enrich')
  expect(A).toContain("'ai', false, 'scraper', false")
  expect(code(A)).not.toMatch(/course_entry_read_enqueue_v1|firecrawl|openrouter/i)
  expect(code(A)).not.toMatch(/insert into pipeline\.layer4_decisions|set status = 'active'/)
  for (const k of ['aer.replay_on', 'batch.aer_replay', 'aer.replay_per_provider', 'aer.replay_daily_max', 'aer.replay_scan']) expect(A).toContain(`'${k}'`)
  expect(code(A)).not.toMatch(/aer\.schedule_layer4_max|aer\.schedule_daily_max/)
  expect(fx).toContain('nothing is approved or admitted')
  expect(fx).toContain('no read is queued: no AI, no page fetch')
  expect(fx).toContain('one place for each university this run')
  expect(fx).toContain('the daily cap is counted over 24 hours')
})

test('the Diploma of Commerce shape needs a row limit of 9, and the live range of the setting (1 to 10) is documented as a decision', () => {
  expect(fx).toContain('S2 (Diploma of Commerce shape) needs a row limit of 9')
  expect(fx).toContain('the 9 stored rows become a new waiting item')
  expect(rule).toContain('a university limit above the setting range (10) is ignored')
  expect(A).toContain('LIVE RANGE: entry.max_rows_per_course has range 1 to 10')
})

test('a cut read is eligible only when the row limit fits it (not when a setting was merely touched)', () => {
  expect(B).toContain("v_now >= v_need and v_now > coalesce(nullif(v_rlim, 0), (r.proposed_value->>'rows')::int, 0)")
  expect(code(B)).toContain('v_now >= v_need')
  expect(rule).toContain('a limit of 9 is short of 10')
  expect(rule).toContain('the authority line names the 10 rows needed')
})

test('matrix rows with the provider rank stored as the minimum are put right while waiting, with the original kept; admitted rows are untouched', () => {
  expect(A).toContain("status = 'proposed' and m.grade_scale = 'rank'")
  expect(A).toContain('pipeline.aer_row_repairs')
  expect(fx).toContain('an admitted row is never touched')
  expect(fx).toContain('the original is kept')
  expect(fx).toContain('AFTER: the run passes D-R3')
})

test('governance: job catalogued with no number in its command, tables commented, Replaces and Retires present, nothing dropped, consumer API untouched', () => {
  expect(A).toMatch(/insert into pipeline\.automation_catalogue\(jobname[^)]*\) values\s*\('aer-replay'/)
  expect(A).toContain("cron.schedule('aer-replay', '33 * * * *', $c$select security.aer_replay_v1(false)$c$)")
  expect(A).toContain('comment on table pipeline.aer_replay_checks')
  expect(A).toContain('comment on table pipeline.aer_row_repairs')
  for (const m of [A, B]) {
    expect(m).toMatch(/^-- Replaces: /m)
    expect(m).toMatch(/^-- Retires: /m)
    expect(m).not.toMatch(/\bdrop (table|function|column|view|schema)\b|\bdelete from\b|\btruncate\b/i)
    expect(m).not.toMatch(/website_v2_|website_edge_|zoho_edge_|api\.website/)
  }
})
