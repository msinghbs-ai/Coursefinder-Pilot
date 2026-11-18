// Guards: Scholarship course links resolved by rule (Platform Admin 18 Nov 2026 13:06): every waiting scholarship gets a deterministic course scope from its own name and description, All courses only for explicit university-wide wording with no restriction, No courses when not course-specific, applied under the automated rule authority through the existing apply function with a decision reason and a Layer 4 audit row each
// CF-247 S636. Migration 20261118153000_cf247_scholarship_scope_auto_decide. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261118153000_cf247_scholarship_scope_auto_decide.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf('$function$;', i)) }

test('the scope comes from the scholarship\'s own name first; word lists, aliases and patterns are settings', () => {
  const sug = fn('security.scholarship_scope_suggest_v1')
  expect(sug).toContain("v_name := s.name; v_text := s.name || ' ' || s.description;")
  expect(sug).toContain("if cardinality(v_subj) = 0 and not v_name_code then")
  for (const k of ['scope_suggest_subjects', 'scope_suggest_aliases']) expect(sug).toContain(`security.toolset_setting('pipeline', 'scholarship.${k}')`)
  expect(sug).not.toMatch(/openrouter|insert into scholarship\.|update scholarship\./)
  for (const k of ['scope_suggest_aliases', 'scope_all_patterns', 'scope_none_patterns']) expect(code).toMatch(new RegExp(`\\('pipeline', 'scholarship\\.${k}', [^\\n]+\\n[^\\n]+\\n\\s+'list', `))
})

test('the decision order: not course-specific, own scope, explicit university-wide, otherwise none', () => {
  const d = fn('security.scholarship_scope_auto_decide_v1')
  const i = (s) => { const n = d.indexOf(s); expect(n, s).toBeGreaterThan(-1); return n }
  const none = i("'scholarship.scope_none_patterns'"), own = i("elsif (g->>'matched')::int > 0 then"), all = i("'scholarship.scope_all_patterns'")
  expect(none).toBeLessThan(own); expect(own).toBeLessThan(all)
  expect(d).toContain("if v_hit is not null and jsonb_array_length(g->'levels') = 0 and jsonb_array_length(g->'subjects') = 0 then")
  expect(d).toContain("v_reason := 'Auto-applied deterministic title/description scope rule: ' || v_rule")
})

test('applied as the Course links decision applies it: system actor, existing apply function, an audit row each', () => {
  const d = fn('security.scholarship_scope_auto_decide_v1')
  expect(d).toContain('v_actor uuid := security.system_actor_id();')
  expect(d).toContain('v_res := security.scholarship_scope_apply_v1(p_scholarship_id, v_actor);')
  expect(d).toContain("values ('scholarship_course_scope', 'scope_decision_' || v_decision, v_actor,")
  expect(d).toContain("'CF-CHG-20260915-247'")
  expect(d).not.toMatch(/insert into scholarship\.|update scholarship\.|delete from/)
  expect(code).not.toMatch(/create or replace function security\.scholarship_scope_apply_v1/)
})

test('post-checks: nothing left waiting, an audit row per decision, the Inbox empty, nothing dropped', () => {
  expect(code).toContain("raise exception 'post-check: % scholarships still wait for a course scope', v_left;")
  expect(code).toContain("raise exception 'post-check: % decisions but % audit rows', v_n, v_ops;")
  expect(code).toContain("raise exception 'post-check: All courses without university-wide wording';")
  expect(code).toContain("raise exception 'post-check: Scholarship course links items remain in the Inbox';")
  expect(code).toMatch(/if v <> '[0-9a-f]{32}' then raise exception 'security\.scholarship_scope_suggest_v1 is not the definition/)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})

test('correction 20261118163000: not-course-specific wording read in the name only; description words added when the name keeps no course; only rule decisions redone', () => {
  const fix = fs.readFileSync('supabase/migrations/20261118163000_cf247_scholarship_scope_auto_fix.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  const f = (name) => { const i = fix.indexOf(`create or replace function ${name}(`); return fix.slice(i, fix.indexOf('$function$;', i)) }
  expect(f('security.scholarship_scope_auto_decide_v1')).toContain("where position(lower(p) in lower(s.name)) > 0 limit 1;")
  expect(f('security.scholarship_scope_suggest_v1')).toContain("if v_match = 0 and cardinality(v_subj) > 0 and not v_name_code then")
  expect(f('security.scholarship_scope_suggest_v1')).toContain("c.status <> 'superseded' and co.provider_id = sc.provider_id")
  expect(fix).toContain("where d.decided_by = security.system_actor_id() and d.reason like 'Auto-applied deterministic title/description scope rule:%';")
  expect(fix).toContain("raise exception 'post-check: a corrected scholarship still keeps no course';")
  expect(fix).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
