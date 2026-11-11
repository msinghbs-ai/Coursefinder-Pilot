// Guards: F-AER.04 AER delivery reported through the existing Data Delivery screen (Platform Admin decision delivery item 6, 11 Nov 2026: gains, gaps, spend and failures)
// Stage 4 of the Data Delivery AER panel (discovery and admission) reads public.admin_aer_delivery_progress on its own, beside the panel's existing read, so it adds nothing to
// security.data_delivery_v1 (measured 7-17 s against the 8 s limit). A figure the server did not send is Not measured, never 0. Proven by tests/fixtures/aer-delivery-progress/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261112133700_cf247_aer_delivery_progress.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const ui = fs.readFileSync('src/DataDelivery.jsx', 'utf8')

test('read only, Curator and above, edits no existing definition and stays out of the slow Data Delivery read', () => {
  expect(code).toContain("if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required'")
  expect(code).not.toMatch(/do \$m\$|execute v_def|create or replace function security\.data_delivery_(aer_)?v1/)
  expect(code).not.toMatch(/\b(insert into|update|delete from) (catalogue|pipeline)\.(?!component_register)/)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing\./m)
})

test('stage 4 sits in the existing AER panel, reads on its own and shows Not measured on failure', () => {
  const panel = ui.slice(ui.indexOf('function AerSources({a}){'), ui.indexOf('function Stream({s,now,providerFilters,open,onToggle}){'))
  expect(panel).toContain('<AerProgress/>')
  expect(panel).toContain("supabase.rpc('admin_aer_delivery_progress')")
  expect(panel).toContain('data-dd-aer-progress="unknown"')
  expect(panel).toContain("const nm=x=>x==null?'Not measured':fmtNumber(Number(x))")
  for (const k of ['aer_campaign_asked', 'aer_campaign_usable', 'aer_campaign_credits', 'aer_campaign_spare', 'aer_machine_matrix', 'aer_corrected_open', 'aer_gains', 'aer_failures']) expect(panel).toContain(`k="${k}"`)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112133700_'))).toEqual(['20261112133700_cf247_aer_delivery_progress.sql'])
})
