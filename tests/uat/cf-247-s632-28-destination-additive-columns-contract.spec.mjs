// Guards: 28-destination schema lock (Platform Admin 18 Nov 2026 12:21): national quality ratings and employment-by-industry series are stored in the existing canonical tables by additive columns and checks only (no new table, consumer API unchanged at 75 functions and 48 relations, nothing dropped); the CHECK replacements go to the Platform Admin as a paste file.
// CF-247 S632. supabase/migrations/20261118150000_cf247_28_destination_additive_columns.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118150000_cf247_28_destination_additive_columns.sql', 'utf8')

test('ratings and industry series are additive columns on existing tables', () => {
  for (const c of ['rating', 'rating_period']) expect(M).toContain(`alter table catalogue.provider_accreditations add column if not exists ${c} text;`)
  expect(M).toContain("alter table destination.career_outcomes add column if not exists series_kind text not null default 'occupation';")
  for (const c of ['industry_scheme text', 'industry_code text', 'industry_title text', 'employment_count numeric']) expect(M).toContain(`alter table destination.career_outcomes add column if not exists ${c};`)
  expect(M).toContain("check (series_kind = 'occupation' or (industry_scheme is not null and industry_code is not null and industry_title is not null))")
  expect(M).toContain("raise exception 'post-check: the consumer API surface changed'")
})

test('no table is created, nothing is dropped, no CHECK is replaced here', () => {
  expect(M).not.toMatch(/create table/i)
  expect(M).not.toMatch(/drop (table|constraint|column|function)|alter column [a-z_]+ drop not null/i)
  expect(M).not.toMatch(/^\s*(delete from|truncate )/im)
  expect(M).toMatch(/-- Replaces: nothing\./)
  expect(M).toMatch(/-- Retires: nothing\./)
})
