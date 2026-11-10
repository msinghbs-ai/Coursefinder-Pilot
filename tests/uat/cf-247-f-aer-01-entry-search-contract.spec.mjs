// Guards: F-AER.01 AER source coverage: targeted entry-requirements search for providers AER source discovery asked about (Platform Admin 11 Nov 2026 05:42 AEDT)
// CF-247 F-AER.01. Production evidence 11 Nov 2026: job aer-source-discover asked about 294 providers with nothing stored; 242 settled 'refused' (svc_fc_spend
// 'not_due': their whole-site central map ran within central_refresh_days), 0 credits spent, 0 entry sources found. 357 of the 370 were last searched before the
// entry page kind existed. Migration 20261111100000 lets one targeted entry search run on its own interval; worker v0.64.0 runs it; central.ts scores a small
// provider's top-level entry requirements page. These are source contracts: the migration is run against live by the governed deploy and checked by md5 there.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { centralCandidates, entryCandidates, weakKinds, ENTRY_SEARCH } from '../../supabase/functions/coverage-sweep/central.ts'

const MIG = 'supabase/migrations/20261111100000_cf247_aer_entry_search.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const L = (url, title = null) => ({ url, title })

test('the live AER migrations applied overnight are checked in byte for byte (no live-only object)', () => {
  for (const f of ['20261111010000_cf247_aer_row_limits_from_evidence', '20261111020000_cf247_aer_machine_admission', '20261111030000_cf247_aer_machine_same_page_recapture',
    '20261111040000_cf247_aer_title_identity', '20261111050000_cf247_aer_title_identity_index', '20261111060000_cf247_aer_title_identity_set', '20261111070000_cf247_aer_source_discover']) {
    expect(fs.existsSync(`supabase/migrations/${f}.sql`), f).toBe(true)
  }
})

test('the two live functions are edited only from their live md5, by one exact text edit each, and the result is checked', () => {
  expect(code).toContain("md5(pg_get_functiondef('security.fc_purpose_group_v1(text)'::regprocedure)) <> '94950903b554779e4d0793620b3ccad3'")
  expect(code).toContain("md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) <> 'a0f43e737574f504de4aad17daf792bb'")
  expect(code).toContain("'8041bf166d40460f8b255ed0bcbc8312'")
  expect(code).toContain("'ee400f93352eef2be4158d4edacdc716'")
  expect(m).toMatch(/^-- Replaces: security\.fc_purpose_group_v1, public\.svc_fc_spend/m)
  expect(m).toMatch(/^-- Retires: |Retires: nothing/m)
})

test('the targeted search spends inside the central share on its own interval; every other spend rule is unchanged', () => {
  expect(code).toContain("'central_map', 'central_scrape', 'central_entry_search'")
  expect(code).toMatch(/p_purpose = 'central_entry_search' then\s+if exists \(select 1 from pipeline\.coverage_vendor_usage x where x\.provider_id = p_provider_id and x\.purpose = 'central_entry_search'/)
  expect(code).toContain("security.pipeline_num_v1('aer.source_discover_recheck_days', 30)")
  // the edit inserts before the whole-site map's not_due rule and leaves it in place
  expect((code.match(/elsif p_provider_id is not null and v_grp = 'central'/g) || []).length).toBe(2) // once in the old text, once kept in the new text
})

test('wanted only while discovery has an open request and the switch is on; recorded without losing other page kinds; service role only', () => {
  expect(code).toMatch(/create or replace function public\.svc_aer_entry_search_wanted\(p_provider_id uuid\) returns boolean/)
  expect(code).toContain("security.pipeline_num_v1('aer.entry_search_on', 0) >= 1")
  expect(code).toContain('q.outcome is null')
  expect(code).toMatch(/e->>'kind' is distinct from 'entry_requirements'/)
  expect(code).toContain("e->>'kind' = 'entry_requirements' and e->>'url' ~* '^https?://'")
  for (const f of ['svc_aer_entry_search_wanted(uuid)', 'svc_central_entry_record(uuid, jsonb, jsonb)']) {
    expect(code).toContain(`revoke all on function public.${f} from public, anon, authenticated`)
    expect(code).toContain(`grant execute on function public.${f} to service_role`)
  }
  expect((code.match(/raise exception 'service_role required'/g) || []).length).toBe(2)
})

test('G2: the switch is a labelled setting with a range, unit and used_by; no number in any job command (no job added)', () => {
  expect(code).toMatch(/\('pipeline', 'aer\.entry_search_on', 'Entry requirements: targeted entry-page search/)
  expect(code).toMatch(/'number', to_jsonb\(1\), 0, 1, 'switch', 1505, 'Entry requirements',/)
  expect(code).not.toMatch(/cron\.schedule/)
})

test('worker v0.64.0 asks the database before a targeted search and records it with the entry-only record', () => {
  expect(worker).toContain('const WORKER = "coverage-sweep-worker-v0.64.0"')
  expect(worker).toContain('rpc("svc_aer_entry_search_wanted", { p_provider_id: p.provider_id })')
  expect(worker).toContain('useFc("central_entry_search", p.provider_id, site.origin, true)')
  expect(worker).toContain('rpc("svc_central_entry_record"')
  expect(worker).toMatch(/if \(wantEntry\) \{ out\.push\(\{ provider_id: p\.provider_id, status: await entrySearch\(\) \}\); return \}/)
  expect(worker).toMatch(/wantEntry && !found\.some\(\(c\) => c\.kind === "entry_requirements" && c\.score >= 4\)/)
})

test('page rule: a small provider\'s top-level entry page is suggested; course-level, English and other-host pages are not; the whole-site map path is unchanged', () => {
  const h = 'www.college.edu.au'
  const urls = (links) => entryCandidates(links, h).map((c) => c.url)
  expect(urls([L('https://www.college.edu.au/entry-requirements')])).toEqual(['https://www.college.edu.au/entry-requirements'])
  expect(entryCandidates([L('https://www.college.edu.au/entry-requirements')], h)[0].score).toBeGreaterThanOrEqual(4) // entry_matrix_attach_v1 takes 4 or more
  expect(urls([L('https://www.college.edu.au/international/admission-requirements/')])).toHaveLength(1)
  expect(urls([L('https://www.college.edu.au/courses/diploma-of-business/entry-requirements')])).toEqual([])
  expect(urls([L('https://www.college.edu.au/english-entry-requirements')])).toEqual([])
  expect(urls([L('https://www.cricos.gov.au/entry-requirements')])).toEqual([])
  expect(centralCandidates([L('https://www.college.edu.au/study/international/entry-requirements-by-country')], h)[0].score).toBeGreaterThanOrEqual(6)
  expect(weakKinds([])).not.toContain('entry_requirements')
  expect(ENTRY_SEARCH).toMatch(/entry requirements/)
})
