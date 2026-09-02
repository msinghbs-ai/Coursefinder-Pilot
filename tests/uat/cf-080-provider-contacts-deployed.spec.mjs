import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-080 Provider Contacts managed Catalogue @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-080-provider-contacts',change_control:'CF-CHG-20260902-080'})})

  test('Catalogue route loads managed contacts and honours the governed role boundary',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#provider-contacts',process.env.UAT_BASE_URL).toString())
      await expect(page.getByRole('heading',{name:'Provider Contacts'}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(page.getByText('Active contacts')).toBeVisible()
      await expect(page.getByText('Providers covered')).toBeVisible()
      await expect(page.locator('.pc-table tbody tr').first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(page.getByRole('button',{name:/Columns/})).toBeVisible()
      await page.getByRole('button',{name:/Columns/}).click()
      await expect(page.getByText('Show, reorder and resize the grid. Saved for this browser.')).toBeVisible()
      const add=page.getByRole('button',{name:/Add contact/})
      if(await add.count()){
        await expect(add).toBeVisible()
        await expect(page.getByRole('button',{name:/Import CSV/})).toBeVisible()
        await expect(page.getByRole('button',{name:/Export view/})).toBeVisible()
        await page.getByRole('button',{name:/Import CSV/}).click()
        await expect(page.getByRole('heading',{name:'Provider Contact CSV'})).toBeVisible()
        await expect(page.locator('option').filter({hasText:'9/1/2026 = 1 Sep 2026'})).toHaveCount(1)
        await expect(page.getByText(/Private Evidence upload/)).toBeVisible()
      }else{
        await expect(page.getByText(/Read-only view\. PIM Operator or Platform Admin is required/)).toBeVisible()
        await expect(page.getByRole('button',{name:/Import CSV/})).toHaveCount(0)
        await expect(page.getByRole('button',{name:/Export view/})).toHaveCount(0)
      }
    }finally{await finish(testInfo,runtime)}
  })

  test('Provider deep-link contract and governed client wiring are retained',async()=>{
    const fs=await import('node:fs/promises')
    const [shell,workspace,client,layer4]=await Promise.all([
      fs.readFile('src/mature-main.jsx','utf8'),
      fs.readFile('src/ProviderContactsWorkspace.jsx','utf8'),
      fs.readFile('src/lib/supabase.js','utf8'),
      fs.readFile('src/m2-3-intelligence-entry.jsx','utf8'),
    ])
    expect(shell).toContain("item('Provider Contacts',UsersRound,1)")
    expect(shell).toContain("navigate?.('Provider Contacts',{provider_id:data.id})")
    expect(workspace).toContain('uploadProviderContactFile')
    expect(workspace).toContain('PIM Operator or Platform Admin')
    expect(workspace).toContain('provider_ambiguous')
    expect(workspace).toContain('provider_unmatched')
    expect(workspace).toContain('CSV date format')
    expect(client).toContain("adminRead('provider_contacts_page'")
    expect(client).toContain("supabase.rpc('provider_contact_manage'")
    expect(client).toContain("invoke('provider-contact-import'")
    expect(client).toContain("invoke('provider-contact-control'")
    expect(client).toContain("provider_contact_export_audit")
    expect(workspace).toContain('contact reconciliation item(s) parked in Layer 4')
    expect(layer4).toContain("provider_contact_reconciliation_decide")
    expect(layer4).toContain("Map & apply")
    expect(layer4).toContain("Keep separate")
  })

  test('Provider Contacts remains contained at tablet and mobile widths',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      for(const viewport of [{width:768,height:1024},{width:390,height:844}]){
        await page.setViewportSize(viewport)
        await page.goto(new URL('/#provider-contacts',process.env.UAT_BASE_URL).toString())
        await expect(page.getByRole('heading',{name:'Provider Contacts'}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
        const overflow=await page.evaluate(()=>({
          viewport:window.innerWidth,
          doc:document.documentElement.scrollWidth,
          tableClient:document.querySelector('.pc-table-wrap')?.clientWidth||0,
          tableScroll:document.querySelector('.pc-table-wrap')?.scrollWidth||0,
        }))
        expect(overflow.doc).toBeLessThanOrEqual(overflow.viewport+2)
        expect(overflow.tableScroll).toBeGreaterThanOrEqual(overflow.tableClient)
        const importButton=page.getByRole('button',{name:/Import CSV/})
        if(await importButton.count()){
          await importButton.click()
          await expect(page.getByRole('heading',{name:'Provider Contact CSV'})).toBeVisible()
          const modal=await page.locator('.pc-import-modal').boundingBox()
          expect(modal?.width||9999).toBeLessThanOrEqual(viewport.width)
          await page.locator('.pc-modal-head > button').click()
        }else{
          await expect(page.getByText(/Read-only view\. PIM Operator or Platform Admin is required/)).toBeVisible()
        }
      }
    }finally{await finish(testInfo,runtime)}
  })


  test('Layer 4 route exposes Provider Contact reconciliation workload',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#layer-4-review',process.env.UAT_BASE_URL).toString())
      await expect(page.getByRole('heading',{name:'Layer 4 — Human Resolution'}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(page.getByText('Provider Contact reconciliation').first()).toBeVisible()
      await expect(page.getByText('Duplicate, Provider ambiguity or import/PIM conflict.')).toBeVisible()
    }finally{await finish(testInfo,runtime)}
  })

})
