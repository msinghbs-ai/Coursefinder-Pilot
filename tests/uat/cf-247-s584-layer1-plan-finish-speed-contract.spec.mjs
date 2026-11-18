// Guards: CRICOS 11 Nov 2026 edition apply (Platform Admin 17 Nov 2026 14:30): the Layer 1 plan finish matches new register codes in one scan, so finishing a CRICOS plan fits the service statement limit
// CF-247 S584. Migration 20261117211000_cf247_layer1_plan_finish_reactivation_speed.sql (md5-guarded edit of security.layer1_plan_finish_v1).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations-archive/20261117211000_cf247_layer1_plan_finish_reactivation_speed.sql', 'utf8')

test('the reactivation statement collects the new codes first and matches them with = any, guarded by the live body md5', () => {
  expect(mig).toContain("v_new_codes := array(select distinct upper(i->>0) from jsonb_array_elements(p.items) i where i->>2='new');")
  expect(mig).toContain("and lower(cr.scheme)='cricos' and upper(cr.registration_code)=any(v_new_codes)")
  expect(mig).toContain("if md5(v_src) <> 'cbd1ae1397a6c45599c23d3597967e51' then raise exception")
  expect(mig).toContain("if md5((select p.prosrc from pg_proc p where p.oid = v_sig)) <> md5(v_out) then raise exception")
  expect(mig).toMatch(/-- Replaces: .+\n-- Retires: nothing\./)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
