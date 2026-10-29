// CF-247 AER workspace live read-only visual acceptance (Platform Admin decision 29 Oct 2026 09:57, item 5).
// Used by capture.spec.mjs when SCREENS contains "aer-tour". Read-only: it filters, opens menus and drawers and inspects resolution;
// it never edits, adds, withdraws, quarantines, restores or reads again. Desktop at 1440 px, then phone width (390 px).
import path from 'node:path'

const pick = async (page, bar, button, text, exact) => {
  await bar.getByRole('button', { name: button }).first().click()
  await page.locator('.m-filter-popover input').fill(text)
  await page.locator('.m-filter-popover').getByRole('button', { name: exact }).first().click()
}

async function layoutFacts(page) {
  return page.evaluate(() => {
    const doc = document.documentElement
    const clipped = [...document.querySelectorAll('main *')].filter((el) => {
      const cs = getComputedStyle(el)
      if (cs.overflowX !== 'visible' || el.closest('.m-table-wrap, .m-table-scroll, table, .aer-columns-menu, .m-filter-popover')) return false
      return el.scrollWidth > el.clientWidth + 2 && el.clientWidth > 0 && /hidden|clip/.test(cs.overflow)
    }).length
    return { viewport: window.innerWidth, page_scroll_width: doc.scrollWidth, horizontal_page_scroll: doc.scrollWidth > window.innerWidth + 1, clipped_elements: clipped }
  })
}

const bar = (page) => page.locator('[data-aer-filters="matrix"]')

const DP020 = 'b365fde8-d003-4ef6-80c3-4136fbd5587a'  // RMIT Diploma of Commerce (CRICOS 111278B), mandate 29 Oct 2026 12:23 section C
// Course detail for DP020, read-only: the country selector's order, India's resolution, the scholarships result and the evidence overlay
// (opened, its timeline counted, closed with Escape). Selecting a country only asks the resolver; nothing here edits or reads again.
async function courseDp020(p, prefix, shot) {
  await p.goto(`/#courses?id=${DP020}`)
  const blade = p.locator('aside.m-drawer-course')
  await blade.waitFor({ timeout: 60_000 })
  const select = blade.getByLabel('Country of prior education')
  await select.waitFor({ timeout: 60_000 })
  const order = (await select.locator('option').allTextContents()).filter((t) => t && t !== 'Choose…').slice(0, 6)
  await select.selectOption({ label: (await select.locator('option').allTextContents()).find((t) => /^India/.test(t)) })
  const outcome = blade.locator('[data-entry-resolution]')
  await outcome.waitFor({ timeout: 60_000 })
  await outcome.scrollIntoViewIfNeeded()
  const scholarships = blade.locator('[data-course-scholarships]')
  const scholarshipText = (await scholarships.count()) ? (await scholarships.first().innerText()).replace(/\s+/g, ' ').slice(0, 300) : null
  await shot(p, `${prefix}-dp020-india`, { country_order: order, india_outcome: await outcome.getAttribute('data-entry-resolution'),
    india_text: (await outcome.innerText()).replace(/\s+/g, ' ').slice(0, 300), scholarships: scholarshipText })
  const embedded = await p.locator('[data-course-audit]').count()  // the timeline section exists only inside the overlay
  await blade.locator('[data-course-evidence-open]').click()
  const dialog = p.getByRole('dialog')
  await dialog.waitFor({ timeout: 60_000 })
  await p.locator('[data-ca-kind]').first().waitFor({ timeout: 60_000 })
  const kinds = await p.locator('[data-ca-kind]').evaluateAll((els) => els.map((e) => e.getAttribute('data-ca-kind')))
  await shot(p, `${prefix}-dp020-evidence`, { timeline_entries: kinds.length, timeline_kinds: [...new Set(kinds)], timeline_in_blade_before_open: embedded })
  await p.keyboard.press('Escape')
  await dialog.waitFor({ state: 'detached', timeout: 10_000 })
}

// the shell's low-credit notice (when shown): its icon and first letter sit inside the viewport, nothing is cut at the left
async function bannerFacts(p) {
  return p.evaluate(() => {
    const b = document.querySelector('[data-credit-banner]')
    if (!b) return { shown: false }
    const r = b.getBoundingClientRect(); const range = document.createRange(); const t = [...b.querySelectorAll('*')].find((e) => /OpenRouter/.test(e.textContent || '') && !e.children.length) || b
    range.selectNodeContents(t); const tr = range.getBoundingClientRect()
    return { shown: true, left: Math.round(r.left), text_left: Math.round(tr.left), text_starts_inside: tr.left >= r.left && tr.left >= 0, horizontal_scroll: b.scrollWidth > b.clientWidth + 1, text: (b.innerText || '').slice(0, 120) }
  })
}

export async function aerTour({ page, browser, out, settle, fitHeight, masks, login, manifest, consoleErrors, baseURL }) {
  // a lighter wait than the review's settle (that one waits up to 45 s for a quiet network, which a polling shell never gives)
  const calm = async (p) => { await p.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {}); await p.waitForTimeout(1200)
    await p.locator('main .cf-skeleton-line, main [aria-busy="true"], .m-row-skeleton').first().waitFor({ state: 'detached', timeout: 10_000 }).catch(() => {}) }
  const shot = async (p, name, extra = {}) => {
    await calm(p)
    if (p.viewportSize().width > 800) await fitHeight(p)
    const file = `aer-${name}.png`
    await p.screenshot({ path: path.join(out, file), fullPage: true, mask: masks(p), maskColor: '#9ca3af' })
    manifest.push({ file, route: 'aer-tour', action: name, url: p.url(), layout: await layoutFacts(p), console_errors: consoleErrors.splice(0), ...extra })
    if (p.viewportSize().width > 800) await p.setViewportSize({ width: 1440, height: 1000 })
  }
  const aerCalls = []
  const watch = (p) => p.on('request', (r) => { if (r.url().includes('/rest/v1/rpc/admin_aer')) { try { const b = r.postDataJSON() || {}; aerCalls.push({ action: b.p_action, page_size: b.p_args?.page_size ?? null }) } catch { /* not JSON */ } } })
  watch(page)
  page.setDefaultTimeout(30_000)  // a control that never appears fails its step instead of holding the tour
  // a step that cannot finish is recorded with its reason and the tour goes on (the manifest says what was and was not exercised)
  const t0 = Date.now()
  const step = async (name, fn) => { const t = Date.now(); try { await fn(); manifest.push({ route: 'aer-tour', action: name, ok: true, seconds: Math.round((Date.now() - t) / 1000), at: Math.round((t - t0) / 1000) }) } catch (e) { manifest.push({ route: 'aer-tour', action: name, error: String(e?.message || e).slice(0, 300), seconds: Math.round((Date.now() - t) / 1000) }) } }

  // 1. Provider entry matrix: summary, then RMIT and India (status Active is the default)
  await step('matrix', async () => {
    await page.goto('/#entry-requirements')
    await page.locator('[data-aer-tile="active"] strong').waitFor({ timeout: 60_000 })
    await shot(page, '01-matrix-all')
    await pick(page, bar(page), /Provider/, 'RMIT', /RMIT/)
    await pick(page, bar(page), /Country/, 'India', /^India/)
    await page.locator('table[data-table="aer-matrix"] tbody tr[data-row]').first().waitFor({ timeout: 60_000 })
    await shot(page, '02-matrix-rmit-india', { rows_shown: await page.locator('table[data-table="aer-matrix"] tbody tr[data-row]').count() })
  })
  // 2. Columns menu open (show / hide), then closed again
  await step('columns', async () => {
    await page.locator('[data-aer-columns] summary').click()
    await shot(page, '03-matrix-columns-menu')
    await page.locator('[data-aer-columns] summary').click()
  })
  // 3. Row drawer: quote, stored copy, reading, history
  await step('drawer', async () => {
    await page.locator('table[data-table="aer-matrix"] tbody tr[data-row]').first().click()
    await page.locator('[data-aer-drawer="matrix"] [data-aer-quote]').waitFor({ timeout: 60_000 })
    await shot(page, '04-matrix-drawer')
    await page.locator('[data-aer-drawer="matrix"]').getByRole('button', { name: 'Close detail' }).click()
  })
  // 4. Waiting in Layer 4 (proposed) rows: what the website does not use
  await step('waiting', async () => {
    await page.goto('/#entry-requirements')
    await bar(page).getByRole('button', { name: /Clear filters/ }).first().click().catch(() => {})
    await pick(page, bar(page), /Status/, 'Waiting', /Waiting/)
    await page.locator('table[data-table="aer-matrix"] tbody tr').first().waitFor({ timeout: 60_000 })
    await shot(page, '05-matrix-waiting-in-layer-4')
    await bar(page).getByRole('button', { name: /Clear filters/ }).first().click().catch(() => {})
  })
  // 5. Course entry requirements
  await step('course', async () => {
    await page.goto('/#entry-requirements?tab=course')
    await page.locator('[data-aer-view="course"]').waitFor({ timeout: 60_000 })
    await shot(page, '06-course-requirements')
    const courseRow = page.locator('[data-aer-view="course"] table tbody tr').first()
    if (await courseRow.isVisible().catch(() => false)) { await courseRow.click(); await page.waitForTimeout(500); await shot(page, '07-course-drawer') }
  })
  // 6. Sources, reads and holds
  await step('sources', async () => {
    await page.goto('/#entry-requirements?tab=sources')
    await page.locator('[data-aer-view="sources"] table tbody tr').first().waitFor({ timeout: 60_000 })
    await shot(page, '08-sources-reads-holds')
  })
  // 7. Resolution inspection: RMIT Bachelor of Engineering (Honours) 0100714 for India, the developer guide's worked example
  await step('resolve', async () => {
    await page.goto('/#entry-requirements?tab=resolve')
    await page.locator('[data-aer-resolve-course]').fill('0100714')
    await page.locator('.aer-suggest button').first().click()
    await page.getByRole('button', { name: /Country of prior education/ }).click()
    await page.locator('.m-filter-popover input').fill('India')
    await page.locator('.m-filter-popover').getByRole('button', { name: /^India/ }).first().click()
    await page.locator('[data-aer-outcome]').waitFor({ timeout: 60_000 })
    await shot(page, '09-resolution-0100714-india')
  })

  // 7b. Course detail DP020 at desktop width (mandate 29 Oct 2026 12:23 section C)
  await step('course-dp020', async () => { await courseDp020(page, '15', shot) })

  // 8. Phone width: the same screens at 390 px (the page must not scroll sideways)
  await step('phone', async () => {
    const ctx = await browser.newContext({ baseURL, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true })
    const phone = await ctx.newPage()
    phone.setDefaultTimeout(30_000)
    phone.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 400)) })
    phone.on('pageerror', (e) => consoleErrors.push('pageerror: ' + String(e.message).slice(0, 400)))
    watch(phone)
    await login(phone)
    for (const [route, name, ready] of [['entry-requirements', '10-phone-matrix', '[data-aer-tile="active"] strong'], ['entry-requirements?tab=course', '11-phone-course', '[data-aer-view="course"]'],
      ['entry-requirements?tab=sources', '12-phone-sources', '[data-aer-view="sources"] table tbody tr'], ['entry-requirements?tab=resolve', '13-phone-resolve', '[data-aer-view="resolve"]']]) {
      await phone.goto('/#' + route)
      await phone.locator(ready).first().waitFor({ timeout: 60_000 })
      await shot(phone, name)
    }
    await phone.goto('/#entry-requirements')
    // a person taps a record once the list has loaded: loading rows (data-skeleton) are not records and open nothing (A5, 29 Oct 2026)
    const firstRow = phone.locator('table[data-table="aer-matrix"] tbody tr[data-row]').first()
    await firstRow.waitFor({ timeout: 60_000 })
    await firstRow.scrollIntoViewIfNeeded(); await firstRow.locator('td').nth(2).tap()  // a cell beside the sticky first column
    await phone.locator('[data-aer-drawer="matrix"] [data-aer-quote]').waitFor({ timeout: 60_000 })
    await shot(phone, '14-phone-drawer', { banner: await bannerFacts(phone) })
    await phone.locator('[data-aer-drawer="matrix"]').getByRole('button', { name: 'Close detail' }).tap()
    await phone.locator('[data-aer-drawer="matrix"]').waitFor({ state: 'detached', timeout: 10_000 })
    manifest.push({ route: 'aer-tour', action: 'phone-drawer-closed', ok: true })
    await courseDp020(phone, '16-phone', shot)
    await ctx.close()
  })
  const lists = aerCalls.filter((c) => /_list$/.test(c.action || ''))
  manifest.push({ route: 'aer-tour', action: 'reads', admin_aer_calls: aerCalls.length, list_reads: lists.length, largest_page_size: Math.max(0, ...lists.map((c) => Number(c.page_size) || 0)),
    writes: aerCalls.filter((c) => ['update', 'add', 'lifecycle', 'reread'].includes(c.action)).length })
}
