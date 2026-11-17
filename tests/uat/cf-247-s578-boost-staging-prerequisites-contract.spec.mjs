// Guards: Boost bulk-ingestion prerequisites (Platform Admin 17 Nov 2026 14:12): the staging-boost bucket is private and service-role only (the change refuses a public bucket or a storage policy that anon or authenticated could use); the Boost staging and model-qualification tables keep row-level security on with no grant to anon or authenticated; nothing is switched on (no job, no promotion function, no qualified model)
// CF-247 S578. Migration 20261117152300_cf247_boost_staging_bucket_and_tables. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261117152300_cf247_boost_staging_bucket_and_tables.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the bucket is private and the change refuses a public bucket or a storage policy anon or authenticated could reach', () => {
  expect(code).toMatch(/insert into storage\.buckets \(id, name, public, file_size_limit, allowed_mime_types\)\s*values \('staging-boost', 'staging-boost', false,/)
  expect(code).toContain("on conflict (id) do nothing;")
  expect(code).toContain("if v_public then raise exception 'refused: staging-boost must be private")
  expect(code).toMatch(/roles && array\['anon', 'authenticated', 'public'\]::name\[\]/)
  expect(code).not.toMatch(/create policy/i)
})

test('both tables keep row-level security on, with no grant to anon or authenticated, and each states its purpose', () => {
  for (const t of ['pipeline.boost_inbound_staging', 'pipeline.boost_model_qualifications']) {
    expect(code).toContain(`create table if not exists ${t} (`)
    expect(code).toContain(`alter table ${t} enable row level security;`)
    expect(code).toMatch(new RegExp(`comment on table ${t.replace('.', '\\.')} is`))
  }
  expect(code).toContain('revoke all on pipeline.boost_inbound_staging, pipeline.boost_model_qualifications from anon, authenticated;')
  expect(code).not.toMatch(/grant [^;]*(anon|authenticated)/i)
})

test('nothing is switched on: no job, no function, no qualified model', () => {
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job/)
  expect(code).not.toMatch(/create (or replace )?function/i)
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications/)
  expect(code).toContain("if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'")
})
