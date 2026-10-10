// Decision 212: domestic-only scholarships are not published; "up to" values are maxima; savings per year from the
// provider's annual international tuition fee.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('database: publishing check, admin confirmation, maximum values, per-year savings, all guarded', () => {
  const m = read('supabase/migrations-archive/20261002180400_cf247_scholarship_publishing_rules.sql')
  expect(m).toContain("then 'eligibility lists domestic students only' end,")
  expect(m).toContain("and coalesce(cr.value_json->>'by','')<>'scholarship_sweep' and 'international'=any(cr.value_codes))")
  expect(m).toContain("elsif p_action='confirm_international' then")
  expect(m).toContain("if coalesce(btrim(p_args->>'note'),'')='' then raise exception 'a note is required'; end if;")
  expect(m).toContain('add column if not exists award_value_is_maximum boolean not null default false')
  expect(m).toContain("elsif v_s.award_value_is_maximum then")
  expect(m).toContain("f.fee_type='provider_current_tuition'")
  expect(m).toContain("'amount_is_maximum',p.award_value_is_maximum,")
  for (const h of ['7a890c3c293159532a7dee6a660ddc8c', 'a287876beb1ce510cb7026b5b2edfb47', '940e8fde94883ad072f4f1ca8d28cfe6', 'a3ae9776e28279555f84a6c289aa030a', 'ec3b3087e53ef02f76097ed7a6bd6dd5', '0fc45dcbde2d72d11160f5c0a9b43864', '65fc940ff02813c2eb229c2f8f9ad7a1'])
    expect(m).toContain(`if v is distinct from '${h}' then raise exception`)
  expect(m.toLowerCase()).not.toContain('delete from')
  expect(m).not.toMatch(/set\s+publication_status\s*=\s*'published'/)
})

test('browser: Domestic only list; a Platform Admin confirms international students with a note', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.type() === 'prompt' ? d.accept('Page lists international students under Residency') : d.accept())
  await page.goto('/#layer-4-review?tab=publishing')
  await page.getByLabel('Show').selectOption('domestic_only')
  await expect(page.locator('[data-domestic-words]')).toContainText('Australian citizen')
  await expect(page.locator('[data-domestic-words]')).toContainText('taken off at the next daily review')
  await page.getByRole('button', { name: 'International students can apply to Women in STEM Scholarship' }).click()
  await expect.poll(() => page.l3calls.find(c => c.p_action === 'confirm_international')?.p_args).toEqual({ id: 'd1', note: 'Page lists international students under Residency' })
})
