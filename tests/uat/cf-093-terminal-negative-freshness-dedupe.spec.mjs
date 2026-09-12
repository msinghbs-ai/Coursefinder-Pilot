import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

const migration = fs.readFileSync(
  path.resolve('supabase/migrations/20260912032000_cf_093_scheduler_terminal_negative_freshness_dedupe.sql'),
  'utf8',
)

test('CF-093 fresh terminal discovery outcomes are bounded by governed profile freshness', async () => {
  expect(migration).toContain('scheduler_workflow_recent_terminal_negative_v1')
  expect(migration).toContain("freshness_sla_hours")
  expect(migration).toContain("source_profile_version_id=p.current_version_id")
  expect(migration).toContain("current_page_not_found','ambiguous','identity_mismatch")
  expect(migration).toContain("l.created_at>=now()-make_interval(hours=>p.freshness_sla_hours)")
  expect(migration).toContain('terminal_negative_count')
})

test('CF-093 preview and start exclude only fresh terminal negatives from rediscovery', async () => {
  expect(migration).toContain("sc.source_url is null and not security.scheduler_workflow_recent_terminal_negative_v1")
  expect(migration).toContain("fresh_terminal_negative_count")
  expect(migration).toContain("async_discovery_preview_bound',v_discovery_count>0")
})

test('CF-093 large-scope fresh-preview dedupe follows existing execution stale horizon', async () => {
  expect(migration).toContain('v_dedupe_minutes integer:=10')
  expect(migration).toContain('max(ep.stale_after_minutes)')
  expect(migration).toContain("now()-make_interval(mins=>v_dedupe_minutes)")
  expect(migration).toContain("'dedupe_horizon_minutes',v_dedupe_minutes")
})

test('CF-093 correction preserves authority boundaries', async () => {
  expect(migration).not.toMatch(/insert\s+into\s+pipeline\.layer3_interpretations/i)
  expect(migration).not.toMatch(/insert\s+into\s+pipeline\.search_refresh_signals/i)
  expect(migration).not.toMatch(/insert\s+into\s+publishing\.publication_events/i)
  expect(migration).not.toMatch(/update\s+catalogue\.courses/i)
})
