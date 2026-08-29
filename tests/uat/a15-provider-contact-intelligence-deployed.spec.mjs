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
function isProviderDetail(response){
  if(!response.url().includes('/rest/v1/rpc/admin_read'))return false
  try{return response.request().postDataJSON()?.p_operation==='provider_detail'}catch{return false}
}

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
    const hardening=await fs.readFile('supabase/migrations/20260829113049_a15_review_precedence_and_acceptance_contract.sql','utf8')
    const sydney=await fs.readFile('supabase/migrations/20260829113320_a15_sydney_regional_expert_reconciliation.sql','utf8')
    const sydneyInvariant=await fs.readFile('supabase/migrations/20260829113955_a15_sydney_acceptance_invariant.sql','utf8')
    const migrationFiles=(await fs.readdir('supabase/migrations')).filter(file=>/^\d{14}_.+\.sql$/.test(file))
    const versions=new Map()
    for(const file of migrationFiles){const version=file.slice(0,14);versions.set(version,(versions.get(version)||0)+1)}
    const duplicateVersions=[...versions.entries()].filter(([,count])=>count>1).map(([version])=>version)

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
    expect(duplicateVersions).toEqual([])

    expect(hardening).toContain("metadata ? 'a15_quality_review_at'")
    expect(hardening).toContain("v_review_rejected")
    expect(hardening).toContain("'contact_restored'")
    expect(hardening).toContain('provider_contact_profile_reconcile_service')
    expect(hardening).toContain('complete scan with at least one fetched page required')
    expect(hardening).toMatch(/revoke all on function public\.provider_contact_profile_reconcile_service\(uuid,text\[\],integer\) from public,anon,authenticated/i)
    expect(hardening).toContain("if p_operation='a15_acceptance_status'")
    expect(sydney).toContain("'sydney_first_party_regional_experts'")
    expect(sydney).toContain("metadata=(o.metadata-'a15_quality_disposition')")
    expect(sydney).toContain('structured regional-expert extraction with institutional email and governed territory')
    expect(sydneyInvariant).toContain("'sydney'")
    expect(sydneyInvariant).toContain("and coalesce((v_key_contacts->>'sydney')::boolean,false)")

    expect(scraper).toMatch(/provider-contact-discover-scheduled-v1\.\d+\.\d+/)
    expect(scraper).toContain('/sitemap.xml')
    expect(scraper).toContain('tableContacts')
    expect(scraper).toContain('structured.length?structured:lineContacts')
    expect(scraper).toContain('personal_contact_reveal:false')
    expect(scraper).toContain('provider-contact-discover-scheduled-v1.4.0')
    expect(scraper).toContain('seenIdentityHashes')
    expect(scraper).toContain('pageFailures===0')
    expect(scraper).toContain('provider_contact_profile_reconcile_service')

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

  test('A15 frozen cohort, reconciliations, watch semantics and authority boundaries remain accepted',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const providerDetail=page.waitForResponse(isProviderDetail,{timeout:45_000})
      await page.goto(`${process.env.UAT_BASE_URL}/#providers?id=${UQ_ID}`)
      const response=await providerDetail
      expect(response.status()).toBe(200)
      const requestHeaders=await response.request().allHeaders(),origin=new URL(response.url()).origin
      expect(requestHeaders.authorization).toMatch(/^Bearer /i)
      expect(requestHeaders.apikey).toBeTruthy()

      const result=await page.evaluate(async({origin,authorization,apikey})=>{
        const rpc=async(path,body,auth=true,extraHeaders={})=>{
          const response=await fetch(`${origin}${path}`,{
            method:'POST',
            headers:{apikey,...(auth?{authorization}:{}),'content-type':'application/json',...extraHeaders},
            body:JSON.stringify(body),
          })
          return{status:response.status,body:await response.json().catch(()=>null)}
        }
        const table=async(auth=true)=>{
          const response=await fetch(`${origin}/rest/v1/provider_contact_observations?select=id&limit=1`,{
            headers:{apikey,...(auth?{authorization}:{}),'accept-profile':'pipeline'},
          })
          return response.status
        }
        const [contract,anonymousContract,anonymousTable,authenticatedTable,authenticatedService]=await Promise.all([
          rpc('/rest/v1/rpc/admin_read',{p_operation:'a15_acceptance_status',p_args:{}},true),
          rpc('/rest/v1/rpc/admin_read',{p_operation:'a15_acceptance_status',p_args:{}},false),
          table(false),
          table(true),
          rpc('/rest/v1/rpc/provider_contact_profile_reconcile_service',{p_profile_id:'00000000-0000-0000-0000-000000000000',p_seen_identity_hashes:[],p_pages_fetched:1},true),
        ])
        return{contract,anonymousContract,anonymousTable,authenticatedTable,authenticatedService}
      },{origin,authorization:requestHeaders.authorization,apikey:requestHeaders.apikey})

      expect(result.contract.status).toBe(200)
      const status=result.contract.body
      expect(status?.ok).toBe(true)
      expect(status?.change_control).toBe('CF-CHG-20260829-046')
      expect(status?.metrics).toMatchObject({
        profile_total:60,profile_au:52,profile_nz:8,profile_success:60,profile_errors:0,
        current_contacts:31,contact_providers:11,territory_contacts:17,rejected_contacts:45,
        email_contacts:30,phone_contacts:18,reviewed_rejection_violations:0,
      })
      expect(status?.key_contacts).toEqual({uow:true,vu:true,wellington:true,sydney:true,otago:true})
      expect(status?.watch_events).toMatchObject({removal_supported:true,restoration_supported:true})
      expect(Number(status?.watch_events?.contact_removed_count||0)).toBeGreaterThan(0)
      expect(status?.security).toEqual({rls_enabled:true,no_direct_table_grants:true,service_upsert_private:true,service_reconcile_private:true})
      expect(status?.authority).toMatchObject({
        providers:3085,courses:43461,search_documents:33105,
        publication_entity_states:0,publication_events:9,publication_approvals:2,
      })
      expect(status?.canonical_mutation_authorised).toBe(false)
      expect(status?.search_mutation_authorised).toBe(false)
      expect(status?.publication_mutation_authorised).toBe(false)

      for(const denied of [result.anonymousContract.status,result.anonymousTable,result.authenticatedTable,result.authenticatedService.status]){
        expect(denied).toBeGreaterThanOrEqual(400)
      }
    }finally{await finish(testInfo,runtime)}
  })
})
