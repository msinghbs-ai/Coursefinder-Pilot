// Guards: Platform Admin mandate 3 Nov 2026 12:04 §5 and §6 (per-field backlog measured by the platform; missing page proof is a discoverable gap fed to the source-proof lane)
// The behaviour runs on isolated fixtures by tests/fixtures/source-proof/run.sh (scratch PostgreSQL; the lanes fixture and migration it builds on;
// the live relink definitions loaded from their live text and checked against the live md5s; the defect reproduced on them; the migration applied
// twice; every case asserted). This spec holds the contract of the change and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261103190000_cf247_source_proof_lane_field_backlog.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/source-proof'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']]', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf('$function$;', a)) }

const MD5 = {
  'security.course_relink_tick_v1(integer)': ['cad7fad43c0421d52f76315f28c8fbdf', 'b159c75a0ed1517fc9305b62984aa141'],
  'security.course_relink_provider_v1(uuid,integer)': ['c349b4f218c604d2d1937e66ab3a051c', '8f2f82c7e2ad360a0ade7cdee1f63cce'],
  'public.admin_pipeline_yield(jsonb)': ['a38814324515b163a34129b7a9d01dbd', '34617ad96ea43189509c3f4dd536d50e'],
}

test('three definitions are edited only from their known md5 (the yield from its v2.15.423 text) and checked after', () => {
  for (const [sig, [b, a]] of Object.entries(MD5)) {
    const e = edit(sig)
    expect(e).toContain(`array['${b}'], array['${a}']`)
    expect(m).toContain(`${b} -> ${a}`)
    expect(run).toContain(b)
  }
  expect(run).toContain('$LMIG')
  expect(m).toContain("raise exception 'source proof: apply migration 20261103160000 (lanes and gap queue, v2.15.423) first'")
  expect(m).toContain("raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_afters[k];")
})

test('course-relink tries a requested course again, once per request (no loop); nothing else in it changes', () => {
  for (const sig of ['security.course_relink_tick_v1(integer)', 'security.course_relink_provider_v1(uuid,integer)']) {
    const e = edit(sig)
    expect(after(e)).toContain("and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))")
    expect(e.endsWith("$n$")).toBe(true)
  }
  expect(fn('security.source_proof_relink_asked_v1')).toContain("and q.requested_at > coalesce(p_since, '-infinity'::timestamptz))")
  expect(before).toContain("course-relink takes none of them again")
  for (const k of ['P1 ok', 'P2 ok', 'P3 ok']) expect(fixtures).toContain(k)
  expect(fixtures).toContain('(no loop)')
})

test('the source-proof lane routes to existing lanes only; free work at 50 a run, paid search ships 0; bounded and fingerprinted', () => {
  const f = fn('security.source_proof_feed_v1')
  for (const route of ['layer4', 'locked', 'reading', 'relink', 'search', 'no_route', 'exhausted', 'unchanged']) expect(f).toContain(`'${route}'`)
  expect(f).toContain('from pipeline.course_page_proofs pp')
  expect(f).toContain("i.field_code = 'official_course_url' and i.status = 'pending'")
  expect(f).toContain("when r.qfp = r.fp then 'unchanged'")
  expect(f).toContain("when r.attempts >= v_max then 'exhausted'")
  expect(f).toContain('insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)')
  expect(f).not.toMatch(/firecrawl|net\.http_post|openrouter|svc_pilot_submit/i)
  expect(f).toContain("s.key = 'course_url.fill_countries'")
  expect(m).toMatch(/'proof\.feed_per_run'[\s\S]*?to_jsonb\(50\), 0, 1000, 'courses'/)
  expect(m).toMatch(/'proof\.search_per_run'[\s\S]*?to_jsonb\(0\), 0, 200, 'courses'/)
  expect(m).toContain("raise exception 'source proof post-check: proof.search_per_run must ship 0 (paid search)'")
  expect(m).toContain("perform cron.schedule('source-proof-feed', '14,44 * * * *', $c$select security.source_proof_feed_v1()$c$);")
  for (const k of ['P4 ok', 'P5 ok', 'P6 ok', 'P7 ok', 'P8 ok']) expect(fixtures).toContain(k)
})

test('field backlog: twelve fields, read-only and bounded, each split adds up, forecast only from a measured rate', () => {
  const b = fn('security.field_backlog_v1')
  expect(b).toContain("language plpgsql stable security definer set search_path to '' set statement_timeout to '20s'")
  expect(b).not.toMatch(/\b(insert into|update|delete from)\s+(pipeline|catalogue)\./)
  expect(b).toContain('from pipeline.course_attribute_coverage a')
  // rankings are read where the Website API reads them (schema ranking), not from the empty catalogue.provider_rankings
  expect(b).toContain("where sy.active and e.status = 'accepted' order by e.system_id, e.edition_year desc")
  expect(b).toContain('from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id')
  expect(b).not.toMatch(/catalogue\.provider_rankings|ref\.ranking_sources/)
  for (const f of ['course_description', 'application_deadline', 'provider_description', 'intakes', 'aer_course', 'scholarships', 'fees', 'english', 'campus', 'delivery', 'duration', 'rankings']) expect(b).toContain(`'${f}'`)
  for (const k of ['waiting_layer4', 'not_supported', 'stored_source', 'requires_acquisition', 'processed_24h', 'admitted_24h', 'processed_7d', 'admitted_7d', 'accepted_per_hour', 'forecast_hours']) expect(b).toContain(`'${k}'`)
  expect(b).toContain("'forecast_hours', case when coalesce((r.v->>'admitted_in_rate_window')::numeric, 0) > 0")
  expect(after(edit('public.admin_pipeline_yield(jsonb)'))).toContain("|| jsonb_build_object('field_backlog', security.field_backlog_v1(nullif(p_args->>'country', '')));")
  for (const k of ['B1 ok', 'B2 ok']) expect(fixtures).toContain(k)
})

test('Platform health › Integration queue › Pipeline yield shows the field backlog and the source-proof lane', async ({ page }) => {
  await mockAdmin(page, { rank: 5 })
  await page.route('**/rest/v1/rpc/admin_integration_queue', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ mode: { mode: 1, set_by: 'x', set_at: '2026-11-02T06:00:00Z', reason: 'r' }, by_status: {}, by_severity: {}, by_workstream: {}, issues: [] }) }))
  const row = (o) => ({ eligible: 0, waiting_layer4: 0, not_supported: 0, stored_source: 0, requires_acquisition: 0, processed_24h: 0, admitted_24h: 0, processed_7d: 0, admitted_7d: 0, accepted_per_hour: 0, forecast_hours: null, ...o })
  await page.route('**/rest/v1/rpc/admin_pipeline_yield', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ window_hours: 24, lanes: [], field_backlog: { country: null, fields: [
    row({ field: 'intakes', label: 'Intake dates', eligible: 20727, waiting_layer4: 377, not_supported: 5422, stored_source: 9800, requires_acquisition: 5128, admitted_24h: 120, admitted_7d: 840, accepted_per_hour: 5, forecast_hours: 3061 }),
    row({ field: 'rankings', label: 'Rankings (universities with none)', eligible: 52, not_supported: 52, note: 'no active ranking source' })],
    source_proof: { waiting_for_page_proof: 10900, settled_24h: 96, free_per_run: 50, paid_search_per_run: 0 } } }) }))
  await page.goto('/#platform-health?tab=integration')
  const t = page.locator('[data-field-backlog]')
  await expect(t).toContainText('Field backlog now')
  await expect(t.locator('[data-backlog-field="intakes"] [data-backlog-col="eligible"]')).toHaveText('20,727')
  await expect(t.locator('[data-backlog-field="intakes"] [data-backlog-col="requires_acquisition"]')).toHaveText('5,128')
  await expect(t.locator('[data-backlog-field="intakes"] [data-backlog-col="forecast"]')).toHaveText('128 days')
  await expect(t.locator('[data-backlog-field="rankings"] [data-backlog-col="forecast"]')).toHaveText('No rate yet')
  await expect(t.locator('[data-source-proof]')).toContainText('10,900 courses wait for page proof')
  await expect(t.locator('[data-source-proof]')).toContainText('paid search 0 a run')
})
