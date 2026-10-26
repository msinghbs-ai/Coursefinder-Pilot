// Guards: CF-247 AU completion week step 1 (Platform Admin 26 Oct 2026 17:01): CRICOS end dates recorded so a deregistered provider is separable from a current one; publish eligibility is registered + live site
// Record: admin docs/platform/ui-audit/2026-10-26-au-completion-week.md section 4. Course retirement stays a Platform Admin approval;
// the consumer API is not touched; nothing is ended when the register edition looks truncated.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261026004000_cf247_au_register_end_dates.sql', 'utf8')
const fn = m.slice(m.indexOf('create or replace function security.layer1_register_end_dates_v1('), m.indexOf('comment on function security.layer1_register_end_dates_v1('))
const el = m.slice(m.indexOf('create or replace function security.au_publish_eligibility_v1()'), m.indexOf('comment on function security.au_publish_eligibility_v1()'))

test('every tunable is a setting (G2): switch, truncation guard, eligibility minimums', () => {
  for (const k of ['layer1.register_end_dates_on', 'layer1.register_end_dates_min_share', 'publish.eligible_min_current_courses', 'publish.eligible_min_site_pages'])
    expect(m).toContain(`('pipeline', '${k}', `)
  expect(fn).toContain("security.pipeline_num_v1('layer1.register_end_dates_on', 1) < 1")
  expect(fn).toContain("security.pipeline_num_v1('layer1.register_end_dates_min_share', 0.9)")
  expect(el).toContain("security.pipeline_num_v1('publish.eligible_min_current_courses', 1)")
  expect(el).toContain("security.pipeline_num_v1('publish.eligible_min_site_pages', 1)")
})

test('end dates: guard before any write; courses get the last listed date; providers end only when none of their courses is listed; restores', () => {
  const guard = fn.indexOf("v_listed::numeric / v_tracked < v_share")
  expect(guard).toBeGreaterThan(0)
  expect(guard).toBeLessThan(fn.indexOf('update catalogue.course_registrations'))
  expect(fn).toContain("coalesce((s.seen_at at time zone 'Australia/Sydney')::date,")
  // a recorded date is never moved by the fallback (retirement clears the register row state)
  expect(fn).toContain('and (cr.valid_to is null or (g.tracked and cr.valid_to is distinct from g.d));')
  expect(fn).toContain("set status = 'ended', valid_to = pv.last_listed")
  expect(fn).toContain('pv.listed = 0 and pv.last_listed is not null')
  expect(fn).toContain("set status = 'active', valid_to = null")
  expect(fn).toContain("update catalogue.course_registrations cr set valid_to = null")
  // course lifecycle (retirement) is not changed here: that stays the Platform Admin's approval
  expect(fn).not.toMatch(/update catalogue\.courses/)
  expect(fn).not.toMatch(/lifecycle_status\s*=/)
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})

test('eligibility is read-only: publish only when registered (not ended, courses listed) and the site answers; every hold has a cause and owner', () => {
  expect(el).toMatch(/language sql stable/)
  expect(el).not.toMatch(/\b(update|insert|delete)\b/i)
  expect(el).toContain("where p.publication_status = 'unpublished' and p.lifecycle_status = 'active'")
  expect(el).toContain("when d.status = 'mapped' and coalesce(d.kept_count, 0) >= security.pipeline_num_v1('publish.eligible_min_site_pages', 1) then 'publish'")
  for (const c of ['CRICOS registration ended', 'no course on the current register edition', 'site gave no course pages', 'no website on record', 'site not checked yet'])
    expect(el).toContain(c)
  expect(el).toContain("'Platform Admin: publish paste'")
})

test('job catalogued before it is scheduled (G1), first run in the migration', () => {
  expect(m.indexOf("('layer1-register-end-dates', 'Layer 1 register',")).toBeLessThan(m.indexOf("cron.schedule('layer1-register-end-dates'"))
  expect(m).toContain("$$select security.layer1_register_end_dates_v1()$$")
  expect(m.trim().endsWith('select security.layer1_register_end_dates_v1();')).toBe(true)
})
