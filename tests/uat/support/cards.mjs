// v2.15.200: every card starts collapsed. Opens the collapsed cards on the page (top level first, then any that appear).
export async function openCards(page, scope = 'body') {
  await page.locator(`${scope} .cf-card-toggle`).first().waitFor()
  for (let i = 0; i < 6; i++) {
    const closed = page.locator(`${scope} .cf-card-toggle[aria-expanded="false"]`)
    const n = await closed.count()
    if (!n) return
    for (let k = n - 1; k >= 0; k--) await closed.nth(k).click()
    await page.waitForTimeout(150)
  }
}
export async function openCard(page, id) {
  const t = page.locator(`[data-card="${id}"] .cf-card-toggle`)
  if ((await t.getAttribute('aria-expanded')) !== 'true') await t.click()
}

// v2.15.200: Layer 2 › Adapters. Opens one university's row and then the named blocks (switch, build, schedule, central, fees, hosted, firecrawl, history, courses).
export async function openAdapter(page, id, blocks = []) {
  await page.goto('/#layer-2-discovery')
  await page.locator('[data-adapters-list] select[aria-label="Provider kind"]').selectOption('any')
  const row = page.locator(`[data-adapter-row="${id}"]`)
  await row.locator('.ad-row-head .ad-row-name').click()
  for (const b of blocks) await row.locator(`[data-ad-block="${b}"] > .ad-row-name`).click()
  return row
}
