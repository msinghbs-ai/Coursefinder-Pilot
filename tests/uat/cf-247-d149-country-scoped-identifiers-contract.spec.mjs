import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 149: official register identifiers are typed, country-scoped identifiers; no country columns.
test('Decision 149: register codes mirrored into country-scoped identifier tables',async()=>{
  const m=fs.readFileSync('supabase/migrations-archive/20260928080000_d149_country_scoped_identifiers.sql','utf8')
  expect(m).toContain('create table if not exists ref.identifier_schemes(')
  for(const row of ["('cricos','provider','AU'","('cricos','course','AU'","('nzqa','provider','NZ'","('nzqa','course','NZ'"])expect(m).toContain(row)
  expect(m).toContain('create trigger trg_mirror_course_registration_identifier after insert or update or delete on catalogue.course_registrations')
  expect(m).toContain('create trigger trg_mirror_provider_registration_identifier after insert or update or delete on catalogue.provider_registrations')
  // no country-specific column is added to a shared table
  expect(m).not.toMatch(/alter table catalogue\.\w+ add column/i)
})

test('Zoho course lookup applies the Layer 4 block to course-code matches',async()=>{
  const m=fs.readFileSync('supabase/migrations-archive/20260928080100_zoho_lookup_block_precedence.sql','utf8')
  expect(m).toContain("and (lower(d.course_stable_key)=lower(btrim(p_identifier))")
  expect(m).toContain("1d30db8739355cb224376b6922344c9f")
})
