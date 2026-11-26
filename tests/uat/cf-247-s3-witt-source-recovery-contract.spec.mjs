// Guards: AER-FU-09 NZ official-host source acquisition, provider identity, G3, existing fetch pipeline and immutable evidence requirement.
// This only registers a verified official candidate; it does NOT read the PDF,
// replace the failed previous URL, approve entry minima, or enable a new job.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql = fs.readFileSync('supabase/migrations/20261129031000_cf247_s3_witt_2026_official_source.sql','utf8')
test('Five NZ source holders gain eight idempotent, official and course-scoped source candidates without a new pipeline',()=>{
  expect(sql).toContain("security.aer_source_check_v1(")
  expect(sql).toContain("v->>'ownership' <> 'official_host'")
  expect(sql).toContain("c.iso_alpha2='NZ'")
  expect(sql).toContain('on conflict(provider_id,url) do nothing')
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).toContain('https://www.witt.ac.nz/study/administration-and-business-management/business-and-management/bachelor-of-applied-management-level-7')
  expect(sql).toContain('https://www.nzma.ac.nz/courses/pharmacy-overview/combined-international')
  expect(sql).toContain('https://www.nzma.ac.nz/courses/pharmacy-overview/introduction-to-pharmacy-level-3')
  expect(sql).toContain('https://www.whitecliffe.ac.nz/wp-content/uploads/2026/03/Entry-requirements-3.pdf')
  expect(sql).toContain('https://nzse.ac.nz/wp-content/uploads/2026/11/InternationalProspectus-2027-NZSEG.pdf')
  expect(sql).toContain('https://www.openpolytechnic.ac.nz/qualifications-and-courses/op7411-graduate-certificate-in-business/tab/QT02/')
  expect(sql).toContain('https://www.openpolytechnic.ac.nz/qualifications-and-courses/op700101-bachelor-of-business/tab/QT02/')
  expect(sql).toContain('https://www.openpolytechnic.ac.nz/qualifications-and-courses/nz3466-new-zealand-diploma-in-library-and-information-studies-level-5/tab/QT02/')
  expect(sql).toContain('src(provider_id,url,title)')
  expect(sql).toContain('No row here is an admission')
  expect(sql).not.toMatch(/(?:create\s+extension|create\s+function|cron\.schedule|alter\s+table|entry\.countries)/i)
})
