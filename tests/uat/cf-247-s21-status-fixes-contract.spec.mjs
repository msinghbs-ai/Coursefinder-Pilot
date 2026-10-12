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
