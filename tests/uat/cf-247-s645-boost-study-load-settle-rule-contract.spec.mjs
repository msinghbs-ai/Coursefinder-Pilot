// Guards: Boost study load settlement rule l4-boost-sl-settle-v1 (Platform Admin 18 Nov 2026 14:29 item 2): an open Boost study load reading is settled only after its page was read again with the current qualified prompt, as Not stated only when that re-read states none or is refused again by the page check, through the Layer 4 Inbox decision under the system automation account with the rule and the findings as its reason; a reading not yet read again waits
// CF-247 S645. Migration 20261118183000_cf247_boost_study_load_settle_rule. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261118183000_cf247_boost_study_load_settle_rule.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf('$function$;', i)) }

test('only readings read again with the current qualified prompt are settled, and only as Not stated', () => {
  const f = fn('security.boost_study_load_settle_rule_v1')
  expect(f).toContain("where q.service_code = 'boost_extract' and q.status = 'qualified' order by q.prompt_version desc limit 1")
  expect(f).toContain('and s.evidence_id is not distinct from r.evidence_id and s.prompt_version = v_prompt and s.id > r.staging_id order by s.id desc limit 1) n on true')
  expect(f).toContain("and (n.worker_status = 'rejected' or (n.worker_status = 'verified' and n.answer->>'study_load' is null))")
  expect(f).toContain("v_res := security.layer4_boost_study_load_inbox_decide_v1(w.id::text, 'not_stated', null, v_reason);")
  expect(f).not.toMatch(/'accept_full_time'|'accept_part_time'|'accept_both'|update catalogue\./)
})

test('decided under the system automation account with the rule and the findings as the reason; the feed closes superseded readings first', () => {
  const f = fn('security.boost_study_load_settle_rule_v1')
  expect(f).toContain("v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';")
  expect(f).toContain("perform set_config('request.jwt.claim.sub', v_sys::text, true);")
  expect(f).toContain('[rule l4-boost-sl-settle-v1] Not stated: the page was read again with %s')
  expect(f).toContain('perform security.boost_study_load_review_feed_v1();')
  expect(f).toContain("if security.pipeline_num_v1('boost.sl_settle_on', 0) < 1 or v_lim = 0 then")
})

test('the job runs from settings; the first run must not fail; nothing dropped', () => {
  expect(code).toContain("select cron.schedule('layer4-boost-sl-settle', '7,37 * * * *',")
  expect(code).toContain("security.pipeline_num_v1(''batch.boost_sl_settle'', 400)::int")
  expect(code).toContain("raise exception 'post-check: % settlements failed: %', v->>'failed', v;")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
