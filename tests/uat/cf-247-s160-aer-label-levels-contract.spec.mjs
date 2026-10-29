// Guards: CF-247 AER W19 (Platform Admin mandate 29 Oct 2026 12:23, A3): a published matrix level label that names several levels counts for each (DP020 Diploma finds RMIT "Diploma/Associate degrees" rows); resolver rules 3 and 4, its step-5 reason and Resolution inspection match the course level or a level named in the printed label; mapping only, nothing inferred; rules, settings and consumer API shape unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029060000_cf247_aer_label_levels.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('every level a printed label names, mapped part by part with the existing mapping', () => {
  expect(code).toContain('create or replace function security.entry_label_levels_v1(p_label text) returns uuid[]')
  expect(code).toContain("from regexp_split_to_table(coalesce(p_label, ''), '\\s*(/|,|&|\\mand\\M|\\mor\\M)\\s*', 'i') part")
  expect(code).toContain('select security.entry_level_map_v1(btrim(part)) l')
  expect(code).toContain('union all select security.entry_level_map_v1(p_label)) z')
})

test('the resolver and the inspector match the course level or a level named in the label (md5-guarded, three places each)', () => {
  expect(code).toContain("select pg_temp.edit_n('security.entry_resolve_v1(uuid,text)', '8281a03fc85dcc1c5be19d86ad3ee3a0', array[")
  expect(code).toContain('$n$(m.study_level_id = any (v_levels) or security.entry_label_levels_v1(m.level_label) && v_levels)$n$]], array[3]);')
  expect(code).toContain("select pg_temp.edit_n('public.admin_aer(text,jsonb)', '744cb0173b8ea0f8092d5bcc9a6268b1', array[")
  expect(code).toContain('$n$(m0.study_level_id = any (v_levels) or security.entry_label_levels_v1(m0.level_label) && v_levels)$n$]], array[3]);')
  // no course-, provider- or country-specific code; no setting, rule or consumer API change
  expect(code).not.toMatch(/b365fde8|8e1adb6c|'IN'|DP020/)
  expect(code).not.toMatch(/platform_toolset_settings|create or replace function (public\.website_|public\.zoho_|api\.)/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(m).toMatch(/^-- Replaces: security\.entry_resolve_v1, public\.admin_aer/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
