// Guards: CF-103 Provider logo UX and identity quality
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
const badName=/^(location|campus|city|state|region|country|australia|new zealand|canada)$/i

test.describe('CF-103 Provider logo UX and identity quality @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-103-provider-logo-identity-quality-v3',change_control:'CF-CHG-20260904-103'})})

  test('source contract keeps Provider detail bold while list uses stable cached logo slots',async()=>{
    const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
    const upload=fs.readFileSync('supabase/functions/provider-asset-upload/index.ts','utf8')
    const access=fs.readFileSync('supabase/functions/provider-asset-access/index.ts','utf8')
    expect(logo).toContain('.m-drawer-provider .cf-provider-brand-copy strong')
    expect(logo).toContain('font-weight:850!important')
    expect(logo).toContain('.cf-provider-list-cell>.m-cell-title strong{font-weight:500!important')
    expect(logo).toContain("const listCache=new Map()")
    expect(logo).toContain('sessionStorage')
    expect(logo).toContain('flex:0 0 34px!important')
    expect(logo).toContain('const misses=targets.filter(x=>!x.cached)')
    expect(logo).toContain("img.loading='lazy'") // lazy since CF-150 (as CF-102 checks)
    expect(logo).toContain('Image address') // v2.15.281 editor wording
    expect(upload).toContain('gate.rpc("svc_logo_upload_allowed"') // v2.15.281: the role is a setting (Pipeline settings › Logos)
    expect(upload).toContain('unsafe_source_url')
    expect(access).toContain('stable_keys')
  })
})
