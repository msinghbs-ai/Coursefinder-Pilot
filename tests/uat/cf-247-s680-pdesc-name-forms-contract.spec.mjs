// Guards: University description name forms pdesc-name-forms-v2 (Platform Admin 18 Nov 2026 17:03 item 1): the first-sentence name check also knows each name of a semicolon-separated list of trading names and the initials of a whole name (four letters or more); every earlier name form is kept, and the validation, the machine gate, the word lists and the admission are not changed by this rule.
// CF-247 S680. Migration 20261118203000_cf247_boost_providers_rules. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261118203000_cf247_boost_providers_rules.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name, end = '$function$;') => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf(end, i)) }

test('semicolon-separated trading names and a whole name\'s initials are name forms; earlier forms are kept', () => {
  const f = fn('security.pdesc_name_forms_v1', '$f$;')
  expect(f).toContain("cross join lateral unnest(array[n0] || regexp_split_to_array(n0, '\\s*;\\s*')) n")
  expect(f).toContain("cross join lateral unnest(array[n] || string_to_array(n, ',')) part")
  expect(f).toContain('cross join lateral unnest(array[btrim(part), b.bare, c.plain,')
  expect(f).toContain("case when part = n and position(';' in n) = 0 then")
  expect(f).toContain("case when length(string_agg(left(w, 1), '' order by o)) >= 4")
  expect(f).toContain("where w ~ '^[A-Z]'")
  expect(f).toContain('language sql immutable')
})

test('the live text is checked before it is replaced, and the forms are proved after', () => {
  expect(code).toContain("<> '655c3643ba0b4c25bdc7bfe4fa63c22c'")
  expect(code).toContain("raise exception 'security.pdesc_name_forms_v1 is not the text of 20261112023700; nothing applied';")
  expect(code).toContain("if not ('ICMS' = any (security.pdesc_name_forms_v1(array['International College of Management, Sydney; Aspire English']))")
  expect(code).toContain("security.pdesc_name_forms_v1(array['Monash University Pty Ltd']) @> array['Monash University', 'Monash University Pty Ltd']")
})

test('the rule changes no check, word list or admission, and writes no description', () => {
  expect(code).not.toMatch(/create or replace function security\.(provider_description_validate_v1|provider_description_machine_gate_v1|provider_description_machine_admit_v1|pdesc_machine_text_check)/)
  expect(code).not.toMatch(/pdesc\.machine_refused_words|pdesc\.min_sentences|update catalogue\.providers|insert into catalogue\./)
})
