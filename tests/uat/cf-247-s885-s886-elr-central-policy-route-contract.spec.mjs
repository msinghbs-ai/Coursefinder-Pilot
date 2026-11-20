// Guards: CF-247 s885 and s886 (session S1-ELR-Central, Platform Admin 20 Nov 2026 22:07 AEDT): central-page English readings go through the governed English policy route (one proposal a university, only the tiers its approved policy lacks, approved automatically only with no conflict and no other reading waiting, under the course-page disagreement check); the plan gives VET and diploma courses a VET default only when the policy states one and holds regulated-discipline courses for Layer 4; existing plans are unchanged; the work runs inside the existing elr-det-sweep job (no new cron job) and never overwrites a course rule or a manual lock
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120220000_cf247_s884_elr_central_policy.sql', 'utf8')
const fn = (name) => { const a = MIG.indexOf(`create or replace function ${name}(`); return MIG.slice(a, MIG.indexOf('$f$;', a)) }

test('housekeeping and no new job: replaces and retires lines, no top-level drop or delete, no new cron schedule, comments on new tables', () => {
  expect(MIG).toMatch(/^-- Replaces: .+\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(MIG).not.toMatch(/cron\.schedule\(/)
  expect(MIG).toContain("raise exception 'post-check: the number of active cron jobs changed'")
  for (const t of ['elr_central_reads', 'elr_central_applies']) {
    expect(MIG).toContain(`comment on table pipeline.${t} is 'CF-247 s88`)
    expect(MIG).toContain(`revoke all on pipeline.${t} from public, anon, authenticated;`)
  }
})

test('every replaced function is md5-checked against the live text first, and existing plans are compared before and after', () => {
  for (const h of ['737f92c05ae9d61a95dfb855b6fe35e3', '65f5d9c65057ce4acb67c344d854a1d5', 'a0d9a19695fd50416b65460b3149a2df', 'f8f0b8dd7c793fb2e11c3be55cfc8045',
    'e08ac04e1c4c42239dab5a3040c10db4', '00d5cfd704afe3730aca8a5d71380ce2']) expect(MIG).toContain(`'${h}'`)
  expect(MIG).toContain("if v_h <> r.h then raise exception 'post-check: the English plan of proposal % changed'")
})

test('strict tiers in the plan: VET only when the policy states it, regulated disciplines held', () => {
  expect(MIG).toContain("when c0.lvl in ('diploma', 'advanced_diploma', 'certificate', 'certificate_ii', 'certificate_iii', 'certificate_iv') and jsonb_typeof(v_defaults->'vet') = 'array' then 'vet' end grp,")
  expect(MIG).toContain("when m.disc is not null and m.disc = any (v_disc) then 'held|regulated discipline (' || m.disc || '): the central page gives it higher bands'")
  for (const d of ['nursing', 'midwifery', 'medicine', 'allied health', 'education', 'law', 'social work']) expect(MIG).toContain(`then '${d}'`)
})

test('the governed route: one proposal a university, only missing tiers, approved automatically only without conflict or a waiting reading', () => {
  const w = fn('security.elr_central_record_v1')
  expect(w).toContain("if jsonb_array_length(v_merged) > 0 and not (t = any (v_base_tiers)) then")
  expect(w).toContain("o.parser = v_x and o.status in ('proposed', 'approved')")
  expect(w).toContain("'named', coalesce(b.proposal->'named', '[]'::jsonb), 'exceptions', coalesce(b.proposal->'exceptions', '[]'::jsonb)")
  expect(w).toContain("'proposed'\n      from pipeline.provider_fact_sources f")
  expect(w).not.toMatch(/insert into catalogue\.|update catalogue\./i)
  expect(MIG).toContain("or (x.kind = 'english_policy' and x.parser = 'elr-central-v1.0' and security.pipeline_num_v1('central.auto_approve_elr_central', 1) = 1")
  expect(MIG).toContain("and not exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'proposed' and o.id <> x.id))")
  expect(MIG).toContain("and status = 'approved' and parser is distinct from 'elr-central-v1.0' order by decided_at loop")
})

test('the sweep: central pages read back, bounded application, regulated-discipline holds to Layer 4 with a plain reason', () => {
  const t = fn('security.elr_det_sweep_tick_v1')
  expect(t).toContain("v_rec := security.elr_central_record_v1(v_res->'pages', 'request:' || q.id);")
  expect(t).toContain("security.elr_central_claim_v1(security.pipeline_num_v1('batch.elr_central', 6)::int)")
  expect(t).toContain("limit security.pipeline_num_v1('elr_central.apply_per_run', 2)::int loop")
  expect(t).toContain('v_ap := security.provider_english_apply_v1(ap.id);')
  expect(t).toContain("'Regulated discipline (' || h.disc || '): the university''s central English page gives higher English bands for these courses")
  for (const k of ['elr_central.on', 'batch.elr_central', 'elr_central.apply_per_run', 'elr_central.reapply_hours', 'elr_central.l4_per_run', 'central.auto_approve_elr_central'])
    expect(MIG).toContain(`('pipeline', '${k}', `)
})

test('G3 and safety: the consumer API is checked before and after, manual locks compared, no model or Firecrawl call, no public object', () => {
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toContain("raise exception 'post-check: the manual locks changed'")
  expect(MIG).not.toMatch(/create (or replace )?(function|view|table)( if not exists)? public\./i)
  expect(MIG).not.toMatch(/openrouter|firecrawl_|fc_run|enrich_ai/i)
})
