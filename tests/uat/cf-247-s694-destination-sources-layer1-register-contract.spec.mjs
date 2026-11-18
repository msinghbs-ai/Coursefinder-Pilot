// Guards: destination data sources are Layer 1 Register sources (Platform Admin 18 Nov 2026 22:04, s694): registered by country, run by the standard Layer 1 scheduler and Run now, every artifact in Supabase Storage with a Layer 1 evidence record (source, storage path, SHA-256, fetched_at, licence terms), drafts into destination editions; no side cron.
// CF-247 S694. supabase/migrations-archive/20261118262000_cf247_destination_sources_layer1_register.sql; layer1-destination-geo-loader v1.4.0; layer1-operations-scheduled v1.6.0; layer1-operations-control v1.11.0.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118262000_cf247_destination_sources_layer1_register.sql', 'utf8')
const L = fs.readFileSync('supabase/functions/layer1-destination-geo-loader/index.ts', 'utf8')
const S = fs.readFileSync('supabase/functions/layer1-operations-scheduled/index.ts', 'utf8')
const C = fs.readFileSync('supabase/functions/layer1-operations-control/index.ts', 'utf8')

test('five Australian destination sources in the existing Layer 1 registry; Fair Work paused; no new table or function', () => {
  for (const label of ['ABS Regional Population', 'BOM Climate Statistics (IDCJCM0037)', 'Jobs and Skills Australia (JSA) OSCA & Table 1',
    'Department of Home Affairs Student & Graduate Visa Rules', 'Fair Work Ombudsman National Minimum Wage']) expect(M).toContain(`('${label}',`)
  expect(M).toContain("insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)")
  expect(M).toContain("insert into pipeline.layer1_source_operations(")
  expect(M).toContain("raise exception 'post-check: Fair Work stays paused';")
  expect(M).not.toMatch(/create table|create or replace function (?!security\.destination_source_evidence_v1)/i)
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})

test('the standard Layer 1 scheduler and Run now load a destination source; the side jobs are off and retiring', () => {
  expect(S).toContain('if(system==="DESTINATION"){')
  expect(S).toContain('invokeStatWorker(url,serviceKey,"layer1-destination-geo-loader",{mode,scope:md.destination_scope||"",trigger:"layer1_schedule",source_id:ctx.source_id})')
  expect(C).toContain('if(system==="DESTINATION"){')
  expect(C).toContain('system==="DESTINATION"?"layer1-destination-geo-loader"')
  expect(L).toContain('if (internal && internal === key) return "layer1";')
  expect(M).toContain("perform cron.alter_job(job_id := r.jobid, active := false);")
  expect(M).toContain("raise exception 'post-check: the side jobs are off';")
})

test('every artifact goes to Supabase Storage and its evidence record names the Layer 1 source, fetched_at and licence terms', () => {
  expect(L.match(/service\.storage\.from\("evidence"\)\.upload\(/g).length).toBeGreaterThanOrEqual(4)
  expect(L).toContain('fileSha256')
  expect(M).toContain("insert into pipeline.evidence_artifacts(evidence_type, source_url, storage_path, content_hash, mime_type, metadata, review_state, source_id)")
  expect(M).toContain("jsonb_build_object('layer1_source_id', v_src, 'licence_terms', v_licence, 'fetched_at', now())")
  expect(M.replace(/\n-- /g, ' ')).toContain('all Destination Data sources must be registered in Layer 1 Register by country and ingest via standard Layer 1 schedule')
})
