import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

// Clean-up batch 2 (Platform Admin, 9 Oct 2026): the old Layer 2 onboarding queue (Decision 141) and the Layer 2
// automation settings were retired. Providers › Onboarding now explains that new providers are onboarded through the
// guided Adapter builder and links to it.
test('Providers › Onboarding: a plain panel pointing to the Adapter builder; the old queue is gone', () => {
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).not.toContain("import('./layer2-provider-onboarding')")
  expect(main).toContain('<ProviderOnboardingNotice rank={rank} navigate={navigate}/>')
  expect(main).toContain("onClick={()=>navigate('layer2',{tab:'builder'})}>Open the Adapter builder</button>")
  expect(fs.existsSync('src/layer2-provider-onboarding.jsx')).toBe(false)
  expect(fs.existsSync('src/Layer2AutomationSettings.jsx')).toBe(false)
})

test.describe('mocked browser', () => {
  test('Onboarding opens the Adapter builder', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#providers?tab=onboarding')
    const panel = page.locator('[data-provider-onboarding-notice]')
    await expect(panel).toContainText('New providers are onboarded through the guided Adapter builder')
    await panel.getByRole('button', { name: 'Open the Adapter builder' }).click()
    await expect(page).toHaveURL(/tab=builder/)
  })
})
