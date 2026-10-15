// CF-247 (S48): usage audit decisions D6, D7, D9 and D10. Platform Admin, 15 Oct 2026 22:12: "Proceed with D6, D7, D9 and D10."
// Live jobs move off the retired Layer 3 tables and the empty layer2_scope_wave_items; the rows nothing live uses are exported to the
// private Storage bucket (read back and checked) before a paste file purges or drops them. Rows still used are kept.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261015120000_cf247_retired_table_readers.sql', 'utf8')
const def = JSON.parse(fs.readFileSync('supabase/archive/cf247-usage-audit-2026-10-15.json', 'utf8'))
const wf = fs.readFileSync('.github/workflows/db-archive-export.yml', 'utf8')
const py = fs.readFileSync('scripts/archive_export.py', 'utf8')
const bodies = [...mig.matchAll(/\$function\$([\s\S]*?)\$function\$/g)].map((m) => m[1])

test('live jobs no longer read the retired rows: frozen copies, the English plan does not wait for Layer 3', () => {
  expect(mig).toContain('create table if not exists pipeline.layer3_validated_readings as')
  expect(mig).toContain('create table if not exists pipeline.layer3_call_costs_hourly as')
  expect(mig).toContain("comment on table pipeline.layer3_validated_readings is '")
  expect(mig).toContain("comment on table pipeline.layer3_call_costs_hourly is '")
  expect(mig).toContain('           false in_l3,  -- CF-247 15 Oct 2026 (usage audit D6): Layer 3 is retired, so no course waits for it')
  const adapter = bodies.find((b) => b.includes('v_mode_n int := 0;'))
  expect(adapter).toContain('from pipeline.layer3_validated_readings x where')
  expect(adapter).not.toContain('layer3_interpretations')
  const observe = bodies.find((b) => b.includes('r.ai_cost_mtd_usd'))
  expect(observe).toContain('from pipeline.layer3_call_costs_hourly k where k.hour >= m')
  expect(observe.replace(/--[^\n]*/g, '')).not.toContain('layer3_interpretations')
  for (const b of bodies) expect(b.replace(/--[^\n]*/g, '')).not.toMatch(/layer2_scope_wave_items/)
  expect(mig).toMatch(/^-- Replaces: .+/m)
  expect(mig).toMatch(/^-- Retires: pipeline\.layer2_scope_wave_items and 14 tables/m)
  // G2: the functions re-created here read their windows and sizes from settings
  for (const k of ['retention.job_log_keep_days', 'retention.screenshot_keep_days', 'retention.resource_observations_days', 'retention.estimate_refresh_hours', 'batch.retention_rows', 'batch.retention_layer2_rows', 'batch.retention_evidence'])
    expect(mig).toContain(`('pipeline', '${k}', `)
  expect(mig).toContain("make_interval(days => security.pipeline_num_v1('retention.screenshot_keep_days', 7)::int) order by created_at")
})

test('the export: every set a single select; still-used Layer 3 rows are not in the purge sets', () => {
  expect(def.bucket).toBe('archive')
  expect(def.sets).toHaveLength(18)
  for (const s of def.sets) {
    expect(s.select).toMatch(/^select /)
    expect(s.select).not.toContain(';')
  }
  const wi = def.sets.find((s) => s.name === 'layer3_work_items_purged').select
  expect(wi).toContain("w.task_class <> 'provider_current_tuition_validation' and w.status in ('admitted', 'no_candidate', 'superseded')")
  const li = def.sets.find((s) => s.name === 'layer3_interpretations_purged').select
  expect(li).toContain('not exists (select 1 from pipeline.layer4_review_items r where r.layer3_interpretation_id = i.id)')
  expect(li).toContain('not exists (select 1 from pipeline.scholarship_ai_run_items s where s.interpretation_id = i.id)')
  expect(def.sets.map((s) => s.name)).not.toContain('scholarship_coverage_benchmarks')
})

test('the export workflow: confirmed target, read back and checked, nothing changed in the database', () => {
  expect(wf).toContain('if [ -z "${{ vars.SUPABASE_PROJECT_REF }}" ] || [ "$PROJECT_REF" != "${{ vars.SUPABASE_PROJECT_REF }}" ]')
  expect(wf).toContain('python3 scripts/archive_export.py')
  expect(py).toContain("sys.exit(f\"::error::{s['name']}: key hash of the stored objects differs from the database\")")
  expect(py).toContain("'x-upsert': 'false'")
  expect(py).toContain("print(f'::add-mask::{svc}')")
  expect(py).not.toMatch(/\b(delete from|drop table|truncate table)\b/i)
})

test('removing an interpretation looks up its review items by index (the pending-only index cannot serve the check)', () => {
  const ix = fs.readFileSync('supabase/migrations/20261015130000_cf247_review_item_interpretation_index.sql', 'utf8')
  expect(ix).toContain('create index if not exists layer4_review_items_layer3_interpretation on pipeline.layer4_review_items (layer3_interpretation_id) where layer3_interpretation_id is not null;')
})
