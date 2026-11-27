// Guards: Autonomous PIM reader lifecycle (SS-Programme-Control 27 Nov 2026 11:27 AEDT; F-OPS.14, F-OPS.16, F-OPS.19; Master Plan §6.3 and §6.8), s1303: a held entry-matrix template is detected, an active configuration is reused or a configuration (data only: registered reading.entry_* overrides and the address country) is proposed in the existing versioned Layer 2 source profiles, qualified on stored copies by the same worker code with deterministic readers only (no model, no fetch, no spend), switched on only by a separate activation step under the standing authority its knowledge pattern records, and every outcome is kept in the existing recovery knowledge so the same stored copies are never proposed again after a failure
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const mig = read('supabase/migrations/20261130143000_cf247_s1303_reader_lifecycle_aer.sql')
const body = mig.replace(/^--.*$/gm, '')
const ix = read('supabase/functions/coverage-sweep/index.ts')
const rc = read('supabase/functions/coverage-sweep/reader-config.ts')

test('store: versioned Layer 2 source profiles, created switched off; no new table', () => {
  expect(body).not.toMatch(/create table (if not exists )?pipeline\./i)
  expect(body).toContain("values (v_src, v_key, 'academic_entry', 'other_deterministic', 'entry_matrix', 'first_party', false, true, 'S2-Build reader lifecycle (s1303)')")
  expect(body).toContain("insert into pipeline.layer2_source_profile_versions (profile_id, version_no, configuration, configuration_hash, validation_status, validation_result, change_control_ref)")
  expect(body).toContain("where p.profile_key like 'reader:' || p_domain || ':' || p_provider::text || ':%' and p.enabled and not p.paused and v.validation_status = 'valid'")
})

test('a pass switches nothing on: activation is a separate step under the recorded standing authority, else a protected hold', () => {
  const decide = body.slice(body.indexOf('create or replace function security.reader_qualify_decide_v1'), body.indexOf('create or replace function security.reader_activate_v1'))
  expect(decide).not.toMatch(/enabled = true/)
  expect(decide).toContain("'activation', 'separate step'")
  expect(body).toContain("if k.code is null or k.authority <> 'auto' or not k.auto_eligible then")
  expect(body).toContain("'held', 'HELD:ACTIVATION_AUTHORITY'")
  expect(body).toContain("'HELD:ROUTE_UNAVAILABLE'")
  expect(body).toContain("set current_version_id = v.id, enabled = true, paused = false")
})

test('qualification: stored copies, deterministic readers only, positive and negative samples', () => {
  expect(body).toContain("'model', null, 'model_code', null, 'models', '[]'::jsonb, 'det_only', true")
  expect(body).toContain("case when c2.country is null then 'negative' else 'positive' end")
  expect(body).toContain("count(*) filter (where e.value->>'role' = 'negative' and e.value->>'outcome' <> 'guard_held')")
  expect(body).toContain("v_pass := v_mode is not null and v_neg_bad = 0;")
  expect(ix).toContain('const qitems: any[] = ((await rpc("svc_reader_qualify_next", { p_limit: limit }).catch(() => [])) || []) as any[];')
  expect(ix).toContain('rpc("svc_reader_qualify_record", { p_version: it.qualify_version_id, p_source: it.source_id, p_result: x.p_result ?? null, p_error: x.p_error ?? null })')
})

test('configuration is data: a closed list of registered reader settings and the address country', () => {
  expect(rc).toContain('const KEY = /^reading\\.entry_[a-z0-9_]+$/;')
  expect(ix).toContain('const ws = readerSettings(wsAll, it.reader_config);')
  expect(ix).toContain('stored.manifest.heading = `${String(it.reader_config.country_hint)} | ${stored.manifest.heading || ""}`;')
  expect(body).toContain("''reader_config'', security.reader_config_for_v1(''academic_entry'', u.provider_id, s.url)")
  expect(body).not.toMatch(/\bexecute\s+(p_|v_cfg|v\.configuration)/i)
})

test('learning and prevention through the existing recovery knowledge', () => {
  expect(body).toContain("v_chk := security.ops_learning_retry_check_v1(v_code, 'provider:' || p_provider::text, v_sig);")
  expect(body).toContain("'HELD:READER_RELEASE_REQUIRED'")
  expect(body).toContain("insert into pipeline.ops_remedy_blocks (knowledge_code, fingerprint, reason, signature)")
  expect((body.match(/security\.ops_learning_record_v1\(/g) || []).length).toBeGreaterThanOrEqual(3)
  expect(body).toContain("('reader_config:aer_matrix:country_page_generic_heading', 'aer',")
  expect(body).toContain("('reader_config:aer_matrix:pdf_layout_unproven', 'aer',")
})

test('re-reads go through the existing function with its history; nothing is dropped or deleted', () => {
  expect(body).toContain('v := public.admin_entry_matrix_reread(p_source_ids, p_reason);')
  expect(body.replace(/on commit drop/gi, '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
})
