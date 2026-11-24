// Guards: Admin #1048 (Platform Admin 25 Nov 2026 05:55 AEDT: verify production outcomes and continue outstanding shared fixes)
// s1120: job entry-matrix-read starts a worker call for a source whose fetch claim ran out, with the same test the fetch uses, so a handed-back or stopped fetch is not left waiting.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261126160000_cf247_s1120_entry_fire_expired_claims.sql', 'utf8')
const fn = MIG.slice(MIG.indexOf('CREATE OR REPLACE FUNCTION security.entry_matrix_fire_v1()'), MIG.indexOf('$function$;') + 11)

test('s1120: the due count takes an expired fetch claim exactly as svc_entry_matrix_fetch_next does', () => {
  expect(fn).toContain("v_due := v_due + (select count(*) from pipeline.entry_matrix_sources s where (s.status = 'found' or (s.status = 'reading' and s.updated_at < now() - interval '20 minutes'  -- fixed: claim timer (svc_entry_matrix_fetch_next)")
  expect(fn).toContain("and s.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3))) and security.entry_matrix_enabled_v1(s.provider_id));")
  // the rest of the job is unchanged: the AI switch, the fire guard, one call
  expect(fn).toContain("if not security.ai_use_allowed_v1('entry_matrix') then return")
  expect(fn).toContain("l.created_at > now() - interval '4 minutes'  -- fixed: fire guard")
  expect(fn).toContain("if v_due > 0 and v_open = 0 then")
  expect((fn.match(/svc_pilot_submit_nonce/g) || []).length).toBe(1)
})

test('s1120: made from the live definition it replaces, and checked after', () => {
  expect(MIG).toContain("if md5(pg_get_functiondef('security.entry_matrix_fire_v1()'::regprocedure)) <> '0ab725cb35f7c7d5d2309f18ec94c119' then")
  expect(MIG).toContain("raise exception 'post-check: the due count does not take expired claims'")
  expect(MIG).not.toMatch(/platform_toolset_settings|ai_service_routes|\bdelete from\b|\bdrop\s+(table|function|trigger|index|view)|truncate |cron\.schedule|cron\.alter_job/i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
