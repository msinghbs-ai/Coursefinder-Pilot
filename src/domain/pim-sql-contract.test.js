import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const here=dirname(fileURLToPath(import.meta.url))
const migration=readFileSync(resolve(here,'../../supabase/migrations/20260908032500_course_detail_pim_payload.sql'),'utf8')

describe('course detail PIM SQL contract',()=>{
 it('keeps governed nested JSON outside recursive null stripping',()=>{
  const stripStart=migration.indexOf('jsonb_strip_nulls(jsonb_build_object(')
  const valueAppend=migration.indexOf("case when av.value_json is not null then jsonb_build_object('value_json', av.value_json)")
  const optionAppend=migration.indexOf("jsonb_build_object('option_labels', coalesce(")
  expect(stripStart).toBeGreaterThanOrEqual(0)
  expect(valueAppend).toBeGreaterThan(stripStart)
  expect(optionAppend).toBeGreaterThan(valueAppend)
  const strippedOuterSegment=migration.slice(stripStart,valueAppend)
  expect(strippedOuterSegment).not.toContain("'value_json'")
  expect(strippedOuterSegment).not.toContain("'option_labels'")
 })

 it('selects preferred single values within locale and channel partitions',()=>{
  expect(migration).toContain('avp.locale is not distinct from av.locale')
  expect(migration).toContain('avp.channel_code is not distinct from av.channel_code')
  expect(migration).toContain('av.locale nulls first, av.channel_code nulls first')
 })

 it('scopes embedded option labels to the value locale with global fallback only',()=>{
  expect(migration).toContain('(ao.locale is not distinct from av.locale or ao.locale is null)')
  expect(migration).toContain('(av.locale is not null or ao.locale is null)')
  expect(migration).toContain('(ao.locale is not distinct from av.locale) desc')
  expect(migration).toContain('select distinct on (ao.code)')
 })
})