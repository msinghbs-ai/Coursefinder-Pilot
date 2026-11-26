// Guards: Platform Admin approval of s1240 A1 to A3 (relayed by SS-Programme-Control 26 Nov 2026 17:01 AEDT; decision pack s1240, S1-AER-Claude): CQU and AIBT host aliases, one provider each; Excelsia guide source retired
// s1260: two aliases added to aer.provider_host_aliases with their reason, the Excelsia guide source set inactive, and the two declined matrix decisions decided again by the existing machine admission.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129150000_cf247_s1260_s1240_aliases_and_retire.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1260: exactly the two approved aliases, never AIBT International', () => {
  expect(MIG).toContain("'f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6:delivery-cqucontenthub.stylelabs.cloud'")
  expect(MIG).toContain("'eb9e3903-6d92-4502-a2b3-51cb231b21fc:aibtglobal.edu.au'")
  expect(code).not.toContain('fc6f01a7-66fb')
  expect(MIG).toContain("raise exception 'post-check: AIBT International was aliased'")
})

test('s1260: the Excelsia guide is set inactive, not deleted; decisions go back through the existing machine admission', () => {
  expect(MIG).toContain("update pipeline.entry_matrix_sources set status = 'inactive'")
  expect(MIG).toContain("security.aer_matrix_machine_admit_v1(v_item, 'run')")
  expect(code).not.toMatch(/\bdelete from\b|truncate |cron\.schedule|website_v2_|layer4_review_items\s+set/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
})
