// v2.15.116 Layer 4 › Batch rules: fee wording rules prepared, previewed, approved and run from the UI.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('Layer 4 has a Batch rules tab; rules are role-checked, never touch values entered by hand, and are logged', () => {
  expect(PAGES.layer4.tabs.map(t => t.key)).toEqual(['review', 'flags', 'sendback', 'rules', 'blocks'])
  const m = read('supabase/migrations/20260930140000_cf247_fee_wording_rules.sql')
  expect(m).toContain("if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required'")
  expect(m).toContain("if p_action in ('approve','run','pause','resume') and v_rank < 5 then raise exception 'PIM Operator role or above required to approve or run a rule'")
  expect(m).toContain("l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition'")
  expect(m).toContain("g.identity_basis in ('cricos_code','manual')")
  expect(m).toContain('if m.amounts > 1 then n_amb := n_amb + 1; continue; end if;')
  expect(m).toContain('insert into pipeline.layer4_mass_operations')
  for (const f of ['admin_fee_rules_read()', 'admin_fee_rule_preview(uuid, text, text)', 'admin_fee_rule_control(text, jsonb)']) {
    expect(m).toContain(`revoke all on function public.${f} from public, anon;`)
    expect(m).toContain(`grant execute on function public.${f} to authenticated;`)
  }
})

test.describe('mocked browser', () => {
  test('approve a draft, preview it, make a rule from a found wording and save it as a draft', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#layer-4-review?tab=rules')
    await expect(page.getByRole('tab', { name: 'Batch rules' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.locator('.fr-rules tbody tr')).toHaveCount(2)
    await page.getByRole('button', { name: 'Preview rule 1' }).click()
    await expect(page.locator('[data-preview-rule="1"] [data-preview]')).toContainText('214 courses would get a fee.')
    await page.getByRole('button', { name: 'Approve rule 1' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'approve')?.p_args).toEqual({ id: 1 })
    await expect(page.getByRole('status')).toContainText('Approved and run: 214 fees admitted.')
    await page.getByRole('button', { name: 'Make a rule from Indicative first-year tuition fee' }).click()
    const b = page.locator('[data-builder]')
    await expect(b).toContainText('University of Technology Sydney (UTS)')
    await expect(b.locator('[data-preview]')).toContainText('214 courses would get a fee.')
    await b.getByLabel('Fee period').selectOption('annual')
    await b.getByRole('button', { name: 'Save as draft' }).click()
    await expect.poll(() => page.l3calls.find(c => c.p_action === 'create')?.p_args).toMatchObject({ provider_id: 'p-uts', phrase: 'Indicative first-year tuition fee', basis: 'annual' })
  })
})
