// Guards: Atlas brief 26 Nov 2026 22:25 AEDT (Platform Admin live UAT of the StudySearch Portal), s1279: a Portal search card shows a short two-line course description only when the platform holds one (read-only, cut at a whole word, length from the setting portal.card_description_chars, never "Not recorded"), and a long provider name is clamped to two lines with its full text as the tooltip; G2 (the length is a setting), G3 (consumer API 75/48 untouched), manual locks and active cron unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261130023000_cf247_s1279_portal_card_description_snippet.sql'
const m = fs.readFileSync(MIG, 'utf8')
const src = p => fs.readFileSync(p, 'utf8')
const SRC = 'portal/src'

test('migration: read-only, guarded on the live cards body, nothing dropped, consumer API and locks untouched', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m)
  expect(m).not.toMatch(/\bdrop\s+(table|function|view|index|schema)\b/i); expect(m).not.toMatch(/\bdelete\s+from\b/i)
  expect(m).not.toMatch(/\b(insert\s+into|update|delete\s+from)\s+catalogue\./i)  // course rows are only read; S1-Data-Gaps owns the description writers
  expect(m).toContain("'2880886cc930e17946614e76057afe11'")
  expect(m).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(m).toContain('select count(*) from cron.job where active')
  expect(m).toContain('select count(*) from pipeline.manual_locks')
  expect(m).toContain('post-check: the number of active cron jobs changed'); expect(m).toContain('post-check: manual locks changed')
})

test('G2: the length is a Portal setting with a label, range, unit and used_by; the helper reads it', () => {
  expect(m).toMatch(/insert into pipeline\.platform_toolset_settings[\s\S]*'portal', 'card_description_chars'[\s\S]*to_jsonb\(220\), 80, 400, 'characters'/)
  expect(m).toContain("'Portal', 'public.portal_course_search_v1 (cards: description_snippet)'")
  expect(m).toContain("security.portal_setting_v1('card_description_chars')")
  expect(m).toMatch(/-- fixed: the setting's own default and range/)
  expect(m).toMatch(/revoke all on function portal\.description_snippet_v1\(text\) from public, anon, authenticated/)
})

test('the snippet is tidied, cut at a whole word with an ellipsis, and null when no description is held', () => {
  const h = m.slice(m.indexOf('create or replace function portal.description_snippet_v1'), m.indexOf('$function$;', m.indexOf('create or replace function portal.description_snippet_v1')))
  expect(h).toContain("'&#039;', ''''")
  expect(h).toContain("'&amp;', '&'"); expect(h).toContain("'\\s+', ' ', 'g'")
  expect(h).toMatch(/when t = '' then null/)
  expect(h).toMatch(/regexp_replace\(left\(t, n\), '\\s\+\\S\*\$', ''\)/); expect(h).toContain("|| '…'")
})

test('the cards function gains exactly one key, by one anchored edit of its live text', () => {
  expect(m).toContain("'description_snippet', portal.description_snippet_v1(c.description)")
  expect(m).toMatch(/s1279_patch\(v_def,[\s\S]*, 1\);\s*execute v_def;/)
  expect(m).toContain("raise exception 'guard: anchor")
  expect(m).toContain('post-check: a course with no description must carry a null snippet')
  expect(m).toContain('post-check: a course with a description has no usable snippet')
  expect(m).not.toContain('portal_course_search_v1(jsonb) returns')  // the search function is not replaced
})

test('portal: provider names are clamped to two lines with the full name as the tooltip, in cards and list rows', () => {
  const ui = src(`${SRC}/components/ui.jsx`)
  expect(ui).toContain("export const ProviderLine = ({ name, as: Tag = 'p', className = 'muted' })")
  expect(ui).toContain('<Tag className={`${className} clamp-2`} title={name}>{name}</Tag>')
  expect(src(`${SRC}/screens/Courses.jsx`)).toContain('<ProviderLine name={c.provider_name} />')
  expect(src(`${SRC}/screens/EntryRequirements.jsx`)).toContain('<ProviderLine name={c.provider_name} />')
  expect(src(`${SRC}/screens/Saved.jsx`)).toContain('<ProviderLine name={c.provider_name} />')
  expect(src(`${SRC}/components/CourseRow.jsx`)).toContain('<ProviderLine name={c.provider_name} as="span" className="muted small" />')
  const css = src(`${SRC}/styles.css`)
  expect(css).toMatch(/\.clamp-2 \{[^}]*-webkit-line-clamp:2[^}]*line-clamp:2[^}]*overflow:hidden/)
  expect(src(`${SRC}/components/DetailDrawer.jsx`)).toContain('{course.provider_name && <p className="muted">{course.provider_name}</p>}')  // the full name stays in Course details
})

test('portal: the description shows only when held, on the search card, and never says Not recorded', () => {
  const ui = src(`${SRC}/components/ui.jsx`)
  const d = ui.slice(ui.indexOf('export const DescSnippet'), ui.indexOf('export const IntlBadge'))
  expect(d).toContain("typeof c.description_snippet === 'string' && c.description_snippet.trim()")
  expect(d).toContain('<p className="desc-snippet clamp-2">{c.description_snippet}</p> : null')
  expect(d).not.toContain('Not recorded')
  const courses = src(`${SRC}/screens/Courses.jsx`)
  expect(courses).toContain('<DescSnippet c={c} />')
  expect(courses.indexOf('<DescSnippet c={c} />') < courses.indexOf('<div className="tags">')).toBe(true)
  expect(src(`${SRC}/styles.css`)).toContain('.desc-snippet {')
})
