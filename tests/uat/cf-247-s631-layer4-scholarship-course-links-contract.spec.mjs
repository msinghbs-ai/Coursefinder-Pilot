// Guards: Scholarship course links in Layer 4 (Platform Admin 18 Nov 2026 11:57): scholarships waiting for a course scope decision appear in Layer 4 › Inbox with a rule-based scope suggested from their own name and description; every choice is decided through the existing Course links decision (public.admin_scholarship_links_decide), never a new write path
// CF-247 S631. Migration 20261118143000_cf247_layer4_scholarship_course_links. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations-archive/20261118143000_cf247_layer4_scholarship_course_links.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf('$function$;', i)) }

test('the suggestion reads only the scholarship\'s own name and description; subject words are a setting', () => {
  const sug = fn('security.scholarship_scope_suggest_v1')
  expect(sug).toContain("v_text := s.name || ' ' || s.description;")
  expect(sug).toContain("security.toolset_setting('pipeline', 'scholarship.scope_suggest_subjects')")
  expect(sug).toContain("security.scholarship_scope_match(c.course_id, 'filter', v_filter)")
  expect(sug).not.toMatch(/openrouter|cascadeFetch|insert into scholarship\.|update scholarship\./)
  expect(code).toMatch(/\('pipeline', 'scholarship\.scope_suggest_subjects', [^\n]+\n[^\n]+\n\s+'list', /)
})

test('every choice goes through the Course links decision, Pipeline Operator or above', () => {
  const decide = fn('security.layer4_scholarship_links_inbox_decide_v1')
  expect(decide).toContain("v_r := public.admin_scholarship_links_decide(v_id, 'filter', g.filter,")
  expect(decide).toContain("v_r := public.admin_scholarship_links_decide(v_id, 'all', '{}'::jsonb, v_reason);")
  expect(decide).toContain("v_r := public.admin_scholarship_links_decide(v_id, 'none', '{}'::jsonb, v_reason);")
  expect(decide).not.toMatch(/insert into scholarship\.|update scholarship\.|delete from/)
  const kind = fn('security.layer4_scholarship_links_kind_v1')
  for (const k of ['accept_suggested', 'all_courses', 'no_courses']) expect(kind).toContain(`{"key": "${k}"`)
  expect((kind.match(/"rank": 4/g) || []).length).toBe(3)
  expect(code).toContain("values ('scholarship_course_links', 'kind', 'security.layer4_scholarship_links_kind_v1()', 'security.layer4_scholarship_links_inbox_counts_v1()', 'security.layer4_scholarship_links_inbox_page_v1(jsonb)',")
})

test('post-checks: a suggestion for every waiting scholarship, the Inbox count matches, nothing dropped', () => {
  expect(code).toContain("raise exception 'post-check: % waiting scholarships but % suggestions', v_wait, v_sugg;")
  expect(code).toContain("raise exception 'post-check: the Inbox count is not the waiting scholarships';")
  expect(code).toContain("raise exception 'post-check: the Inbox does not accept kind scholarship_course_links: %', v_hooks;")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
  expect(code).toContain('alter table pipeline.scholarship_scope_suggestions enable row level security;')
})
