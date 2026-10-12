// CF-247 v2.15.256 (S21): Platform Admin status review, 12 Oct 2026 13:06. Fixes agreed: 1 one targets refresh at a time; 2 a third,
// stronger pinned model before Layer 4 (qualified first; a person adds it to the order); 3 onboarding falls back to the university's
// central pages read with AI, proposed for a person to approve; 4 onboarding waits for found course pages; 5 catalogue cleanup (paste file).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

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
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.20\.3"/)
  expect(w).toContain('|| foreignNamed(a?.audience_quote, home))')
  expect(w).toContain('const checks = checkScholarshipAnswer(a, `${title} ${h1} ${text}`, it.country || null);')
})
