// Guards: SS-Programme-Control 26 Nov 2026 17:01 AEDT item 1 (DR-15: separate free scholarship acquisition eligibility from paid Firecrawl caps; preserve all other holds, UTAS restrictions and spending controls)
// s1199: the candidate picker no longer holds a provider on its paid Firecrawl limits; paid reads stay decided by svc_fc_spend (cap, shares, and now the spend rule for new candidate pages); a held provider's waiting candidate retries after the existing interval.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129141500_cf247_s1199_dr15_scholarship_free_reads.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')
const fn = (name) => { const i = MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}(`); return MIG.slice(i, MIG.indexOf('$function$;', i)) }

test('s1199: each replaced function is guarded by the definition read live', () => {
  for (const [f, md5] of [['public.svc_scholarship_candidate_next(integer)', '2f3129679369d97bafaa27d8a468f30b'], ['public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)', '44c06460d022b98dfa5404c28ccaa368'],
    ['public.svc_fc_spend(numeric,text,uuid,text)', '545680b0455d28d121fff0b3cd17c167']]) expect(MIG).toContain(`md5(pg_get_functiondef('${f}'::regprocedure)) <> '${md5}'`)
})

test('s1199: the picker holds on unpublished, search off and directory hosts, never on a paid Firecrawl limit', () => {
  const p = fn('public.svc_scholarship_candidate_next')
  expect(p).not.toContain('fc_sch_held_v1')
  expect(p).toContain('security.provider_hidden_v1')
  expect(p).toContain('security.provider_sch_search_off_v1')
  expect(p).toContain('security.third_party_host_v1')
})

test('s1199: paid reads keep every control and gain the spend rule for new candidate pages', () => {
  const s = fn('public.svc_fc_spend')
  expect(s).toContain("security.fc_setting_num_v1('scholarship_cap_per_uni', 150)")
  expect(s).toContain("or (p_purpose = 'sch_scrape' and not exists (select 1 from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id")
  expect(s).toContain("and not security.fc_sch_eligible_v1(p_provider_id) then")
})

test('s1199: a held provider waiting for a paid read retries after the existing interval; no new value, job or setting', () => {
  expect(fn('public.svc_scholarship_candidate_record')).toContain("now() + make_interval(mins => (60 * security.pipeline_num_v1('retry.scholarship_waiting_scraper_hours', 1))::int)")
  expect(code).not.toMatch(/insert into pipeline\.platform_toolset_settings|cron\.schedule|cron\.alter_job|ai_service_routes|\bdelete from\b|truncate |website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: a cron job was created', 'post-check: more than 140 active cron jobs', 'post-check: manual locks changed', 'post-check: a setting value or range changed', 'post-check: the picker still holds on a paid Firecrawl limit', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
