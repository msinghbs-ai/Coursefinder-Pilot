// Guards: CF-088 M2.4.5 Administration IA hardening
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-088 M2.4.5 Administration IA hardening @targeted',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-088-admin-ia-v1',change_control:'CF-CHG-20260903-088'})})

  test('source contract keeps one Administration control plane and legacy deep links',async()=>{
    const main=fs.readFileSync('src/mature-main.jsx','utf8')
    const access=fs.readFileSync('src/access-roles-entry.jsx','utf8')
    const index=fs.readFileSync('index.html','utf8')
    expect(main).toContain("import{UI_VERSION}from'./release-manifest.js'") // v2.15.291: the shell's version comes only from the manifest
    // v2.15.107: Administration sections became pages in nav-map.js; every old Administration
    // section and legacy address (users-roles, attributes, settings) still resolves.
    const nav=fs.readFileSync('src/nav-map.js','utf8')
    expect(nav).toContain('export const LEGACY_ADMIN_SECTIONS = {')
    for(const k of ["'overview'","'sources-imports'","'layer1-sources'","'layer2-providers'","'provider-assets'","'layer2-sources'","'onboarding'","'pim'","'users-roles'","'environment-migration'","'platform'"])expect(nav).toContain(k+':')
    expect(nav).toContain("'attributes': { page: 'coverage', tab: 'attributes' }") // v2.15.301: Data model retired
    expect(nav).toContain("'settings': { page: 'migration' }") // v2.15.301: Capacity is on the Go-live checklist
    expect(main).toContain("case'users':return <AccessRolesEmbedded actorId={actorId}/>")
    expect(main).not.toContain("if(key==='users-roles'){location.hash='#users-roles'")
    expect(access).toContain("export function AccessRolesEmbedded")
    expect(index).not.toContain('id="access-roles-root"')
    expect(index).not.toContain('src="/src/access-roles-entry.jsx"')
    execFileSync('npm',['run','build'],{stdio:'inherit'})
  })
})
