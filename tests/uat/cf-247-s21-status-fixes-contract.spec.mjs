// CF-247 v2.15.256 (S21): Platform Admin status review, 12 Oct 2026 13:06. Fixes agreed: 1 one targets refresh at a time; 2 a third,
// stronger pinned model before Layer 4 (qualified first; a person adds it to the order); 3 onboarding falls back to the university's
// central pages read with AI, proposed for a person to approve; 4 onboarding waits for found course pages; 5 catalogue cleanup (paste file).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const a = fs.readFileSync('supabase/migrations/20261012011100_cf247_targets_refresh_lock_onboarding_wait.sql', 'utf8')
const outside = s => s.slice(0, s.indexOf('CREATE OR REPLACE FUNCTION')) + s.slice(s.lastIndexOf('$function$;'))

test('11100: one refresh at a time; onboarding waits for found pages up to 6 hours; guarded; nothing dropped', () => {
  expect(a).toContain("if not pg_try_advisory_xact_lock(hashtext('cf247:firecrawl_targets_refresh')) then return 0; end if;")
  expect(a).toContain("and (v_age > interval '6 hours' or not exists (select 1 from pipeline.course_link_search s where s.provider_id = o.provider_id and s.state in ('queued', 'sent', 'found'))) then")
  expect(a).toContain('live % differs from the definition this change replaces')
  expect(outside(a)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

const b = fs.readFileSync('supabase/migrations/20261012011200_cf247_scholarship_ai_rules_third_model.sql', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('11200 + worker v0.20.3: proven value stands; nationality proves international; GPT-4.1 qualified, never switched on; waiting pages read again', () => {
  expect(b).toContain("p_answer := jsonb_set(p_answer, '{value}', v_prev.val) || jsonb_build_object('value_from', v_prev.model_code);")
  expect(b).toContain("'country', case when u.provider_id is not null then security.coverage_country(u.provider_id) end")
  expect(b).toContain("values ('gpt-4.1', 'openai/gpt-4.1', 'GPT-4.1', 'candidate', 30,")
  expect(b).toContain("elsif p_action = 'reviews_reread' then")
  // qualifying never adds it to the order or activates it
  expect(b.slice(b.lastIndexOf('$function$;'))).not.toMatch(/set_chain|activate|set_admission/)
  expect(b).toContain('live % differs from the definition this change replaces')
  expect(outside(b)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(w).toContain('v0.20.3 (12 Oct 2026, Platform Admin status review): an audience quote that names another country')
  expect(w).toContain('|| foreignNamed(a?.audience_quote, home))')
  expect(w).toContain('const checks = checkScholarshipAnswer(a, `${title} ${h1} ${text}`, it.country || null);')
})

const c = fs.readFileSync('supabase/migrations/20261012011300_cf247_central_pages_ai.sql', 'utf8')

test('11300 + worker v0.21.0: central pages read by a pinned model become proposals a person approves; catalogued job; nothing applied by the AI', () => {
  expect(c).toContain("values (1, 'gpt-4.1-mini', 'openai/gpt-4.1-mini',")
  expect(c).toContain("r := public.svc_provider_policy_record(q.fact_source_id, p_parsed);")
  expect(c).toContain("insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)\nvalues ('central-ai',")
  expect(c).toContain("perform cron.schedule('central-ai', '*/5 * * * *', 'select security.central_ai_fire_v1()')")
  expect(c).toContain("v_central_n := security.central_ai_enqueue_v1(o.provider_id)")
  expect(c).toContain("and pp.status = 'approved' and pp.decided_at >= coalesce(ob.started_at, ob.created_at));")
  // the AI never approves or applies: no approval or catalogue writes in the recording function
  const rec = c.slice(c.indexOf('create or replace function public.svc_central_ai_record'), c.indexOf('create or replace function security.central_ai_fire_v1'))
  expect(rec).not.toMatch(/status = 'approved'|course_english_requirements|course_intakes/)
  expect(c).toContain('live % differs from the definition this change replaces')
  expect(outside(c)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.21\.0"/)
  expect(w).toContain('if (mode === "central_ai") {')
  expect(w).toContain('if (!on(x.quote) || !has(x.ielts_overall, x.quote)) { dropped.push(lv); continue }')
  expect(w).toContain("provider: { require_parameters: true },\n    response_format: { type: \"json_schema\", json_schema: { name: kind, strict: true, schema } },")
})

test.describe('mocked browser', () => {
  test('Approve central pages shows under Needs a person with what to do', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#providers?tab=onboarding')
    const ob = page.locator('[data-provider-onboarding]')
    await expect(ob.locator('[data-onboarding-tile="needs_person"]')).toContainText('1 with central pages to approve')
    const row = ob.locator('[data-onboarding-row="ob-6"]')
    await expect(row).toContainText('Approve central pages')
    await expect(row.locator('[data-stop-help]')).toContainText('Approve or reject each in the Adapter builder (1.3)')
  })

  test('AI could not decide: read the waiting pages again asks for a reason', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?tab=aireview')
    const r = page.locator('[data-ai-review]')
    await r.locator('[data-ai-review-reread]').click()
    await expect(r.locator('[data-ai-review-reread-confirm]')).toBeDisabled()
    await r.getByLabel('Reason: read the waiting pages again').fill('New rules in v2.15.256')
    await r.locator('[data-ai-review-reread-confirm]').click()
    await expect(r.locator('[data-ai-review-note]')).toContainText('2 page(s) will be read again')
    const call = page.l3calls.find(x => x.scholarshipAi?.p_action === 'reviews_reread')
    expect(call.scholarshipAi.p_args).toEqual({ reason: 'New rules in v2.15.256' })
  })
})
