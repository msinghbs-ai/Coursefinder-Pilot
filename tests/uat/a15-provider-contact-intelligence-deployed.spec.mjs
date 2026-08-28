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

  test('UQ Provider blade shows governed first-party regional manager assignments with Evidence',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(`${process.env.UAT_BASE_URL}/#providers?id=${UQ_ID}`)
      const drawer=page.locator('aside.m-drawer-provider')
      await expect(drawer).toBeVisible({timeout:45_000})
      const contacts=drawer.locator('.cf-contact-intel')
      await expect(contacts.getByRole('heading',{name:'International contacts',exact:true})).toBeVisible()
      await expect(contacts).toContainText('First-party university contacts are preferred')
      await expect(contacts).toContainText('8 first-party')
      await expect(contacts).toContainText('Ashwin Sreekumar')
      await expect(contacts).toContainText('India')
      await expect(contacts).toContainText('india@uq.edu.au')
      await expect(contacts).toContainText('Jinny Yun')
      await expect(contacts).toContainText(/Cambodia, Indonesia, Laos, Malaysia/i)
      await expect(contacts).toContainText('Michelle Liu')
      await expect(contacts).toContainText(/China, Hong Kong \(SAR\), Japan/i)
      await expect(contacts.getByText('First-party university').first()).toBeVisible()
      const source=contacts.getByRole('link',{name:/University source/i}).first()
      await expect(source).toHaveAttribute('href',UQ_REGIONAL_URL)
      await expect(contacts.getByRole('button',{name:/Evidence/i}).first()).toBeVisible()
      await milestoneScreenshot(page,testInfo,'a15-uq-international-contacts-desktop')

      await page.setViewportSize({width:768,height:1024})
      await expect(contacts).toBeVisible()
      await expect(contacts.locator('.cf-contact-grid')).toBeVisible()
      await expect(contacts).toContainText('First-party university')
      await milestoneScreenshot(page,testInfo,'a15-uq-international-contacts-tablet')

      await page.setViewportSize({width:390,height:844})
      await expect(contacts).toBeVisible()
      await expect(contacts).toContainText('Ashwin Sreekumar')
      await expect(contacts).toContainText('India')
      await milestoneScreenshot(page,testInfo,'a15-uq-international-contacts-mobile')
    }finally{await finish(testInfo,runtime)}
  })

  test('A15 data boundary keeps contact tables private and licensed search non-revealing',async()=>{
    const schema=await fs.readFile('supabase/migrations/20260829003000_a15_provider_contact_intelligence.sql','utf8')
    const bridge=await fs.readFile('supabase/migrations/20260829005500_a15_provider_contact_service_bridge.sql','utf8')
    const signals=await fs.readFile('supabase/migrations/20260829009000_a15_contact_change_signal_semantics.sql','utf8')
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

    expect(scraper).toContain('provider-contact-discover-scheduled-v1.1.2')
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
