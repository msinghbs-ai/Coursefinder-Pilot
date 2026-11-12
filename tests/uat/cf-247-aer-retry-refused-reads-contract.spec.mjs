// Guards: Platform Admin 13 Nov 2026 07:54 ("How does stalled jobs get requeued"): a read the AI provider refused (key limit, credits) was not read, so it is read again at the next run instead of waiting the retry interval, and does not count as a try
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113261500_cf247_aer_retry_refused_reads.sql', 'utf8')

test('the refusal pattern is a setting; only failed reads whose reason matches it skip the retry interval; nothing is deleted', () => {
  expect(M).toMatch(/'aer\.retry_now_error_pattern'[\s\S]*?'text', to_jsonb\('Key limit exceeded\|/)
  expect(M).toContain("'c208bcd0c7695018bba0b63d9d797f4a'")
  expect(M).toContain("or (f.updated_at > now() - s.retry and not (f.state = 'failed' and s.refused <> '' and coalesce(f.reason, '') ~* s.refused))))")
  expect(M).toContain("'454a9271ddc5b436e56ca6056bbee5a8'")
  expect(M).toContain("or count(*) filter (where r.error is null or cfg.refused = '' or r.error !~* cfg.refused) >= cfg.tries")
  expect(M).toMatch(/\('aer\.schedule_daily_max', 0::numeric, 5000::numeric\), \('aer\.v2_shadow_on', 0, 1\)/)
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
