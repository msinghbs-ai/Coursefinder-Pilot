// Guards: Autonomous PIM reader lifecycle for scholarships (SS-Programme-Control 27 Nov 2026 11:27 AEDT; F-OPS.14, F-OPS.16, F-OPS.19), s1304: 0-item listing pages are classed (a help, status or award page is recorded once for the scholarship owner as HELD:NOT_A_LISTING; a listing whose awards were not extracted gets a proposal), a provider configuration (added link hosts, data only) is qualified on stored copies with the existing listing readers (no fetch, no model, no write), activation is its own step and is held (HELD:ACTIVATION_AUTHORITY) because no standing authority covers scholarship reader configurations, an active configuration only adds hosts to the listing read, and outcomes go to the existing recovery knowledge
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const mig = read('supabase/migrations/20261130150000_cf247_s1304_reader_lifecycle_scholarships.sql')
const body = mig.replace(/^--.*$/gm, '')
const ix = read('supabase/functions/coverage-sweep/index.ts')
const sch = read('supabase/functions/coverage-sweep/scholarship.ts')

test('classes: help, status and award pages are not listings; the rest gets a proposal', () => {
  expect(body).toContain("then 'not_a_listing' else 'items_not_extracted' end")
  expect(body).toContain("and p_url like rtrim(l2.url, '/') || '/%')")
  expect(body).toContain("'disposition', 'HELD:NOT_A_LISTING'")
})

test('qualification on stored copies with the existing listing readers; a pass switches nothing on', () => {
  expect(ix).toContain('const n0 = scholarshipListing(html, base, hosts, maxItems).length + awardSections(html, base, labelOpts).length;')
  expect(ix).toContain('const after = scholarshipListing(html, base, [...hosts, ...cand], maxItems);')
  expect(ix).toContain('await rpc("svc_reader_qualify_sch_record", { p_version: q.qualify_version_id, p_listing: q.listing_id, p_result: res })')
  expect(sch).toContain('export function listingCandidateHosts(html: string, baseUrl: string, hosts: string[] = []): string[] {')
  expect(sch).toContain('.filter(([, n]) => n >= 2)')
  const rec = body.slice(body.indexOf('create or replace function public.svc_reader_qualify_sch_record'), body.indexOf('create or replace function public.svc_reader_config_sch_v1'))
  expect(rec).not.toMatch(/enabled = true/)
  expect(rec).toContain("'HELD:READER_RELEASE_REQUIRED'")
})

test('activation is its own step and is held without a standing authority', () => {
  expect(body).toContain("'admin', 'platform', 'the listing gives its award links")
  expect(body).toContain("if k.code is null or not k.auto_eligible then")
  expect(body).toContain("jsonb_build_object('held', 'HELD:ACTIVATION_AUTHORITY', 'held_at', now())")
})

test('an active configuration only adds qualified hosts to the listing read', () => {
  expect(ix).toContain('for (const r of rows) if (schCfg[r.provider_id]?.length) r.hosts = [...(r.hosts || []), ...schCfg[r.provider_id]];')
  expect(body).toContain("select jsonb_object_agg(v.configuration->>'provider_id', v.configuration->'hosts_add')")
})

test('the entry-matrix job runs the academic entry lifecycle step and counts queued samples as due work (s1303 correction)', () => {
  expect(body).toContain("perform security.reader_lifecycle_tick_v1();  -- s1304: the reader lifecycle step")
  expect(body).toContain("v_due := v_due + (select count(*) from pipeline.layer2_source_profile_versions qv")
  expect(body).toContain("<> '68213bf48d54bd0a82db117c708cd2dd' then")
})

test('learning and prevention; no new table; nothing dropped', () => {
  expect(body).not.toMatch(/create table (if not exists )?pipeline\./i)
  expect(body).toContain("'the same listing copies already failed', 'prevented', true")
  expect((body.match(/security\.ops_learning_record_v1\(/g) || []).length).toBeGreaterThanOrEqual(2)
  expect(body.replace(/on commit drop/gi, '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
})
