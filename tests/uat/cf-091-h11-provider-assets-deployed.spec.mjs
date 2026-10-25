// Guards: CF-091 H11 Provider Assets coverage
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-091 H11 Provider Assets coverage @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-101-h11-provider-assets-closure-v2',change_control:'CF-CHG-20260903-101'})})

  test('source contract exposes governed Provider Assets read surface',async()=>{
    const main=fs.readFileSync('src/mature-main.jsx','utf8')
    const api=fs.readFileSync('src/lib/supabase.js','utf8')
    // 26 Oct 2026 (test governance): Provider Assets moved under Providers › Assets; the old menu key now redirects there
    expect(fs.readFileSync('src/nav-map.js','utf8')).toContain("'provider-assets': { page: 'providers', tab: 'assets' }")
    expect(main).toContain("if(tab==='assets')return <ProviderAssetsWorkspace")
    expect(main).toContain('function ProviderAssetsWorkspace')
    expect(api).toContain("providerAssetSummary:")
    expect(api).toContain("providerAssetCoverage:")
  })
})
