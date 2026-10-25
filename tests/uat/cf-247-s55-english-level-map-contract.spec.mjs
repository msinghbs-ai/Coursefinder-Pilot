// Guards: CF-247 (S55) Decision 264: English levels named on course pages.
// CF-247 (S55) Decision 264: English levels named on course pages. Platform Admin 17 Oct 2026 ("Band reader (Recommended)"; 18:56 "Proceed
// with band reader"; "Level map first (Recommended)"). A course page names a level ("Band 2", "higher ELC requirements"); the approved policy
// gives that level's scores. Written-out policies are proposed only; a Platform Admin approves them.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261017070000_cf247_english_level_map.sql', 'utf8')
const adapters = fs.readFileSync('supabase/functions/coverage-sweep/adapters.ts', 'utf8')
const builder = fs.readFileSync('supabase/functions/coverage-sweep/builder.ts', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('Decision 264: guarded replacements; nothing dropped or deleted; proposals stay proposed', () => {
  expect(mig).toContain("<> 'c8dc54ee12e8bba301673cb738da5d68' then")
  expect(mig).toContain("<> '7f261e733c1b06ea48c534af9fcb2890' then")
  expect(mig).toContain("<> '74b92c10e3aca0eb76ccabe8808ad141' then")
  expect(mig).toMatch(/-- Replaces: /)
  expect(mig).toMatch(/-- Retires: nothing/)
  expect(mig).not.toMatch(/^(delete|drop|truncate)\b/im)
  expect(mig).toContain("'written out from the central page', fs.content_hash, fs.evidence_id, fs.url, v.style, v.proposal, 'proposed'")
  expect(mig).not.toMatch(/status\s*=\s*'approved'\s*,/)  // the change approves nothing
})

test('a level is written only where the course page names it; own readings, locks and pending Layer 4 items are kept', () => {
  expect(mig).toContain("security.english_level_key(g.candidates->'adapter_extra'->>'english_level') k")
  expect(mig).toContain("if r.locked or r.in_review then v_held := v_held + 1; continue; end if;")
  expect(mig).toContain("and (coalesce(e.source_requirement_key, '') not like 'policy:%'")
  expect(mig).toContain("'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code')")
  expect(mig).toContain("update catalogue.course_english_requirements e set status = 'withdrawn'")
  expect(mig).toContain("v_unknown := jsonb_set(v_unknown")
  expect(mig).toContain("select security.english_policy_in_force_all_v1(true); select security.english_level_apply_all_v1(true);")
  expect(mig).toContain("and pp.parser <> 'written out from the central page'")
})

test('worker v0.28.0 reads english_level as an adapter field', () => {
  expect(adapters).toMatch(/EXTRA_FIELDS = \[[^\]]*"english_level"(, "majors")?\]/)
  expect(builder).toMatch(/PATTERN_FIELDS = \[[^\]]*"english_level"(, "majors")?\]/)
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(28|29|[3-9]\d)\.\d+";/)
  expect(mig).toContain("'other_requirements', 'english_level']")
})

const fix = fs.readFileSync('supabase/migrations/20261017080000_cf247_english_level_own_differs.sql', 'utf8')
test('Decision 264 fix: a course whose own score differs from its level keeps its own reading only', () => {
  expect(fix).toContain("<> '4c44713235dd2ee97867ca1e37bb9db1' then")
  expect(fix).toContain("v_own_differs := v_own_differs + 1;")
  expect(fix).toContain("and e.notes like 'English level %Decision 264%'")
  expect(fix).not.toMatch(/^(delete|drop|truncate)\b/im)
})
