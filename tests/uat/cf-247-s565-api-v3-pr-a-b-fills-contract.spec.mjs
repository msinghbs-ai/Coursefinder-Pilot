// Guards: API v3 PR A and PR B fills (Platform Admin 16 Nov 2026 16:52 decisions; 21:03 pull-forward): primary campus only on an exact CRICOS registered-address match to one active campus and never over an existing primary (D-4); campus-null reason from stored evidence only; study load from verbatim page quotes only, never from delivery mode (REQ-52); count-only unless applied, audited, no updated_at change, migration fills nothing
// CF-247 S565. Migration 20261116180000_cf247_api_v3_pr_a_b_fills.
// G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116180000_cf247_api_v3_pr_a_b_fills.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('PR A1 primary campus: CRICOS registered address, exactly one active campus, never over an existing primary', () => {
  expect(code).toContain("r.registration_scheme = 'cricos'")
  expect(code).toContain("k.status = 'active'")
  expect(code).toContain("set is_primary = true, primary_basis = 'cricos_head_office'")
  expect(code).toContain('where c.n = 1 and not c.has_primary')
})

test('PR A2 campus-null reason: only the five allowed codes, from delivery mode online or the stored campus reading', () => {
  for (const c of ['online_only_no_campus', 'not_published_by_provider', 'pending_extraction', 'not_listed_on_register', 'source_unavailable']) expect(code).toContain(`'${c}'`)
  expect(code).toContain("left join pipeline.course_attribute_coverage a on a.course_id = c.id and a.attribute = 'campus'")
  expect(code).toContain("update catalogue.courses c set empty_reason_code = null")
})

test('PR B study load: verbatim quote only, never delivery mode, never over a register or manual value', () => {
  expect(code).toContain("where f.state = 'filled' and f.field in ('duration', 'intakes', 'delivery') and f.quote is not null")
  expect(code).toContain("full[- ]?time[- ]equivalent")
  expect(code).toContain("coalesce(c.study_load_source, 'provider_page') = 'provider_page'")
  const pr_b = code.slice(code.indexOf('security.course_study_load_stage1_v1(p_apply'))
  expect(pr_b.slice(0, pr_b.indexOf('$function$;'))).not.toContain('delivery_mode')
})

test('count-only unless applied, audited, no updated_at write, the migration applies nothing, nothing dropped', () => {
  expect((code.match(/insert into pipeline\.admin_control_events/g) || []).length).toBe(3)
  expect(code).not.toMatch(/updated_at\s*=/)
  expect(code).not.toMatch(/_v1\(true\)/)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\s+(table|from|catalogue|pipeline)/im)
})
