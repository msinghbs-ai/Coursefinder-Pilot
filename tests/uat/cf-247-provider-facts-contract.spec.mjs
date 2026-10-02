// Decision 205: institution-level sources (fee schedules, English policies, academic calendars). Nothing is written to
// the catalogue by the worker; fee rows need the course code and the amount on the same row and a basis from the heading.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')

test('worker: provider_facts searches, reads as evidence, parses fee rows; budgets respected', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('if (mode === "provider_facts") {')
  expect(w).toContain('await useFc("provider_facts_search", it.provider_id, it.query)')
  expect(w).toContain('await useFc("provider_facts_scrape", it.provider_id, it.url)')
  expect(w).toContain('if (codes.length !== 1) continue;')
  expect(w).toContain('if (!basis) return;')
  expect(w).not.toMatch(/provider_facts[\s\S]{0,4000}svc_coursefacts_apply_record/)
})

test('database: sources, queue for top 150, fee rows kept (never deleted), no catalogue writes', () => {
  const m = read('supabase/migrations/20261001178000_cf247_provider_fact_sources.sql')
  expect(m).toContain('group by c.provider_id order by count(*) desc limit 150')
  expect(m).toContain("update pipeline.provider_fee_rows set current = false where source_id = p_id and current;")
  expect(m.toLowerCase()).not.toContain('delete from')
  expect(m).not.toContain('catalogue.course_fees')
  for (const f of ['svc_provider_facts_search_next(int)', 'svc_provider_facts_read_next(int)'])
    expect(m).toContain(`grant execute on function public.${f} to service_role;`)
})

// 1 Oct 2026: fee pages link the real schedule (PDF); the schedule continues across page breaks in tables whose first
// row is a course row, and section rows ("| FACULTY OF ... |  |  |") sit inside tables.
async function feeParser() {
  const { transform } = await import('esbuild')
  const w = read('supabase/functions/coverage-sweep/index.ts')
  const src = w.slice(w.indexOf('const FEE_CODE'), w.indexOf('Deno.serve('))
  const { code } = await transform(src, { loader: 'ts', format: 'esm' })
  return import('data:text/javascript;base64,' + Buffer.from(code).toString('base64'))
}

test('parser: schedule split across pages and section rows keep the annual heading', async () => {
  const { parseFeeRows } = await feeParser()
  const md = [
    '# 2027 Schedule of tuition fees (International)', '',
    '| PROGRAM | CRICOS CODE | ANNUAL FEE(AUD) |', '| --- | --- | --- |', '| FACULTY OF LAW AND BUSINESS |  |  |',
    '| Bachelor of Accounting and Finance | 079454F | $36,016 |', '',
    '069051G $33,360 FACULTY OF EDUCATION AND ARTS', '',
    '| Bachelor of Arts | 001300B | $36,624 |', '| --- | --- | --- |', '| Bachelor of Arts/Bachelor of Global Studies | 074606B | $36,624 |', '',
    '| FACULTY OF HEALTH SCIENCES |  |  |', '| --- | --- | --- |', '| Bachelor of Nursing | 001293G | $39,672 |', '',
    '| Exchange(1 semester) | 078736D | NA |', '| --- | --- | --- |'].join('\n')
  const r = parseFeeRows(md)
  expect(r.rows.map(x => `${x.course_code}:${x.amount}:${x.basis}:${x.fee_year}`)).toEqual(
    ['079454F:36016:annual:2027', '001300B:36624:annual:2027', '074606B:36624:annual:2027', '001293G:39672:annual:2027'])
})

test('parser: heading-less tables never borrow a heading with a different number of columns', async () => {
  const { parseFeeRows } = await feeParser()
  const md = ['| Course | Code | Annual fee 2027 |', '| --- | --- | --- |', '| A | 079454F | $36,016 |', '',
    '| B | 001300B | $36,624 | $99,000 |', '| --- | --- | --- | --- |'].join('\n')
  expect(parseFeeRows(md).rows.map(x => x.course_code)).toEqual(['079454F'])
})

test('linked documents: own-site fee PDFs only, newest first; refund policies and other sites ignored', async () => {
  const { feeLinks } = await feeParser()
  const page = '[Download 2026 international fees schedule (PDF)](https://www.acu.edu.au/media/2026-schedule-of-tuition-fees.pdf?rev=1)\n' +
    '[Download 2027 international fees schedule (PDF)](https://www.acu.edu.au/media/acu-2027-schedule-of-tuition-fees.pdf)\n' +
    '[Fee refund policy](https://www.acu.edu.au/policy/fee-refund.pdf) [x](https://other.example.com/fees-2027.pdf) [Course guide](https://www.acu.edu.au/guide.pdf)'
  expect(feeLinks(page, 'https://www.acu.edu.au/study/fees')).toEqual([
    { url: 'https://www.acu.edu.au/media/acu-2027-schedule-of-tuition-fees.pdf', year: 2027 },
    { url: 'https://www.acu.edu.au/media/2026-schedule-of-tuition-fees.pdf?rev=1', year: 2026 }])
})

test('database: fee proposals need a Platform Admin; only courses without a current fee are written', () => {
  const m = read('supabase/migrations/20261001179200_cf247_provider_fee_proposals.sql')
  expect(m).toContain("if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required'")
  expect(m).toContain("for x in select * from security.provider_fee_proposal_rows(p_source_id) where outcome = 'new' loop")
  expect(m).toContain("when cur.amount is not null then 'differs'")
  expect(m).toContain("l.field_code = 'provider_current_tuition_validation' and l.status = 'pending') then 'in_review'")
  expect(m).toContain("where f.kind = 'fee_schedule'")
  expect(m.toLowerCase()).not.toContain('delete from')
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('rpc("svc_provider_facts_read_record_v2"')
  expect(w).toContain('p_links: links')
})

test.describe('browser: fee schedules panel', () => {
  test('Platform Admin sees totals, opens rows and approves', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#layer-4-review?tab=attributes')
    const fs = page.locator('[data-fee-schedules]')
    await expect(fs).toContainText('Waiting for approval')
    await expect(fs.locator('[data-doc="fs2"]')).toContainText('20 fees added')
    await fs.getByRole('button', { name: 'Australian Catholic University' }).click()
    await expect(fs.locator('[data-fee-rows] [data-outcome="differs"]')).toContainText('Different fee on record (not changed)')
    await fs.locator('[data-doc="fs1"]').getByRole('button', { name: 'Approve' }).click()
    await expect.poll(() => page.l3calls.find(c => c.feeDecide)?.feeDecide).toEqual({ p_source_id: 'fs1', p_action: 'approve', p_note: null })
  })

  test('Pipeline Operator sees the panel but cannot decide; viewer does not see it', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 4 })
    await page.goto('/#layer-4-review?tab=attributes')
    const fs = page.locator('[data-fee-schedules]')
    await expect(fs.locator('[data-doc="fs1"]')).toContainText('Waiting for a Platform Admin')
    await expect(fs.getByRole('button', { name: 'Approve' })).toHaveCount(0)
  })

  test('viewer: no fee schedules panel', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 1 })
    await page.goto('/#coverage?tab=attributes')
    await expect(page.getByText('By area: providers, courses, campuses and scholarships')).toBeVisible()
    await expect(page.locator('[data-fee-schedules]')).toHaveCount(0)
  })
})

test('database: provider facts scheduled; Firecrawl guard follows the balance Firecrawl reports', () => {
  const s = read('supabase/migrations/20261001179400_cf247_provider_facts_schedule.sql')
  expect(s).toContain(`select cron.schedule('provider-facts', '*/10 * * * *',`)
  expect(s).toContain('"mode":"provider_facts","search_limit":12,"read_limit":8')
  const b = read('supabase/migrations/20261001179500_cf247_firecrawl_observed_balance.sql')
  expect(b).toContain("if v is distinct from '5f76be10ad2334c9f550421e0c2fb611' then raise exception")
  expect(b).toContain("v_remaining:=least(v_remaining, coalesce((select greatest(o.remaining_units")
  expect(b).toContain("o.observed_at>now()-interval ''2 hours''")
  expect(b).toContain("https://api.firecrawl.dev/v1/team/credit-usage")
  expect(b.toLowerCase()).not.toContain('delete from')
})
