// Guards: F-AER.08 course identity (one provider, one exact title, one study level) for VET labels and printed training package codes (s1252); G3 no consumer API change; confirmed and rejected decisions never changed
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261129133000_cf247_s1252_vet_course_label_identity.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('one md5-guarded edit of the existing link function, three anchors, no new resolver', () => {
  expect(code).toContain("'f6ef02c506ddc1d842fa0437abfea4c6'")
  expect(code).toContain("pg_get_functiondef('security.entry_course_link_v1(uuid,text,text,uuid,text)'::regprocedure)")
  expect(code.match(/anchor count differs/g)?.length).toBe(3)
  expect(code).not.toMatch(/create (or replace )?(function|table)/i)
})

test('only labels the established level helper cannot read, with the existing mapper and the exact-title, level and single-course rules', () => {
  expect(code).toContain('cardinality(v_levels) = 0')
  expect(code).toContain('security.entry_label_levels_v1(p_label)')
  expect(code).toContain("'^[A-Za-z]{3}[0-9]{5}[A-Za-z]?[[:space:]]+'")
  expect(code).toContain("c.lifecycle_status = 'active'")
  expect(code).toContain('if cardinality(v_ids) = 1 then v_method := \'title\'; end if;')
  expect(code).toContain("p_label !~* '(conjoint|/)'")
})

test('decided links are never changed; no setting, drop, delete, consumer object or provider-specific code', () => {
  expect(code).toContain("state in ('confirmed','rejected')")
  expect(code).toContain("a confirmed or rejected decision changed")
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/platform_toolset_settings|public\.website_|public\.zoho_|\bapi\./)
  expect(code).not.toMatch(/80e8f5fd|dc671c35|fb0c76e5/)
  expect(m).toMatch(/^-- Replaces: security\.entry_course_link_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
