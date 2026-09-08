import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

const UQ_ID='e55396d2-869a-46ef-9d17-841c7eab1313'
const COURSE_ID='3ea5e651-dbcc-4ef4-8143-1de6900e012e'
const SCHOLARSHIP_ID='8c42b7a0-0ccf-5b64-a4ec-ec7b97b8c761'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('M2.4.4 A16 cross-layer contact + Layer 4 intervention @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required')
    await writeRunEnvironment({suite:'m2-4-4-a16-cross-layer',change_control:'CF-CHG-20260830-048'})
  })

  test('A16 database and worker contracts remain non-destructive, append-only and evidence-bound',async()=>{
    const foundation=await fs.readFile('supabase/migrations/20260830094500_m2_4_4_a16_layer4_overlay_contact_dispositions.sql','utf8')
    const completion=await fs.readFile('supabase/migrations/20260830094727_m2_4_4_a16_contact_disposition_completion.sql','utf8')
    const profile=await fs.readFile('supabase/migrations/20260830095100_m2_4_4_a16_contact_layer3_profile_pending_qualification.sql','utf8')
    const benchmark=await fs.readFile('supabase/migrations/20260830095255_m2_4_4_a16_contact_layer3_benchmark_contract.sql','utf8')
    const retry=await fs.readFile('supabase/migrations/20260830111112_m2_4_4_a16_contact_profile_retry_hardening.sql','utf8')
    const interpret=await fs.readFile('supabase/functions/layer3-interpret/index.ts','utf8')
    const benchWorker=await fs.readFile('supabase/functions/layer3-contact-benchmark/index.ts','utf8')
    const l4ui=await fs.readFile('src/Layer4Intervention.jsx','utf8')

    expect(foundation).toContain('layer4_field_registry')
    expect(foundation).toContain('layer4_override_decisions')
    expect(foundation).toContain('layer4_publication_decisions')
    expect(foundation).toContain('provider_contact_dispositions')
    expect(foundation).toContain('Layer 4 audit history is append-only')
    expect(foundation).toContain("editability_class='immutable'")
    expect(foundation).toContain("'canonical_changed',false")
    expect(foundation).not.toMatch(/update catalogue\.courses set description=/i)
    expect(foundation).toContain("'not_found_in_qualified_evidence'")
    expect(completion).toContain('no contact is manufactured')
    expect(profile).toContain("'openrouter-international-contact-v1'")
    expect(profile).toContain('pending_contact_specific_qualification')
    expect(benchmark).toContain('layer3-contact-benchmark')
    expect(benchmark).toContain('contact-specific quality gate')
    const expansion=await fs.readFile('supabase/migrations/20260830111812_m2_4_4_a16_scholarship_contact_layer4_expansion.sql','utf8')
    expect(expansion).toContain("('scholarship','name'")
    expect(expansion).toContain("('provider_contact','full_name'")
    expect(expansion).toContain("when 'scholarship' then exists")
    expect(expansion).toContain("when 'provider_contact' then exists")
    expect(expansion).toContain("layer4_effective_entity_read('provider_contact',o.id)")
    expect(retry).toContain('retry_ceiling=2')
    expect(interpret).toContain('international_contact')
    expect(interpret).toContain('not present in governed Evidence')
    expect(interpret).toContain('keepIfPresent')
    expect(benchWorker).toContain('anti-hallucination')
    expect(benchWorker).toContain('layer3-contact-benchmark-v1.2.0')
    expect(l4ui).toContain('Layer 4 governed intervention')
    expect(l4ui).toContain('Underlying:')
    expect(l4ui).toContain('Effective:')
    expect(l4ui).toContain('Mark publishable')
    expect(l4ui).toContain('does not authorise Production, Website or Zoho cutover')
    const rpcBoundary=await fs.readFile('supabase/migrations/20260830112408_m2_4_4_a16_rpc_security_invoker_boundary.sql','utf8')
    expect(rpcBoundary).toContain('create schema if not exists l4_api')
    expect(rpcBoundary).toContain('security invoker')
    expect(rpcBoundary).toContain('revoke all on schema l4_api from public,anon,authenticated')
    expect(rpcBoundary).toContain('curator role required')
    expect(rpcBoundary).toContain('PIM Admin role required for publication override')
    expect(rpcBoundary).toMatch(/revoke all on function public\.layer4_override_apply[\s\S]*from public,anon/i)
  })

  test('Provider blade shows explicit A16 disposition and Layer 4 intervention surface',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#providers?id=${UQ_ID}`)
      const drawer=page.locator('aside.m-drawer-provider')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'International contacts',exact:true})).toBeVisible()
      await expect(drawer.getByText(/Published Contact Found/i)).toBeVisible()
      const providerL4=drawer.locator('section.cf-layer4-override:visible').first()
      await expect(providerL4.getByRole('heading',{name:'Layer 4 governed intervention',exact:true})).toBeVisible()
      await expect(providerL4.getByText(/Effective-value overlay only/i)).toBeVisible()
      await expect(drawer.getByText('Layer 4 resolve',{exact:true}).first()).toBeVisible()
      await milestoneScreenshot(page,testInfo,'a16-provider-contact-l4')
    }finally{await finish(testInfo,runtime)}
  })

  test('Scholarship blade exposes the same governed Layer 4 overlay',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#scholarships?id=${SCHOLARSHIP_ID}`)
      const drawer=page.locator('aside.m-drawer-scholarship')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Layer 4 governed intervention',exact:true})).toBeVisible()
      await expect(drawer.getByText(/Publication override · separate decision/i)).toBeVisible()
      await milestoneScreenshot(page,testInfo,'a16-scholarship-l4-overlay')
    }finally{await finish(testInfo,runtime)}
  })

  test('Course blade shows Layer 4 overlay separately from publication override',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#courses?id=${COURSE_ID}`)
      const drawer=page.locator('aside.m-drawer-course')
      await expect(drawer).toBeVisible({timeout:45_000})
      await expect(drawer.getByRole('heading',{name:'Layer 4 governed intervention',exact:true})).toBeVisible()
      await expect(drawer.getByText(/Publication override · separate decision/i)).toBeVisible()
      await expect(drawer.getByText(/does not authorise Production, Website or Zoho cutover/i)).toBeVisible()
      await milestoneScreenshot(page,testInfo,'a16-course-l4-overlay')
    }finally{await finish(testInfo,runtime)}
  })
})
