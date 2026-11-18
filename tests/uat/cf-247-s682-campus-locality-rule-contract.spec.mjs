// Guards: Campus locality rule l4-campus-locality-v1 (Platform Admin 18 Nov 2026 17:03 item 3): a waiting campus postcode is settled only through the existing Layer 4 Inbox decision, under the system automation account, when the ABS mesh-block share of one Significant Urban Area (or of the area outside every one) reaches the setting, or when every waiting campus gives the area's own name as its suburb and that area holds the most mesh blocks; every other postcode waits for a person.
// CF-247 S682. Migration 20261118203000_cf247_boost_providers_rules. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations-archive/20261118203000_cf247_boost_providers_rules.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name, end = '$function$;') => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf(end, i)) }

test('the basis comes from the ABS mesh blocks and the campuses\' own suburb, with shares from settings', () => {
  const f = fn('security.campus_locality_rule_candidates_v1')
  expect(f).toContain('s.mesh_blocks::numeric / nullif(s.tot, 0) mshare')
  expect(f).toContain("when t.locality_id is not null and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_min_share', 0.9) then 'mesh_share'")
  expect(f).toContain("when t.locality_id is null and t.sua_name ilike 'Not in any%' and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_min_share', 0.9) then 'outside'")
  expect(f).toContain("t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_name_min_share', 0.5)")
  expect(f).toContain("where u = '' or u <> all (select security.campus_suburb_norm_v1(x) from regexp_split_to_table(t.locality, '\\s+-\\s+') x)) then 'suburb_name'")
  expect(f).toContain("else 'hold' end")
  expect(f).toContain('language sql stable')
})

test('only the existing Inbox decision, under the system automation account; a held postcode is never settled', () => {
  const f = fn('security.campus_locality_rule_v1')
  expect(f).toContain("where c.basis <> 'hold' order by c.postcode limit v_lim")
  expect(f).toContain("v_res := security.layer4_campus_locality_inbox_decide_v1(w.ref, case when w.basis = 'outside' then 'no_locality' else 'choose_locality' end,")
  expect(f).toContain("v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';")
  expect(f).toContain("perform set_config('request.jwt.claim.sub', v_sys::text, true);")
  expect(f).not.toMatch(/update destination\.|insert into destination\.|update catalogue\.|destination_postcode_resolve_v1/)
  expect(code).toContain("raise exception 'post-check: a postcode the rule holds for a person was settled by the rule';")
  expect(code).toContain("raise exception 'post-check: a settled postcode does not hold the locality the rule chose';")
})

test('suburb names are compared as letters only; the job runs hourly from settings; nothing dropped', () => {
  expect(fn('security.campus_suburb_norm_v1', '$f$;')).toContain("select regexp_replace(lower(coalesce(p, '')), '[^a-z]', '', 'g')")
  expect(code).toContain("select cron.schedule('layer4-campus-locality', '57 * * * *',")
  expect(code).toContain("security.pipeline_num_v1(''destination.campus_locality_rule_batch'', 200)::int")
  expect(code).toContain("if security.pipeline_num_v1('destination.campus_locality_rule_on', 0) < 1 or v_lim = 0 then")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
