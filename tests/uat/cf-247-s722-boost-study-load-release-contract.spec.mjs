// Guards: Study-load release after the label split (Platform Admin 19 Nov 2026 05:40 and 06:55 item 2, s722): rejected, failed and promotion-refused study-load items of active courses with no study load and no manual lock, on the course's own latest unshared stored page, are released once for the v1.0.24 reader; nothing that holds a study load is touched, and nothing is admitted except through the existing page check and promotion
// CF-247 S722. Migration 20261119063000_cf247_s722_study_load_release_after_label_split. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119063000_cf247_s722_study_load_release_after_label_split.sql', 'utf8')

test('releases only items the claim will read again for a course with no study load', () => {
  expect(M).toContain("where x.lane = 'study_load' and x.entity = 'course' and c.study_load is null and c.lifecycle_status = 'active'")
  expect(M).toContain("l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')")
  expect(M).toContain('where i.latest_ev = i.evidence_id')
  expect(M).toContain("(i.state in ('rejected', 'failed') or (i.state = 'verified' and i.last_promo = 'refused'))")
  expect(M).toContain('group by e.content_hash having count(distinct e.entity_id) > 1)')  // the claim's own shared-page set
  expect(M).toContain('and not exists (select 1 from shared h where h.content_hash = a.content_hash))')
  expect(M).toContain("set state = 'released', note = left('s722 (19 Nov 2026)")
})

test('no overwrite: the claim guard and the post-checks', () => {
  expect(M).toContain("not like '%c.study_load is null%'")
  expect(M).toContain("raise exception 'post-check: a released item belongs to a course that holds a study load'")
  expect(M).not.toMatch(/update catalogue\.|insert into catalogue\.|create (table|or replace function)|cron\.schedule/i)
})
