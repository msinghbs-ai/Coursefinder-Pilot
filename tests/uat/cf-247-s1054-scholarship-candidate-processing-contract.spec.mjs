// Guards: Platform Admin 24 Nov 2026 19:48 AEDT (SCH-FU-09: restore authorised scholarship candidate processing through the existing pipeline; picker scoped to on-demand tasks and fair across AU, NZ and CA; no new cron, gates or limits)
// s1054: the candidate picker and the resume of the two readers paused temporarily on 17 Nov.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261125100000_cf247_s1054_scholarship_candidate_processing.sql', 'utf8')
const fnStart = MIG.indexOf('CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next')
const fn = MIG.slice(fnStart, MIG.indexOf('$function$;', fnStart))

test('s1054: only a queued or running Find scholarships task puts candidates first; a stale requested_at does not', () => {
  expect(fn).toContain("where j.kind = 'scholarship_provider_scan' and j.state in ('queued', 'running')")
  expect(fn).toContain('c.provider_id = any (v_task) requested')
  expect(fn).not.toMatch(/requested_at is not null/)
})

test('s1054: countries and providers take turns; every hold is kept and checked before the window', () => {
  expect(fn).toContain("row_number() over (partition by coalesce(co.iso_alpha2::text, '--') order by")
  expect(fn).toContain('partition by r0.requested, r0.cc order by r0.rn')
  for (const h of ['security.provider_hidden_v1', 'security.fc_sch_held_v1(v_p.provider_id, true)', 'security.provider_sch_search_off_v1(v_p.provider_id)', 'security.third_party_host_v1(w.url)', 'c.attempts<3', "leased_until=now()+interval '5 minutes'"]) expect(fn).toContain(h)
  expect(fn).toContain('where c.provider_id = any (v_ok)')
  expect(fn).toContain("security.pipeline_num_v1('scholarship.candidates_max', 60)")
})

test('s1054: only the two readers paused temporarily on 17 Nov are resumed, recorded, with no new job and cron at most 140', () => {
  expect(MIG).toContain("v_jobs constant text[] := array['scholarship-discover', 'scholarship-read']")
  expect(MIG).toContain("e.detail->>'by' = 'migration 20261117051700' and (e.detail->>'temporary')::boolean")
  expect(MIG).toContain("values ('automations', 'resume', r.jobname")
  expect(MIG).not.toMatch(/cron\.schedule|scholarship-discover-refill', *active|update pipeline\.platform_toolset_settings/i)
  expect(MIG).toContain("raise exception 'post-check: more than 140 active cron jobs'")
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function)|delete from|truncate pipeline/i)
})
