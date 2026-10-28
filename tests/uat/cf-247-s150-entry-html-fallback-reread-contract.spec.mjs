// Guards: CF-247 AER programme bounded re-read after worker v0.50.2 (Platform Admin consolidated mandate 28 Oct 2026 23:22; the 28 Oct deploy-order lesson): an entry source takes no stored markdown copy; only markdown sources whose reads wait on no person are fetched again, and only no-answer runs with no Layer 4 item get their tries back, each bounded, history kept; nothing dropped
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029007000_cf247_aer_html_fallback_reread.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('md5-guarded: an entry source takes no markdown copy', () => {
  expect(code).toContain("select pg_temp.edit_n('security.entry_matrix_use_stored_v1()', '1d00979372ff27a93725485ac31819ca'")
  expect(code).toContain("and a.mime_type is distinct from 'text/markdown'$n$]], array[1]);")
})

test('markdown sources fetched again only when no person is deciding on them; bounded; passes the refresh interval as never read', () => {
  expect(code).toContain("update pipeline.entry_matrix_sources s set status = 'found', attempts = 0, error = null, read_at = null, updated_at = now()")
  expect(code).toContain("and exists (select 1 from pipeline.evidence_artifacts e where e.id = s.evidence_id and e.mime_type = 'text/markdown')")
  expect(code).toContain("where r.source_id = s.id and li.status in ('pending', 'approved'));")
  expect(code).toContain("if v_n > 6 then raise exception")
})

test('no-answer runs with no Layer 4 item read once more, history kept, bounded; nothing dropped or deleted', () => {
  expect(code).toContain("'reason', 'read again after worker v0.50.2 (no-answer reason named): ' || left(coalesce(error, ''), 200),")
  expect(code).toContain("where state = 'failed' and review_item_id is null")
  expect(code).toContain("if v_n > 5 then raise exception")
  expect(code).not.toMatch(/\b(drop|delete from|truncate|insert into)\b/i)
  expect(code).not.toMatch(/cron\.schedule/)
  expect(m).toMatch(/^-- Replaces: security\.entry_matrix_use_stored_v1/m)
  expect(m).toMatch(/^-- Retires: /m)
})
