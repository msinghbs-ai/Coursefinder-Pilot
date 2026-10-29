// Guards: A15 Provider international contact intelligence
import { test, expect } from '@playwright/test'
import fs from 'node:fs/promises'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

const UQ_ID='e55396d2-869a-46ef-9d17-841c7eab1313'
const UQ_REGIONAL_URL='https://study.uq.edu.au/information-resources/teachers-guidance-counsellors/international-regional-managers'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('A15 Provider international contact intelligence @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'a15-provider-contact-intelligence',change_control:'CF-CHG-20260829-046'})
  })

  // v2.15.225 (Platform Admin, 9 Oct 2026: panels had too much text): the Provider blade no longer lists each contact. It shows an
  // "International contacts" fact card with the count and View contacts (Provider contacts, filtered to the provider). The governed
  // first-party assignments, their source page and Evidence still come in the provider read (international_contacts), checked here.
  test('UQ Provider blade shows governed first-party regional manager assignments with Evidence',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const detail=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{return r.request().postDataJSON()?.p_operation==='provider_detail'}catch{return false}},{timeout:45_000})
      await page.goto(`${process.env.UAT_BASE_URL}/#providers?id=${UQ_ID}`)
      const payload=await(await detail).json()
      const block=payload.international_contacts||{}
      const items=Array.isArray(block.items)?block.items:[]
      const regional=items.filter(x=>x.source_class==='first_party'&&x.source_url===UQ_REGIONAL_URL)
      expect(regional.length,'first-party regional manager assignments').toBeGreaterThan(0)
      expect(regional.every(x=>x.evidence_id),'each first-party assignment keeps its Evidence').toBeTruthy()
      const ashwin=regional.find(x=>x.full_name==='Ashwin Sreekumar')
      expect(ashwin,'UQ India regional manager').toBeTruthy()
      expect(`${ashwin?.territory_text||''} ${(ashwin?.territory_codes||[]).join(' ')}`).toMatch(/India|\bIN\b/)
      expect(Number(block.summary?.first_party_contacts||0)).toBeGreaterThan(0)

      const drawer=page.locator('aside.m-drawer-provider')
      await expect(drawer).toBeVisible({timeout:45_000})
      const card=drawer.locator('[data-ds-card="contacts"]')
      await expect(card).toContainText('International contacts')
      await expect.poll(async()=>Number(((await card.locator('strong').first().innerText())||'').replace(/[^0-9]/g,''))).toBeGreaterThan(0)
      const view=card.getByRole('button',{name:/View contacts/i})
      await expect(view).toBeVisible()
      await milestoneScreenshot(page,testInfo,'a15-uq-international-contacts-desktop')
      await view.click()
      await expect(page).toHaveURL(new RegExp(`#provider-contacts\\?provider_id=${UQ_ID}`))
      await expect(page.locator('.m-title-wrap h1')).toContainText('Provider contacts',{timeout:20_000})

      await page.setViewportSize({width:390,height:844})
      await page.goto(`${process.env.UAT_BASE_URL}/#providers?id=${UQ_ID}`)
      await expect(drawer.locator('[data-ds-card="contacts"]')).toBeVisible({timeout:45_000})
      const box=await drawer.boundingBox()
      expect(Math.abs((box?.width||0)-390)).toBeLessThanOrEqual(2)
      await milestoneScreenshot(page,testInfo,'a15-uq-international-contacts-mobile')
    }finally{await finish(testInfo,runtime)}
  })

  test('A15 data boundary keeps contact tables private and licensed search non-revealing',async()=>{
    const schema=await fs.readFile('supabase/migrations-archive/20260829003000_a15_provider_contact_intelligence.sql','utf8')
    const bridge=await fs.readFile('supabase/migrations-archive/20260829005500_a15_provider_contact_service_bridge.sql','utf8')
    const signals=await fs.readFile('supabase/migrations-archive/20260829009000_a15_contact_change_signal_semantics.sql','utf8')
    const scraper=await fs.readFile('supabase/functions/provider-contact-discover-scheduled/index.ts','utf8')
    const apollo=await fs.readFile('supabase/functions/provider-contact-enrich-apollo/index.ts','utf8')

    expect(schema).toContain('provider_contact_profiles')
    expect(schema).toContain('provider_contact_observations')
    expect(schema).toContain('provider_contact_watch_events')
    expect(schema).toContain('provider_contact_enrichment_attempts')
    expect(schema).toContain("c.iso_alpha2 in ('AU','NZ')")
    expect(schema).toMatch(/canonical_name ilike '%university%'/i)
    expect(schema).toContain('alter table pipeline.provider_contact_observations enable row level security')
    expect(schema).toContain('revoke all on pipeline.provider_contact_observations from public, anon, authenticated')
    expect(schema).toContain("case o.source_class when 'first_party' then 1")
    expect(bridge).toContain('service_role required')
    expect(bridge).toContain('provider_contact_observation_upsert_service')
    expect(signals).toContain("event_type <> 'new_contact'")

    expect(scraper).toMatch(/provider-contact-discover-scheduled-v1\.\d+\.\d+/)
    expect(scraper).toContain('/sitemap.xml')
    expect(scraper).toContain('tableContacts')
    expect(scraper).toContain('structured.length?structured:lineContacts')
    expect(scraper).toContain('personal_contact_reveal:false')

    expect(apollo).toContain('q_organization_domains_list[]')
    expect(apollo).toContain('person_titles[]')
    expect(apollo).toContain('International Recruitment Manager')
    expect(apollo).toContain('Regional Director')
    expect(apollo).toContain('personal_email_requested:false')
    expect(apollo).toContain('phone_requested:false')
    expect(apollo).not.toContain('reveal_personal_emails')
    expect(apollo).not.toContain('reveal_phone_number')
    expect(apollo).not.toMatch(/fetch\([^)]*linkedin\.com/i)
  })
})
