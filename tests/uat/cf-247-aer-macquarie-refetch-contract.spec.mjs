// Guards: Decision 276 workstream B (source recovery): an official PDF refused once is fetched again directly, only Macquarie's three Academic Entry PDFs, with the control event the Platform Admin's attach action writes
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('only the three blocked Macquarie Academic Entry PDFs go back to found, with a recorded control event', () => {
  const m = fs.readFileSync('supabase/migrations/20261113083100_cf247_aer_macquarie_refetch.sql', 'utf8')
  expect(m).toContain("s.provider_id = '188103a5-1aba-4f99-bd3e-0416659086d3' and s.status = 'failed' and s.error = 'blocked_pdf'")
  expect(m).toMatch(/set status = 'found', attempts = 0, error = null/)
  expect(m).toContain("'source_attach_again'")
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
