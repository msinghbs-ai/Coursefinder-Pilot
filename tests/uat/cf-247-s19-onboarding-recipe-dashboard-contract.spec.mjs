// Guards: CF-247 v2.15.254 (S19): onboarding follow-ups. A course-page search switched off because it was built from another domain no longer blocks onboarding with a misleading error;
// CF-247 v2.15.254 (S19): onboarding follow-ups. A course-page search switched off because it was built from another domain no
// longer blocks onboarding with a misleading error; one switched off for the same website stops with a plain reason for a person.
// Dashboard "Waiting for you" drops the retired Flagged values and Fee rules and adds the onboarding rows.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261012010500_cf247_onboarding_recipe_off_dashboard.sql', 'utf8')

test('migration: other-domain switched-off search replaced; same-website one stops as recipe_off; guarded; nothing dropped', () => {
  expect(sql).toContain('pipeline.course_link_recipes.search_domain is distinct from excluded.search_domain')
  expect(sql).toContain("stop_reason = 'recipe_off'")
  expect(sql).toContain('live % differs from the definition this change replaces')
  expect(sql).toContain('v2.15.254 post-check: % not as intended')
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('migration: Dashboard waiting rows', () => {
  const w = sql.slice(sql.indexOf('FUNCTION public.admin_waiting_read'))
  expect(w).not.toContain("'key','flags'")
  expect(w).not.toContain("'key','rules'")
  expect(w).toContain("'key','onboarding_admit','label','Universities ready to admit'")
  expect(w).toContain("'key','onboarding_stopped','label','Onboarding stopped for a person'")
  expect(w).toContain("'href','#scholarships?tab=coverage'")
  expect(w).not.toContain('tab=publishing')
})

test('migration 10600: a proposal with no answer after 30 minutes is asked again, twice at most', () => {
  const s = fs.readFileSync('supabase/migrations/20261012010600_cf247_onboarding_proposal_stall_retry.sql', 'utf8')
  expect(s).toContain("or (d.status = 'proposing' and v_age > interval '30 minutes')) and o.attempts < 2 then")
  expect(s).toContain('live % differs from the definition this change replaces')
  expect(s).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('Providers › Onboarding explains the recipe_off stop', () => {
  const ui = fs.readFileSync('src/ProviderOnboarding.jsx', 'utf8')
  expect(ui).toContain("recipe_off:['Course-page search switched off'")
})
