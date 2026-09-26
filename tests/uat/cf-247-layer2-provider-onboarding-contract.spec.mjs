import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 141: per-provider onboarding panel is mounted on Layer 2 and uses the governed functions.
test('Layer 2 provider onboarding: mounted, dry-run first, three-course check required',async()=>{
  const entry=fs.readFileSync('src/layer2-operations-entry.jsx','utf8')
  expect(entry).toContain("import ProviderOnboarding from'./layer2-provider-onboarding'")
  expect(entry).toContain('<ProviderOnboarding rank={rank}/>')
  const panel=fs.readFileSync('src/layer2-provider-onboarding.jsx','utf8')
  expect(panel).toContain("rpc('layer2_provider_onboarding_queue_v1'")
  expect(panel).toContain("rpc('layer2_provider_catalogue_submit_v1'")
  expect(panel).toContain('p_dry_run:dry')
  expect(panel).toContain('disabled={!canAct||!!busy||!checked}')
  expect(panel).toContain('const canAct=rank>=4')
})

// Decisions 141 and 146: Platform Admin automation controls live in Scraper Config.
test('Layer 2 automation settings: in Scraper Config, admin-only editing, Firecrawl-bounded',async()=>{
  const entry=fs.readFileSync('src/layer2-provider-entry.jsx','utf8')
  expect(entry).toContain("import Layer2AutomationSettings from'./Layer2AutomationSettings'")
  expect(entry).toContain('<Layer2AutomationSettings onError={setError}/>')
  const card=fs.readFileSync('src/Layer2AutomationSettings.jsx','utf8')
  expect(card).toContain("rpc('layer2_auto_discovery_settings_read_v1'")
  expect(card).toContain("rpc('layer2_auto_discovery_settings_save_v1'")
  expect(card).toContain('const edit=data.can_edit,max=Number(data.firecrawl_concurrency||1)')
  expect(card).toContain('max={max}')
  expect(card).toContain("disabled={busy||reason.trim().length<8}")
})

