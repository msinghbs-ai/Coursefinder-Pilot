// Guards: Wave 2 PR C, the generic Layer 1 declarative runner (Platform Admin 17 Nov 2026 17:55, 19:08, 19:58, 22:04, 23:02): AI-built parser specs only (no SQL or code), header drift halts and flags re-inference, chunked staging with row-hash diffing, course and provider registers through svc_layer1_apply_register_records, other record types staged for review, gap routing to the eight enrichment categories, ABS postcode flags, a dry run that writes nothing and switches nothing on, departures in staging only
// CF-247 S596. Migration 20261118013000_cf247_w2c_layer1_declarative_runner.sql; edge function layer1-declarative-runner 1.0.1 (1.0.1: html_table, s613).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations-archive/20261118013000_cf247_w2c_layer1_declarative_runner.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/layer1-declarative-runner/index.ts', 'utf8')
const reg = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8'))

test('staging keeps a row key and hash per source record; departures mark staging only; tables are commented and closed', () => {
  expect(mig).toContain('create table if not exists pipeline.layer1_declarative_rows (')
  expect(mig).toContain('primary key (source_id, row_key)')
  expect(mig).toContain("comment on table pipeline.layer1_declarative_rows is")
  expect(mig).toContain("comment on table pipeline.layer1_declarative_runs is")
  expect(mig).toContain('revoke all on pipeline.layer1_declarative_rows from anon, authenticated;')
  expect(mig).toContain("with d as (update pipeline.layer1_declarative_rows r set state = 'departed', departed_at = now()")
  expect(mig).not.toMatch(/update catalogue\./i)
  expect(mig).toMatch(/-- Replaces: nothing\.\n-- Retires: nothing\./)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).not.toMatch(/cron\.schedule\s*\(/)
})

test('sizes are settings; gap routes name only the eight categories and the seven record types', () => {
  for (const k of ['layer1.declarative_chunk_rows', 'layer1.declarative_dry_run_rows', 'layer1.declarative_batch_rows', 'layer1.declarative_max_rows']) {
    expect(mig).toContain(`'${k}'`)
    expect(fn).toContain(`"${k}"`)
  }
  expect(mig).toContain("raise exception 'post-check: a gap route names a category that is not in ref.enrichment_categories'")
  expect(mig).toContain("raise exception 'post-check: a gap route names a record type with no parser target'")
})

test('the runner: AI-built specs only, drift halts and flags, registers apply new and changed records, dry run writes nothing', () => {
  expect(fn).toContain('const VERSION = "1.0.1";')
  expect(fn).toContain('par.parser_kind !== "ai_built"')
  expect(fn).toContain('if (par.drift_flagged_at) return fail(')
  expect(fn).toContain('if (p.terms_status !== "approved") return fail(')
  expect(fn).toContain('await rpc(service, "svc_layer1_parser_drift_record", { p_source_id: sourceId, p_flagged: true, p_message: m });')
  expect(fn).toContain('"svc_layer1_declarative_stage_v1", { p_run_id: run, p_rows: rows.slice(i, i + cfg.chunk), p_write: false }')
  expect(fn).toContain('const recs = part.filter((x) => changed.has(x.key)).map((x) => x.record);')
  expect(fn).toContain('"svc_layer1_apply_register_records"')
  expect(fn).toContain('"svc_layer1_induction_dry_run_record"')
  expect(fn).toContain('"svc_layer1_declarative_postcodes_v1"')
  expect(fn).toContain('if (!isService) return fail("An apply run is started by the service role only.", 403);')
  expect(fn).not.toMatch(/openrouter|cascadeFetch|new Function|eval\(/i)
  expect(reg.functions['layer1-declarative-runner']).toBe(false)
})
