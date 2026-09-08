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
})
