// Guards: SS-Programme-Control 27 Nov 2026 21:08 AEDT, approved scoped exception 2 (VU course-specific scholarship calculation from an exact, evidence-backed course-to-tier mapping; no fuzzy title matching, no record-level maximum percentage)
// CF-247 s1322. supabase/migrations/20261130203000_cf247_s1322_scholarship_course_tiers.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130203000_cf247_s1322_scholarship_course_tiers.sql', 'utf8')

test('a tier is assigned exactly: its label is the course title (optional trailing code) or the single catch-all, with evidence and a percentage', () => {
  expect(sql).toContain("v_name := lower(regexp_replace(btrim(regexp_replace(t.label, '\\s*\\([A-Za-z0-9]{2,12}\\)\\s*$', '')), '\\s+', ' ', 'g'));")
  expect(sql).toContain("= v_name;")
  expect(sql).not.toMatch(/similarity\(|levenshtein|pg_trgm|ilike '%|%' \|\|/)
  expect(sql).toContain("if v_n <> 1 then v_skip := v_skip || jsonb_build_object('tier', t.tier_code, 'why', format('the label names %s mapped course(s)', v_n)); continue; end if;")
  expect(sql).toContain("if v_all_n = 1 then v_all := t.id; else")
  expect(sql).toContain("if t.evidence_id is null or t.percentage is null then")
  expect(sql).toContain("mm.mapping_state = 'mapped'")
})

test('the calculation uses the assigned tier\'s exact percentage; the record-level "up to" stops only courses with no tier', () => {
  expect(sql).toContain("if md5(d) <> 'c12328425158de6865cdd664c298e52f' then")
  expect(sql).toContain("v_pct := coalesce(v_tier.percentage, v_s.award_percentage);")
  expect(sql).toContain("'elsif v_tier.id is null and v_s.award_value_is_maximum then'")
  expect(sql).toContain("'if v_pct is null or (v_tier.id is null and v_s.award_value_type is distinct from ''percentage'') then'")
  expect(sql).toContain("''tier_code'',v_tier.tier_code")
})

test('applied to the approved scope only, with post-checks; no drop or delete; consumer API, locks, Layer 4 and cron checked', () => {
  expect(sql.match(/assign_course_tiers_v1\('[0-9a-f-]{36}', true\)/g)).toEqual(["assign_course_tiers_v1('c377de6f-87c2-5e7e-a130-e68a6c323884', true)"])
  expect(sql).toContain("if (v->>'assigned')::int <> 14 then")
  expect(sql).toContain("f.calculation_status = 'award_not_structured'")
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|\btruncate\s+/i)
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toMatch(/comment on table scholarship\.course_tier_assignments is/)
  expect(sql).toMatch(/-- Replaces: scholarship\.refresh_course_financial_calculation/)
  expect(sql).toMatch(/-- Retires: nothing\./)
})
