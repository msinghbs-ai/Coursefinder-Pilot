// Guards: Platform Admin decision 9 Nov 2026 19:18 AEDT (formal G3 authorisation of Website API v2 R23/R24) with G3: the forward-restore migration is prepared, held outside supabase/migrations and carries no approval until a new explicit one is given
// CF-247 R23/R24 forward restore (QA F7, 9 Nov 2026): a prepared migration that returns the two consumer builders to their 5 Nov 2026 definitions
// (md5 57115d3b... and d1792cc7..., the preserved live text in tests/fixtures/website-api-v2-r23-r24/live/ of the release PR). It is NOT part of the
// release: it lives in supabase/held/, its first line says PENDING (s57 rejects that as an approval), and this spec fails if it is moved into
// supabase/migrations without a completed approval line. Proven on the production-parity fixture on 9 Nov 2026 (apply after R23/R24: md5s restored,
// baseline re-taken; second run refused).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const HELD = 'supabase/held/20261109200000_cf247_r23_r24_restore_DO_NOT_MERGE.sql'
const m = fs.readFileSync(HELD, 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('held, not released: outside supabase/migrations, first line PENDING (not an approval), marked DO NOT MERGE; nothing in migrations restores the builders', () => {
  expect(m.split('\n')[0]).toMatch(/^-- Consumer API change approved: PENDING /)
  expect(m).toContain('-- DO NOT MERGE. DO NOT APPLY.')
  const mig = fs.readdirSync('supabase/migrations')
  expect(mig.filter((f) => f.includes('r23_r24_restore'))).toEqual([])
  expect(mig.filter((f) => f.startsWith('20261109200000'))).toEqual([])
  // the same regex s57 uses: a PENDING line is not an approval, so moving the file unchanged into migrations fails s57
  expect(/^-- Consumer API change approved: (?!.*\bPENDING\b).{10,}$/m.test(m)).toBe(false)
  expect(m).toMatch(/^-- Replaces: api\.website_v2_provider_campuses\(uuid\), api\.website_v2_scholarship_item\(uuid\)/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
})

test('restore: refuses unless live equals the R23/R24 definitions, replaces each builder by md5 guard with the preserved pre-R23/R24 text, checks drift, re-takes the baseline last, checks the result', () => {
  const g = m.indexOf("md5(pg_get_functiondef('api.website_v2_provider_campuses(uuid)'::regprocedure)) <> '698afad0bc236a314fb356632938c403'")
  expect(g).toBeGreaterThan(0)
  expect(m).toContain("md5(pg_get_functiondef('api.website_v2_scholarship_item(uuid)'::regprocedure)) <> '04532402307717c6dab17567551364e1' then")
  expect(m).toContain("raise exception 'CF-247 R23/R24 restore: live definitions are not the R23/R24 ones (698afad0, 04532402): not applied'")
  const a = m.indexOf("select pg_temp.replace_once('api.website_v2_provider_campuses(uuid)', '698afad0bc236a314fb356632938c403', '57115d3b8ddbc40729ec04078ee15d41', $def$")
  const b = m.indexOf("select pg_temp.replace_once('api.website_v2_scholarship_item(uuid)', '04532402307717c6dab17567551364e1', 'd1792cc7161101ce8c22abad70ecbd36', $def$")
  expect(a).toBeGreaterThan(g)
  expect(b).toBeGreaterThan(a)
  expect(m).toContain("select coalesce(jsonb_agg(distinct jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,")
  expect(m).toContain("CREATE OR REPLACE FUNCTION api.website_v2_scholarship_item(p_id uuid)")
  const drift = m.indexOf("where d not in ('api.website_v2_provider_campuses(uuid)', 'api.website_v2_scholarship_item(uuid)')")
  const reb = m.indexOf("select security.consumer_api_rebaseline_v1('R23/R24 restore")
  const fin = m.indexOf('restore: live does not equal the restored definitions after the restore')
  expect(drift).toBeGreaterThan(b)
  expect(reb).toBeGreaterThan(drift)
  expect(fin).toBeGreaterThan(reb)
  expect((code(m).match(/consumer_api_rebaseline_v1\(/g) || [])).toHaveLength(1)
})

test('G1, G2 and housekeeping: nothing dropped, deleted or created; no setting, job or table; no number written into a rule', () => {
  const noFn = code(m).replace(/CREATE OR REPLACE FUNCTION api\.website_v2_[\s\S]*?\$function\$[\s\S]*?\$function\$/g, '')
  expect(noFn).not.toMatch(/\b(drop|delete|truncate)\b/i)
  expect(noFn).not.toMatch(/cron\.schedule|create table|platform_toolset_settings|insert\s+into/i)
})
