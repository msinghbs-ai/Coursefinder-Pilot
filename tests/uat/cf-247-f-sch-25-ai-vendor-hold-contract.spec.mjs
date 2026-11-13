// Guards: F-SCH.15 scholarship AI lane on a vendor-side block (Platform Admin S2-Scholarship directive 13 Nov 2026 23:07, Priority 3): a key limit or no-credit answer holds the lane to one probe call instead of closing the queue, the first success re-queues what the block closed, and never-decided pages are read before re-reads of earlier decided ones
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113373500_cf247_sch_ai_vendor_hold_and_fresh_first.sql', 'utf8')

test('md5-guarded edits of the fire and the picker', () => {
  expect(m).toContain("select pg_temp.edit_n('security.scholarship_ai_fire_v1()', '3d48dc20a4e9a571266f3de243a31545', array[")
  expect(m).toContain("select pg_temp.edit_n('public.svc_scholarship_ai_next(integer)', '8b24b21a104963db0e2a9429ca03b627', array[")
})

test('a vendor block holds the lane to one probe call; the first success after it re-queues what it closed', () => {
  expect(m).toContain("and (e.error like 'HTTP 403%limit%' or e.error like 'HTTP 402%');")
  expect(m).toContain('if v_okat is null then v_max := least(coalesce(v_max, 3), 1);  -- fixed: one probe call while the vendor refuses')
  expect(m).toContain('else perform security.scholarship_ai_vendor_requeue_v1(')
  expect(m).toContain("where q.state = 'done' and q.done_at >= p_since")
  expect(m).toContain('where e.id = q.extraction_id  -- the item')
  expect(m).toContain("set state = 'queued', attempts = 0, next_try_at = now(), done_at = null, leased_until = null")
  expect(m).toContain("security.pipeline_num_v1('batch.sch_ai_vendor_requeue', 500)")
})

test('never-decided pages before re-reads of decided candidates, within the same order', () => {
  expect(m).toContain('left join pipeline.scholarship_page_candidates cd on cd.id = q.candidate_id')
  expect(m).toContain("q.step desc, (cd.admit_status is not null), q.id offset 0) o")
})

test('the manual pause is replaced by the automatic hold', () => {
  expect(m).toContain('update pipeline.scholarship_ai_extract_settings set calls_at_once = 5')
  expect(m).toContain("where id = 1 and calls_at_once = 0;")
})
