// Guards: Platform Admin directive 10 Nov 2026 14:02 (rapidly increase source-backed entry-requirement coverage across all eligible AU/NZ providers) and G2/G3/Decision 260: source contract over migration 20261110160000, its forward recovery, the fixture workflow and the existing Data Delivery panel (the scheduled reading no longer counts parked Layer 4 holds against its limit; the no_source finding names its route; the AER stream shows sources, gaps, holds and runs).
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110160000_cf247_aer_source_recovery.sql', 'utf8')
const R = fs.readFileSync('supabase/held/aer_source_recovery_forward_recovery.sql', 'utf8')
const UI = fs.readFileSync('src/DataDelivery.jsx', 'utf8')
const WF = fs.readFileSync('.github/workflows/aer-source-recovery-test.yml', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/aer-source-recovery/run.sh', 'utf8')
const fn = (name, tag) => { const a = M.indexOf(`create or replace function ${name}`); return M.slice(a, M.indexOf(`$${tag}$;`, M.indexOf(`as $${tag}$`, a))) }
const PARKED = fn('security.aer_parked_items_v1', 'f'), ROUTE = fn('security.aer_no_source_route_v1', 'f'), DD = fn('security.data_delivery_aer_v1', 'aer')

test('the migration follows the house pattern: header, guarded edits, read-only functions, nothing dropped, no setting or job changed', () => {
  expect(M).toMatch(/^-- Replaces: security\.aer_schedule_tick_v1 /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  for (const l of ['security.aer_schedule_tick_v1(boolean) 705375f3705eb739cbc2bc2b9d64de53 -> ', 'security.aer_current_findings_v1() a9796f1cf7a3308c01972f2a4226eb90 -> ', 'security.data_delivery_v1() 849453412a8b9a448118e7b87362752a -> ']) expect(M).toContain('--   ' + l)
  expect(M).not.toMatch(/@[A-Z_]+_AFTER@/)   // every after md5 is recorded
  expect(M).toContain("live % differs from the definition this change edits (body md5 %)")
  expect(M).toContain('supabase/held/aer_source_recovery_forward_recovery.sql')
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/\balter\s+table\b/i)
  expect(M).not.toMatch(/\bcron\.(schedule|unschedule|alter_job)\b/i)
  expect(M).not.toMatch(/^\s*update\s+/im)
  expect(M).not.toMatch(/^\s*insert into\s+(?!pipeline\.component_register)/im)   // the only write is the component register
  expect(M).not.toMatch(/\bgrant\b/i)
  for (const f of ['aer_parked_items_v1', 'aer_no_source_route_v1', 'data_delivery_aer_v1']) expect(M).toContain(`revoke all on function security.${f}() from public, anon, authenticated;`)
})

test('the scheduled reading leaves parked holds out of the capacity count and keeps the limit and the fair mode', () => {
  expect(M).toContain('select count(*) into v_parked from security.aer_parked_items_v1();')
  expect(M).toContain('v_bp := v_l4 - v_parked + v_prog >= v_l4max;')
  expect(M).toContain("'parked_not_counted', v_parked")
  expect(M.slice(M.indexOf('-- 4. the guarded edits'))).not.toMatch(/aer\.schedule_layer4_max/)   // the limit stays the setting the tick already reads; the edits do not restate it
  expect(M).not.toMatch(/pipeline_num_v1\('wc\.aer_fair_on'/)   // the fair mode is not edited or restated
  // a parked hold is the lane's own record: stage parked and action park (a transient hold being retried is not parked)
  expect(PARKED).toContain("w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.stage = 'parked' and w.unresolved_blocker->>'action' = 'park'")
  expect(PARKED).toContain("i.status = 'pending'")
})

test('the route function reads only what is stored, uses the worker\'s page rules and the existing score setting, and has no operational value of its own (G2)', () => {
  expect(ROUTE).toContain('security.entry_source_score_v1(lk.url, lk.title)')
  expect(ROUTE).toContain("security.pipeline_num_v1('central.min_suggest_score', 4)")
  expect(ROUTE).toContain('security.coverage_identity_allowed(b.provider_id, b.identity_basis, \'entry_requirements\')')
  expect(ROUTE).toContain('security.aer_schedule_courses_v1(100000, true)')
  for (const r of ['source_page_stored', 'source_page_host_shared', 'course_pages_waiting', 'course_pages_unconfirmed', 'weak_page_only', 'nothing_stored']) expect(ROUTE).toContain(`'${r}'`)
  expect(ROUTE).not.toMatch(/\b(insert|update|delete|truncate)\b/i)
  expect(ROUTE).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)   // consumer API (G3)
  // every literal that is not a code or text is marked fixed
  for (const line of ROUTE.split('\n').filter(l => /greatest\(|100000/.test(l))) expect(line).toMatch(/-- fixed:/)
})

test('the no_source finding gains evidence only: fingerprint, root cause and counts are unchanged', () => {
  expect(M).toContain("from el e left join security.aer_no_source_route_v1() r on r.provider_id = e.provider_id where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)")
  expect(M).toContain("(jsonb_build_object('country', e.country) || coalesce(jsonb_strip_nulls(")
  expect(M).not.toMatch(/aer_fingerprint_v1/)
})

test('Data Delivery gets one additive key, counted live and cheap, never 0 when it cannot be counted', () => {
  expect(M).toContain("'aer_sources', case when s.stream = 'aer' then security.data_delivery_aer_v1() end,")
  expect(DD).toContain("return jsonb_build_object('known', false, 'reason', left(sqlerrm, 200));")
  expect(DD).toContain("security.pipeline_num_v1('aer.schedule_layer4_max', 600)")
  expect(DD).toContain('security.aer_parked_items_v1()')
  expect(DD).toContain('security.cron_next_run_v1(c.schedule, now())')
  expect(DD).not.toContain('aer_no_source_route_v1')   // the slow route function is read through the hourly findings, never at page load
  expect(DD).not.toMatch(/\b(insert|update|delete|truncate)\b/i)
})

test('the forward recovery takes the three edits back, guarded by the after md5s, and leaves the read-only functions', () => {
  for (const f of ['705375f3705eb739cbc2bc2b9d64de53', 'a9796f1cf7a3308c01972f2a4226eb90']) expect(R).toContain(f)
  expect(R).toContain('is neither the text this change wrote nor the original')
  expect(R).not.toMatch(/^\s*drop\b/im)
  expect(R.slice(R.indexOf('begin'))).toContain("'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,")
})

test('the existing panel draws the new key; a missing key is Not measured; nothing is a new panel', () => {
  expect(UI).toContain("{s.stream==='aer'&&<AerSources a={s.aer_sources}/>}")
  expect(UI).toContain('data-dd-aer-sources="unknown"')
  expect(UI).toContain('a==null||a.known===false')
  expect(UI).toContain('open={open[s.stream]??Boolean(s.stages||s.provider_ai||s.aer_sources)}')
  expect(UI).toContain("{s.stream==='pdesc'&&<ProviderAi pa={s.provider_ai}/>}")
  expect((UI.match(/export default function/g) || []).length).toBe(1)
})

test('CI runs the fixture and this contract on every change to the files', () => {
  expect(WF).toContain('run: bash tests/fixtures/aer-source-recovery/run.sh')
  expect(WF).toContain('supabase/migrations/20261110160000_cf247_aer_source_recovery.sql')
  expect(WF).toContain('supabase/held/aer_source_recovery_forward_recovery.sql')
  expect(RUN).toContain('dropdb')
  expect(RUN).toMatch(/case "\$DB" in g_\*\)/)   // a scratch database only, never a Supabase project
})
