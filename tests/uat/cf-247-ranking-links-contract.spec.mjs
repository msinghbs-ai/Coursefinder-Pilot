// Decision 208: QS and THE — filters by country, state, provider and link; linked providers open their record;
// a Curator links a ranked university with no provider; links are kept automatically (job ranking-link).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('database: automatic rules are exact or confirmed by two sources; anything else waits for a person', () => {
  const m = read('supabase/migrations/20261001180000_cf247_ranking_links_and_filters.sql')
  expect(m).toContain("if cardinality(v_ids) = 1 then v_method := 'exact_canonical_name_country'; end if;")
  expect(m).toContain("v_method := 'name_key_confirmed';")
  expect(m).toContain("'suggested_shared_words', round(c.score, 2), 'candidate'")
  expect(m).toContain("if v_cur is not null and v_cur <> p_provider then raise exception 'already linked to another provider'; end if;")
  expect(m).toContain("raise exception 'the provider must be active and in the same country as the ranked university';")
  expect(m).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'Curator role required'")
  expect(m).toContain("select cron.schedule('ranking-link', '37 * * * *', $$select security.ranking_link_auto_v1()$$);")
  expect(m).toContain("if v is distinct from '086eea02884a7a4b42a0beb00ba237be' then raise exception")
  expect(m).toContain("if v is distinct from 'e34209c2d0b480cf04c36ea8d6058b85' then raise exception")
  expect(m.toLowerCase()).not.toContain('delete from')
})

test('provider record shows QS and THE history', () => {
  const main = read('src/mature-main.jsx')
  expect(main).toContain("{type==='provider'&&data.id&&<ProviderRankings providerId={data.id} navigate={navigate}/>}")
  const rl = read('src/RankingLinks.jsx')
  expect(rl).toContain("api.providerRankingHistory(providerId)")
})

test.describe('browser: ranking filters and links', () => {
  test('filters send country, state, provider and link; provider opens its record', async ({ page }) => {
    await mockAdmin(page)
    const reads = []
    page.on('request', r => { if (r.url().endsWith('/rpc/admin_read')) { try { reads.push(r.postDataJSON()) } catch {} } })
    await page.goto('/#statistics-rankings?dataset=qs_wur&year=2027')
    const panel = page.locator('[data-react-ranking-viewer="1"]')
    await expect(panel).toContainText('37 linked to a provider')
    const bar = panel.locator('[data-ranking-filters]')
    await bar.getByRole('button', { name: /Country/ }).click()
    await bar.getByRole('button', { name: /^Australia/ }).click()
    await expect.poll(() => reads.some(b => b.p_operation === 'ranking_observations' && b.p_args?.country === 'Australia')).toBe(true)
    await bar.getByRole('button', { name: /State/ }).click()
    await bar.getByRole('button', { name: /^Victoria/ }).click()
    await expect.poll(() => reads.some(b => b.p_operation === 'ranking_observations' && b.p_args?.state === 'AU-VIC')).toBe(true)
    await bar.getByRole('button', { name: /^Link/ }).click()
    await bar.getByRole('button', { name: 'Not linked' }).click()
    await expect.poll(() => reads.some(b => b.p_operation === 'ranking_observations' && b.p_args?.link === 'not_linked')).toBe(true)
    await panel.getByRole('button', { name: 'The University of Melbourne' }).first().click()
    await expect(page).toHaveURL(/#providers\?id=p-mel/)
  })

  test('a Curator links a ranked university to a suggested provider', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#statistics-rankings?dataset=qs_wur&year=2027')
    const panel = page.locator('[data-react-ranking-viewer="1"]')
    await panel.getByRole('button', { name: 'Link', exact: true }).click()
    const picker = panel.locator('[data-ranking-link-picker]')
    await expect(picker).toContainText('Central Queensland University')
    await picker.locator('[data-candidate="p-cqu"]').getByRole('button', { name: 'Link' }).click()
    await expect.poll(() => page.l3calls.find(c => c.rankingLink)?.rankingLink).toEqual({ p_publisher_institution_id: 'pi-cqu', p_action: 'link', p_provider_id: 'p-cqu', p_note: null })
  })
})
