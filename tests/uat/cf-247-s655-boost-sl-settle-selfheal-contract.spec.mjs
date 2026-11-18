// Guards: Boost study load settlement heals itself (Platform Admin 18 Nov 2026 14:29 item 2, closed-loop rule of 16:10): before settling, rule l4-boost-sl-settle-v1 releases the page of any open reading whose last reading used an older prompt than the qualified one, so a worker deploy can never leave readings settled or stuck on an old prompt
// CF-247 S655. Migration 20261118193000_cf247_boost_sl_settle_selfheal. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations-archive/20261118193000_cf247_boost_sl_settle_selfheal.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf('$function$;', i)) }

test('pages last read with an older prompt are released before anything is settled', () => {
  const f = fn('security.boost_study_load_settle_rule_v1')
  const rel = f.indexOf("update pipeline.boost_extract_items x set state = 'released', note = 'read again: the last reading used an older prompt than ' || v_prompt")
  const settle = f.indexOf("v_res := security.layer4_boost_study_load_inbox_decide_v1(w.id::text, 'not_stated', null, v_reason);")
  expect(rel).toBeGreaterThan(-1)
  expect(settle).toBeGreaterThan(rel)
  expect(f).toContain("where r.status = 'open' and x.state in ('verified', 'rejected', 'failed')")
  expect(f).toContain('and s.prompt_version = v_prompt and s.id > r.staging_id))')
})

test('the replaced definition is guarded; the post-check leaves no open reading on an older prompt; nothing dropped', () => {
  expect(code).toMatch(/if v <> '[0-9a-f]{32}' then raise exception 'security\.boost_study_load_settle_rule_v1 is not the definition this migration replaces/)
  expect(code).toContain("raise exception 'post-check: an open reading still rests on a reading with an older prompt';")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
