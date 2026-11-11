// Guards: F-AER.09 held country tables read by older readers are read again with the current reader, and a stale empty-read request closes once the provider's table is live (Platform Admin 11 Nov 2026 23:32 "Proceed", workstream A)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261112183100_cf247_aer_older_reads_and_empty_read_close.sql', 'utf8')

test('only the four older reads are read again, never an item a person holds, and nothing is admitted', () => {
  for (const s of ['74306034-c24a-4ed8-a859-1770edd7ab0b', '58c60102-e549-4482-be03-7b6358059ada', '18e64f94-d2a5-479f-846b-1c5db07cc65b', '01139439-b952-4a53-891c-60e593c01cd1']) expect(m).toContain(s)
  // the five reads made today by the same reader (UTS, CSU, Curtin, Wollongong, VU) are not in it: the same reader would repeat their drops
  for (const s of ['7675875e-11f2-4dc5-a89c-b7a87e4c6f6d', '7fd6e509-324a-4039-9706-a863e2bcc6d6', '30ceba77-2972-400e-b51c-e6139964a2f5', 'c9a5c1d5-8334-4fd6-89f7-f194deb5ad53', 'a84c16f4-7ada-4319-b900-b0e07eacabcf']) expect(m).not.toContain(s)
  expect(m).toMatch(/claimed_at is not null or li\.assigned_to is not null/)
  expect(m).toContain('public.admin_entry_matrix_reread(ids,')
  expect(m).not.toMatch(/^\s*(update|delete|insert)\b/im)
})

test('the empty-read recheck also clears when the provider table is live; the edit is md5-guarded and applies once', () => {
  expect(m).toContain("'e0c47bda3839960013077b57328c1d55'")
  expect(m).toContain("or exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = i.provider_id and m.status = 'active')")
  expect(m).toMatch(/\], array\[1\]\);/)
  expect(m).toContain("security.har_aer_recheck_v1(395)")
})
