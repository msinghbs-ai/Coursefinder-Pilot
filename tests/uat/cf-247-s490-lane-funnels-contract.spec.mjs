// Guards: CF-247 OPS/UI mandate (Platform Admin 8 Nov 2026 14:06): one catalogue-driven lane funnel read (SELECT only, snapshot-fed) shows every autonomous lane on the existing screens, with no new top-level menu, no duplicate schedule or controller, the existing audited controls, and read-only Firecrawl acceptance that edits no budget SQL
// Source contract: reads the migration, the scratch-database fixture (tests/fixtures/lane-funnels, run in CI by lane-funnels-test.yml), the screens and the navigation. The central rules (G2 s32, G3 s57, housekeeping/G1 s42) are not repeated here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261108170000_cf247_lane_funnels.sql', 'utf8')
const fx = fs.readFileSync('tests/fixtures/lane-funnels/fixtures.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/lane-funnels/run.sh', 'utf8')
const wf = fs.readFileSync('.github/workflows/lane-funnels-test.yml', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)
const LANES = ['p0', 'int', 'fee', 'eng', 'cdesc', 'pdesc', 'aer', 'sch', 'disc']

test('the nine lanes are seeded once, each with stages, and a lane adds rows with on conflict do nothing (no code change)', () => {
  for (const l of LANES) expect(C).toMatch(new RegExp(`\\('${l}', '[^']+', \\d+, '`))
  expect(C).toMatch(/insert into pipeline\.lane_funnel_lanes[\s\S]*on conflict \(lane\) do nothing/)
  expect(C).toMatch(/insert into pipeline\.lane_funnel_stages[\s\S]*on conflict[\s\S]*do nothing/)
  // every stage reads the existing progress contract or a SELECT; never both missing
  expect(C).toContain('check (transition_key is not null or count_sql is not null)')
})

test('the screen never runs the counting SELECTs: a refresh job writes readings, the read only reads them, and stage SQL cannot write', () => {
  expect(C).toMatch(/function security\.lane_funnel_eval_v1\(p_sql text, p_window_hours integer\)[\s\S]*?\bstable\b[\s\S]*?security definer/i)
  expect(C).toMatch(/function security\.lane_funnel_v1\(p_lane text default null\)[\s\S]*?\bstable\b/i)
  expect(C).toContain("pg_try_advisory_xact_lock")
  expect(C).toMatch(/statement_timeout/)
  expect(C).toContain("cron.schedule('lane-funnel'")
  expect(C).toMatch(/insert into pipeline\.automation_catalogue[\s\S]*'lane-funnel'/)
  // the evaluator refuses anything but one SELECT
  expect(C).toMatch(/lane_funnel_eval_v1[\s\S]*?(insert|update|delete)[\s\S]*?raise exception/i)
})

test('only the existing screens change: no new top-level menu, no new page key, and the audited control is the existing one', () => {
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  expect(nav).not.toMatch(/lane-funnels|laneFunnels|lane_funnels/i)
  const lf = fs.readFileSync('src/LaneFunnels.jsx', 'utf8')
  expect(lf).toContain("rpc('admin_lane_funnel_v1'")
  expect(lf).toContain("rpc('admin_automation_control'")
  expect(lf).toMatch(/window\.prompt/) // a reason is asked for every control
  expect(lf).not.toMatch(/\.from\(['"]|\.insert\(|\.update\(|\.delete\(/) // the panel reads through the RPC and writes only through the audited control
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toMatch(/<Layer23Operations [^>]*\/><LaneFunnels rank=\{rank\} onError=\{err\}\/>/)
  const ts = fs.readFileSync('src/Toolsets.jsx', 'utf8')
  expect(ts).toMatch(/<FirecrawlAcceptance onError=\{onError\}\/><FirecrawlCredits/)
})

test('Firecrawl acceptance is read only, in credits, and the Controller budget functions are called and never redefined', () => {
  expect(C).toMatch(/function public\.admin_firecrawl_acceptance_v1\(\)[\s\S]*?stable/i)
  for (const f of ['fc_priority_room_v1', 'fc_budget_left_v1', 'fc_budget_status_v1', 'fc_vendor_estimate_v1', 'fc_purpose_group_v1', 'fc_day_start_v1']) {
    expect(C).toContain(`security.${f}(`)
    expect(C).not.toMatch(new RegExp(`create or replace function security\\.${f}\\b`))
  }
  expect(C).not.toMatch(/(insert into|update|delete from)\s+pipeline\.(vendor_credit_observations|coverage_vendor_usage)/i)
  expect(C).toContain("'unit', 'credits'")
  const fc = fs.readFileSync('src/FirecrawlAcceptance.jsx', 'utf8')
  expect(fc).not.toMatch(/\bAUD\b|\bUSD\b|currency/i)
  expect(fc).toContain("'unknown'")
})

test('the fixture proves behaviour on a scratch database (write refusal, unknown against zero, trend, verdicts, permissions) and CI runs it on the isolated image', () => {
  for (const needle of ['refus', 'unknown', 'green_no_transfer', 'failing', 'stalled', 'rank']) expect(fx.toLowerCase()).toContain(needle)
  expect((fx.match(/pg_temp\.(ok|raises)\(/g) || []).length).toBeGreaterThan(40)
  expect(run).toContain('migration applied twice')
  expect(wf).toContain('postgres:17.6-alpine')
  expect(wf).toContain('tests/fixtures/lane-funnels/run.sh')
  expect(wf).toMatch(/^# Guards: /m)
})

test('no settings, tables or functions are dropped, and the change is additive to the consumer API surface', () => {
  expect(C).not.toMatch(/\bdrop\s+(table|function|schema|column|view)\b/i)
  expect(C).not.toMatch(/\balter\s+table\s+(public|api)\./i)
  expect(C).not.toMatch(/function (public\.(website_v2_|website_edge_|website_api_v2_|zoho_edge_)|api\.)/)
})
