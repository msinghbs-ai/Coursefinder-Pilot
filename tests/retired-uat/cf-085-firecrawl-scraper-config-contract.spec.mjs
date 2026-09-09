import fs from'node:fs/promises'
import{test,expect}from'@playwright/test'

test.describe('CF-085 Firecrawl scraper configuration contract',()=>{
 test('Firecrawl quota is editable in Scraper Config and not duplicated in Environment',async()=>{
  const[provider,environment,shell]=await Promise.all([
   fs.readFile('src/layer2-provider-entry.jsx','utf8'),
   fs.readFile('src/EnvironmentMigrationWorkspace.jsx','utf8'),
   fs.readFile('src/mature-main.jsx','utf8'),
  ])
  expect(shell).toContain("['layer2-providers','Scraper Config'")
  expect(shell).toContain("'layer2-providers':'Scraper Config'")
  expect(provider).toContain('aria-label="Firecrawl monthly limit"')
  expect(provider).toContain('aria-label="Firecrawl safety reserve"')
  expect(provider).toContain('monthly_vendor_units_limit:limit')
  expect(provider).toContain('stop_at_vendor_units_remaining:reserve')
  expect(provider).toContain('Firecrawl monthly limit did not persist exactly')
  expect(provider).toContain('Firecrawl safety reserve did not persist exactly')
  expect(environment).toContain('Monthly entitlement and reserve are managed in Administration → Scraper Config.')
  expect(environment).not.toContain('title="Firecrawl" hint="Update the recorded monthly entitlement')
 })
})