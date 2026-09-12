import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

const migration = fs.readFileSync(
  path.resolve('supabase/migrations/20260912031356_cf_093_scheduler_terminal_negative_freshness_dedupe.sql'),
  'utf8',
)
const hardening = fs.readFileSync(
  path.resolve('supabase/migrations/20260912101339_cf_093_terminal_negative_basis_hardening.sql'),
  'utf8',
)

test('CF-093 terminal discovery freshness remains current-version and evidence-basis governed', async () => {
  expect(migration).toContain('scheduler_workflow_recent_terminal_negative_v1')
  expect(migration).toContain('freshness_sla_hours')
  expect(hardening).toContain('source_profile_version_id=p.current_version_id')
  expect(hardening).toContain("d.status in ('ambiguous','identity_mismatch')")
  expect(hardening).toContain("d.status='current_page_not_found'")
  expect(hardening).toContain("layer2-scope-discover-scheduled-v1.3.10")
  expect(hardening).toContain('zero_result_marker_qualified')
  expect(hardening).toContain('required_prefix_link_count')
  expect(hardening).toContain('x.terminal_at>=now()-make_interval(hours=>p.freshness_sla_hours)')
  expect(migration).toContain('terminal_negative_count')
})

test('CF-093 preview and start rediscover only courses without a current governed terminal basis', async () => {
  expect(migration).toContain('sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1')
  expect(migration).toContain('fresh_terminal_negative_count')
  expect(migration).toContain('terminal_negative_count')
  expect(hardening).toContain("d.status in ('ambiguous','identity_mismatch')")
  expect(hardening).toContain("d.status='current_page_not_found'")
  expect(hardening).toContain("coalesce(d.match_basis->>'worker_version','')='layer2-scope-discover-scheduled-v1.3.10'")
})

test('CF-093 large-scope fresh-preview dedupe follows existing execution stale horizon', async () => {
  expect(migration).toContain('v_dedupe_minutes integer:=10')
  expect(migration).toContain('max(ep.stale_after_minutes)')
  expect(migration).toContain('now()-make_interval(mins=>v_dedupe_minutes)')
  expect(migration).toContain("'dedupe_horizon_minutes',v_dedupe_minutes")
})

test('CF-093 freshness and terminal-basis corrections preserve authority boundaries', async () => {
  for (const sql of [migration, hardening]) {
    expect(sql).not.toMatch(/insert\s+into\s+pipeline\.layer3_interpretations/i)
    expect(sql).not.toMatch(/insert\s+into\s+pipeline\.search_refresh_signals/i)
    expect(sql).not.toMatch(/insert\s+into\s+publishing\.publication_events/i)
    expect(sql).not.toMatch(/update\s+catalogue\.courses/i)
  }
})
