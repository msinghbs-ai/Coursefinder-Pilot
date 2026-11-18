// Guards: Held scholarship re-check rule l4-held-sch-recheck-v1 (Platform Admin 18 Nov 2026 17:03 item 2): every pending held scholarship page with a stored copy and no re-check is queued for the existing AI re-check by an hourly catalogued job, from settings; the queue step publishes, rejects and decides nothing and never queues an item twice (settlement on a clear re-check is rule l4-held-sch-settle-v1, guarded by s683).
// CF-247 S681. Migration 20261118203000_cf247_boost_providers_rules. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261118203000_cf247_boost_providers_rules.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name, end = '$function$;') => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf(end, i)) }

test('only held pages with a stored copy and no re-check are queued, once', () => {
  const f = fn('security.scholarship_recheck_queue_rule_v1')
  expect(f).toContain("where r.status = 'pending' and r.recheck is null and nullif(btrim(coalesce(r.storage_path, '')), '') is not null")
  expect(f).toContain("set recheck = jsonb_build_object('state', 'queued', 'queued_at', now(), 'scope', 'rule l4-held-sch-recheck-v1')")
  expect(f).toContain('for update skip locked')
  expect(f).toContain("if security.pipeline_num_v1('scholarship.held_recheck_rule_on', 0) < 1 or v_lim = 0 then")
})

test('the rule decides nothing: no status, decision, scholarship or publication is written', () => {
  const f = fn('security.scholarship_recheck_queue_rule_v1')
  expect(f).not.toMatch(/set status|decision\s*=|decided_|scholarship\.scholarships|publication_status|svc_pilot_submit/)
  expect(code).toContain("raise exception 'post-check: the re-check was queued for an item that is not held or has no stored copy';")
})

test('the job runs hourly from settings and is catalogued', () => {
  expect(code).toContain("select cron.schedule('scholarship-recheck-queue', '9 * * * *',")
  expect(code).toContain("security.pipeline_num_v1(''batch.scholarship_recheck_queue'', 120)::int")
  expect(code).toContain("('scholarship-recheck-queue', 'Layer 4', 33,")
})
