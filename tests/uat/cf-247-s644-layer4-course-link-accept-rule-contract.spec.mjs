// Guards: Course link rule l4-link-accept-v1 (Platform Admin 18 Nov 2026 14:25 and 14:29 item 3): waiting Course link items about an official page are decided from the course-page binder's own proof (use a proved page, enter another proved page, refuse a page the binder or the finder refused) through the existing decision path under the system automation account, never a page with an older year in its address or one refused before; tied, unread, old-year and locked items wait for a person, and an audit share of finder refusals is left for a person
// CF-247 S644. Migration 20261118173000_cf247_layer4_course_link_accept_rule. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261118173000_cf247_layer4_course_link_accept_rule.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf('$function$;', i)) }

test('the classification rests on the binder proof and the finder refusal; old years, earlier refusals and manual locks are never used', () => {
  const c = fn('security.layer4_course_link_accept_check_v1')
  expect(c).toContain("where r.status = 'pending' and r.entity_type = 'course' and r.field_code = 'official_course_url'")
  expect(c).toContain("(p.status = 'bound' and p.read_status = 'read'")
  expect(c).toContain("p.identity_basis = any (security.pipeline_list_v1('layer4.link_accept_identity_bases'))")
  expect(c).toContain("when x.locked then 'hold'")
  expect((c.match(/>= x\.yr/g) || []).length).toBe(2)
  expect(c).toContain('not exists (select 1 from pipeline.page_rejections j where j.course_id = x.entity_id and lower(j.url) = lower(x.burl))')
  expect(c).toContain("when x.ps = 'mismatch' and x.purl <> '' and lower(x.burl) = lower(x.purl) then 'refuse'")
  expect(c).toContain("when x.grp in ('finder_title_mismatch', 'finder_shared_or_list_page')")
  expect(c).toContain("else 'hold' end act")
  expect(c).toContain("security.pipeline_num_v1('layer4.link_accept_audit_pct', 5)")
  expect(c).not.toMatch(/insert into|update |delete from/)
})

test('decisions go through the existing decision path under the system automation account, with the rule named', () => {
  const r = fn('security.layer4_course_link_accept_rule_v1')
  expect(r).toContain("v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';")
  expect(r).toContain("perform set_config('request.jwt.claim.sub', v_sys::text, true);")
  expect(r).toContain("when 'use' then public.layer4_review_decide(w.item_id, 'approve', v_reason, null)")
  expect(r).toContain("when 'enter' then public.layer4_review_decide(w.item_id, 'edit_and_approve', v_reason, to_jsonb(w.page_url))")
  expect(r).toContain('else security.layer4_course_link_refuse_v1(w.item_id, v_reason) end;')
  expect(r).toContain("[rule l4-link-accept-v1]")
  expect(r).toContain("if coalesce(p_apply, false) and not v_on then raise exception 'layer4.link_accept_rule_on is 0: the rule only counts'")
  expect(r).toContain("if w.action = 'hold' then v_hold := v_hold + 1; continue; end if;")
  expect(r).toContain("'audit sample of rule l4-link-accept-v1 (a person decides)'")
  expect(r).not.toMatch(/insert into catalogue\.|update catalogue\./)
})

test('the job is hourly from settings; the first run must decide and is stopped if many decisions fail; nothing dropped', () => {
  expect(code).toContain("select cron.schedule('layer4-link-accept', '41 * * * *',")
  expect(code).toContain("security.pipeline_num_v1(''layer4.link_accept_batch'', 400)::int, true)")
  expect(code).toContain("raise exception 'post-check: the rule decided nothing: %', v;")
  expect(code).toContain("raise exception 'post-check: a rule decision is not recorded under the system automation account';")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
