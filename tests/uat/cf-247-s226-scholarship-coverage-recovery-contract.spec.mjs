// Guards: CF-247 Scholarship Coverage Recovery (Platform Admin mandate 2 Nov 2026 17:41, §4, §5, §8, §13 items 2, 3, 4, 5, 13, 14, 15; overnight direction 2 Nov 2026 23:24 §1 Scholarships, §3)
// The central, parameterised scholarship-discovery guard, with the UNSW regression case. One spec for every provider: the cases are tables, not
// per-provider specs. Pure catalogue rules (umbrella awards, pagination, redirects, map outcomes) run here directly on the worker module; the
// database behaviour runs on isolated fixtures by tests/fixtures/scholarship-recovery/run.sh (scratch PostgreSQL with the live column
// definitions; the replaced and edited definitions loaded from their live text and checked against the live md5s; the defects reproduced on
// them first). This spec holds the contract, the fixtures' case lines and the worker wiring. G2, G3 and housekeeping are guarded centrally
// (s32, s57, s42) and not re-asserted here.
import { test, expect } from '@playwright/test'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const MIG = 'supabase/migrations/20261103050000_cf247_scholarship_recovery.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/scholarship-recovery'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const UNSW = fx('unsw-term1-2027.html')

async function cat() {
  const out = path.join(os.tmpdir(), `sch-catalogue-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/catalogue.ts', '--bundle', '--format=esm', `--outfile=${out}`])
  return import(out)
}

// [definition, live md5 before, md5 after] for every replacement and edit; run.sh loads the same live text and checks the same md5s
const CHANGED = [
  ['public.svc_scholarship_discover_next(integer)', '139bc97b784ac031db99d13b656f7c84'],
  ['public.svc_scholarship_discover_record(uuid,text,text,text,integer,jsonb,jsonb,text)', 'ed20bfe8862da0e5e26ce2f7189469e8'],
  ['public.svc_scholarship_candidate_next(integer)', '05a40ab97bec72d3b3ff2aa2c7dddf41'],
  ['public.svc_scholarship_listing_next(integer)', 'f8184295da30ebd598115ce2ea45f616'],
  ['public.svc_scholarship_fc_budget()', '5a58bfd5a6f3001fdb9e1387ed046650'],
  ['public.svc_worker_settings_v1()', '9f61ab21cbfc1d752c537998500fa936'],
  ['security.scholarship_task_fire_v1(text[])', 'b4f57757292bf861e217e759e9f7aad2'],
  ['security.fc_provider_tier_v1(uuid)', 'f6977adcef5e7f0df41b34f6f47b9fc2'],
  ['security.fc_sch_eligible_v1(uuid)', '06e6fb6f46698c3f59c5b4e754b3d6e2'],
  ['security.scholarship_discovery_refill_v1(integer)', 'ae7d6339945caa175c822754bfeebaff'],
  ['security.scholarship_admit_from_provider_page_v1(bigint)', 'ebed8647a65be18c127bf4a8cb2f1b0e'],
  ['public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)', '2bfb43c34e48aca7194ec8bb196c1662'],
  ['public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)', 'ece9139335e8e6832158353fa097d2e9'],
  ['public.svc_worker_report_v1(text,integer,integer,jsonb,text)', '11e82a3abcefc6ff7c16541a6d71f9cf'],
]

test('fourteen md5-guarded changes from the live text; the fixture run loads the same live definitions and applies the migration twice', () => {
  const guarded = [...m.matchAll(/select pg_temp\.(?:replace|edit)_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b]) => [s, b])
  expect(guarded.sort()).toEqual([...CHANGED].sort())
  expect(m).not.toContain('__AFTER')
  const live = JSON.parse(fx('live-defs.json'))
  for (const [sig, md5] of CHANGED) expect(live[sig]?.md5, sig).toBe(md5)
  const run = fx('run.sh')
  expect(run).toContain('[ "$BEFORE" = "$LIVE" ] || { echo "loaded definitions differ from live"; exit 1; }')
  expect(run).toContain("grep -c ': applied' | grep -qx 14")
  expect(run).toContain("grep -c 'already applied' | grep -qx 14")
  expect(run).toContain('$P -d $DB -f fixtures-before.sql')
  expect(m).toMatch(/^-- Replaces: public\.svc_scholarship_discover_next, .+public\.svc_scholarship_listing_record by public\.svc_scholarship_listing_record_v2/m)
  expect(m).toMatch(/^-- Retires: public\.svc_scholarship_listing_record \(marked retiring/m)
  expect(m).toContain("update pipeline.component_register set status = 'retiring', replaced_by = 'public.svc_scholarship_listing_record_v2'")
})

test('nothing is switched on: the job is paused, the two eligibility proposals and the all-time cap ship off; no Firecrawl limit is raised', () => {
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'worker-outcome-check'), active := false);")
  for (const k of ['scholarship.non_university_admission', 'scholarship.legitimacy_checks_on', 'scholarship.lifetime_cap_on']) expect(m).toMatch(new RegExp(`'${k.replace('.', '\\.')}'[\\s\\S]{0,700}?'boolean', 'false'::jsonb`))
  expect(m).toContain("raise exception 'scholarship recovery post-check: the eligibility proposals must ship off'")
  // the Firecrawl settings are read, never written
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings[\s\S]{0,200}toolset_key = 'firecrawl'/)
  expect(m).not.toMatch(/update pipeline\.scholarship_layer_settings/)
  // F8: with the all-time cap off the ceiling is the daily scholarship share, never unlimited
  expect(m).toContain("else v_used + security.fc_setting_num_v1('daily_share_scholarships', 3500) end,")
})

// ---- the database behaviour, case by case (fixtures.sql), with the defects reproduced on the live definitions first ------------------------
const BEFORE = ['RC1 picker', 'RC2 refused map', 'RC7 all-time cap', 'RC11 task sizes']
const CASES = [
  ['F1', 'F1 the tier refresh is bounded by its setting (500 an hour)'], ['F1', 'F1 refill stores tiers'], ['F1', 'F1 picker: window only, held rows wait'],
  ['F1', 'F1 picker answers well inside the statement time-out'], ['F1', 'F1 picks are bounded by the setting'], ['F1', 'F1 skip rules on new candidates'],
  ['F1', 'F1 candidate picker: requested first, bounded'], ['F1', "F1 candidate picker: an unpublished provider''s pages are not taken"],
  ['F2', 'F2 outcomes: 500 failed; nothing to do idle; refusals with no work zero_work_error'], ['F2', 'F2 three bad runs in a row: one issue naming the scheduled job'],
  ['F2', 'F2 a second check updates the same issue (no duplicate)'], ['F2', 'F2 a good run resolves it'],
  ['F3', 'F3 cadence set on the old empty UNSW row'], ['F3', 'F1/F3 the empty UNSW row is due again and picked first'], ['F3', 'F3 refused map deferred, not empty; count kept'],
  ['F3', 'F3 a deferred row is not picked before its time'], ['F3', 'F3 a map that ran is due again after the cadence'],
  ['F4', 'F4 sources: manual catalogues first, then auto; suggested never'],
  ['F5', 'F5 UNSW umbrella: 9 awards become candidates (PUCA1024 too: live it is only an inactive retired-register record), 2 held records are not added again, an off-site link is ignored'],
  ['F5', 'F5 the section address is the page address plus the award code'], ['F5', 'F5 reading the same page again adds nothing (idempotent)'],
  ['F5', 'F5 two awards of one umbrella page are two records'], ['F5', 'F5 the record keeps the official page address with its award'],
  ['F5', 'F5 the same award found on its own page is a duplicate, not a new record'],
  ['F6', 'F6 partial: nothing marked absent; continues from next_url within the hour'], ['F6', 'F6 the picker hands the continuation address back'],
  ['F6', 'F6 complete: an item no longer listed is marked absent; completed_at set'],
  ['F7', 'F7 redirected away: refused, not queued for the AI, read again only after the long re-read'],
  ['F7', 'F7 the stored Scientia Scholarship address redirecting away is recorded once, seen twice; the record is not withdrawn'],
  ['F8', 'F8 off (default): ceiling is used + the daily scholarship share'], ['F8', 'F8 on: the old all-time cap'],
  ['F9', 'F9 round states'], ['F9', 'F9 nothing published or withdrawn by the classification'],
  ['F10', 'F10 task sizes are the Scholarships settings'], ['F10', 'F10 worker settings include the scholarship keys'],
  ['P1', 'P1 off: universities only (UNSW Sydney yes, UNSW College no)'], ['P1', 'P1 off: the admission still refuses a non-university'],
  ['P1', 'P1 on: a governed university college with its own website is allowed'], ['P1', 'P1 on: not without a recorded provider type basis'], ['P1', 'P1 on: a school is never a scholarship provider'],
  ['P2', 'P2 off: UNSW College (5 courses) is below the 30-course minimum'], ['P2', 'P2 on: legitimacy evidence decides (UNSW College yes; a school no)'], ['P2', 'P2 on: never on a directory website'],
  ['shipped', 'shipped: the job is paused, proposals off, lifetime cap off'],
]
test('database cases: every fix and proposal has its case on the fixtures; the defects are reproduced on the live definitions first', () => {
  const before = fx('fixtures-before.sql'), after = fx('fixtures.sql')
  for (const b of BEFORE) expect(before).toContain(`perform fx_before('${b}',`)
  for (const [, c] of CASES) expect(after, c).toContain(`perform fx_ok('${c}',`)
  expect([...after.matchAll(/perform fx_ok\('/g)].length).toBe(CASES.length)
  for (const f of ['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'P1', 'P2']) expect(CASES.some(([k]) => k === f), f).toBe(true)
  // UNSW carries its live ids; the umbrella awards are those read from the official page
  expect(after).toContain("('22657140-1cb0-4fa7-91df-90518ea8b35b', 'UNSW Sydney'")
  expect(after).toContain("('93c852cf-6df7-4161-82bd-ca95941cc227', 'UNSW College'")
  for (const code of ['PUCA1025', 'PUCA1028', 'PUCA1023', 'PUCA1024', 'UGCA1603', 'UGCA1606', 'PUCA1026', 'PUCA1027', 'PGCA1107', 'UGCA1815']) { expect(after).toContain(code); expect(UNSW).toContain(code) }
})

// ---- the pure catalogue rules (worker module), parameterised -----------------------------------------------------------------------------
test('F5 umbrella pages: UNSW Term 1 2027 gives ten awards, keyed by code, one with its own page; a single-award page gives none', async () => {
  const { awardSections, sectionHtml, sectionCode } = await cat()
  const s = awardSections(UNSW, 'https://www.scholarships.unsw.edu.au/scholarships/id/1988')
  expect(s.map((x) => x.key)).toEqual(['PUCA1025', 'PUCA1028', 'PUCA1023', 'PUCA1024', 'UGCA1603', 'UGCA1606', 'PUCA1026', 'PUCA1027', 'PGCA1107', 'UGCA1815'])
  expect(s.find((x) => x.key === 'PUCA1025')).toMatchObject({ name: 'International Scientia Coursework Scholarship', url: null })
  expect(s.find((x) => x.key === 'PUCA1025').value_text).toContain('full tuition fee scholarship')
  expect(s.find((x) => x.key === 'PUCA1026').url).toBe('https://www.scholarships.unsw.edu.au/australias-global-university-award-puca1026')
  expect(s.find((x) => x.key === 'UGCA1815').codes).toEqual(['UGCA1815', 'UGCA1817', 'UGCA1818', 'UGCA1825'])
  // the portal link in the page is never taken as an award page
  expect(s.every((x) => !/sc_search/.test(x.url || ''))).toBe(true)
  // the copy kept for one award: its own row and the shared eligibility, never another award's value
  const one = sectionHtml(UNSW, 'PUCA1025')
  expect(one).toContain('<h1>International Scientia Coursework Scholarship</h1>')
  expect(one).toContain('Must be an international student')
  expect(one).toContain('$20,000 per annum')
  for (const other of ['PUCA1028', 'UGCA1603', 'PGCA1107', '$15,000']) expect(one).not.toContain(other)
  expect(sectionHtml(UNSW, 'ABCD1234')).toBeNull()
  expect(sectionCode('https://www.scholarships.unsw.edu.au/scholarships/id/1988#award-puca1025')).toBe('PUCA1025')
  expect(sectionCode('https://www.scholarships.unsw.edu.au/international-student-award')).toBeNull()
  expect(awardSections('<main><h1>Australia\'s Global University Award (PUCA1026)</h1><p>' + 'x '.repeat(300) + '</p></main>', 'https://x.edu.au/a')).toEqual([])
})

const PAGES = [
  // [case, current url, page html, next page]
  ['UNSW HDR finder: startRank/numRanks in the fragment', 'https://www.unsw.edu.au/research/hdr/scholarships#search=&filters=residency%3AInternational+funding_type%3ALiving%2520Allowance&sort=relevance&startRank=1&numRanks=10', '<main></main>',
    'https://www.unsw.edu.au/research/hdr/scholarships#search=&filters=residency%3AInternational+funding_type%3ALiving%2520Allowance&sort=relevance&startRank=11&numRanks=10'],
  ['startRank/numRanks in the query', 'https://search.example.edu.au/s/search.html?collection=sch&startRank=21&numRanks=20', '<main></main>', 'https://search.example.edu.au/s/search.html?collection=sch&startRank=41&numRanks=20'],
  ['rel="next"', 'https://x.edu.au/scholarships?page=1', '<link rel="next" href="/scholarships?page=2"><main></main>', 'https://x.edu.au/scholarships?page=2'],
  ['a "Next" link', 'https://x.edu.au/find', '<main><a href="/find?p=2">Next</a></main>', 'https://x.edu.au/find?p=2'],
  ['page=N', 'https://x.edu.au/scholarships/search?page=3', '<main></main>', 'https://x.edu.au/scholarships/search?page=4'],
  ['no pagination', 'https://x.edu.au/scholarships/international', '<main><a href="/apply">Apply now</a></main>', null],
]
const STATES = [
  // [case, input, state, reason]
  ['pagination ended', { pages_read: 3, items: 25, total_stated: null, next_url: null, last_page_new: 5, failed: false, page_limit_hit: false }, 'complete', 'no_next_page'],
  ['stated total reached', { pages_read: 3, items: 30, total_stated: 30, next_url: 'n', last_page_new: 10, failed: false, page_limit_hit: false }, 'complete', 'total_reached'],
  ['an empty page ends it', { pages_read: 4, items: 30, total_stated: null, next_url: 'n', last_page_new: 0, failed: false, page_limit_hit: false }, 'complete', 'empty_page'],
  ['page limit: never complete', { pages_read: 10, items: 100, total_stated: null, next_url: 'n', last_page_new: 10, failed: false, page_limit_hit: true }, 'partial', 'page_limit'],
  ['stated total not reached and no next page: not complete', { pages_read: 2, items: 20, total_stated: 57, next_url: null, last_page_new: 10, failed: false, page_limit_hit: false }, 'partial', 'total_not_reached'],
  ['a later page failed', { pages_read: 2, items: 20, total_stated: null, next_url: 'n', last_page_new: 10, failed: true, page_limit_hit: false }, 'partial', 'page_failed'],
  ['the first page failed', { pages_read: 0, items: 0, total_stated: null, next_url: 'n', last_page_new: 0, failed: true, page_limit_hit: false }, 'failed', 'first_page_failed'],
]
test('F6 pagination: next page by every pattern, complete only when the pagination ended by itself', async () => {
  const { nextPage, pagingState, statedTotal } = await cat()
  for (const [c, url, html, next] of PAGES) expect(nextPage(url, html), c).toBe(next)
  for (const [c, input, state, reason] of STATES) expect(pagingState(input), c).toMatchObject({ state, reason })
  expect(statedTotal('Showing 1-10 of 137 results')).toBe(137)
  expect(statedTotal('57 scholarships found')).toBe(57)
  expect(statedTotal('Find a scholarship that suits you')).toBeNull()
})

const MOVES = [
  ['UNSW legacy id address now opens the catalogue home', 'https://www.scholarships.unsw.edu.au/scholarships/id/1895', 'https://www.scholarships.unsw.edu.au/', 'redirected_away'],
  ['a detail page sent to the search page', 'https://x.edu.au/scholarships/merit-award', 'https://x.edu.au/scholarships/search', 'redirected_away'],
  ['a detail page moved to a new address', 'https://x.edu.au/old/merit-award', 'https://x.edu.au/study/scholarships/merit-award', 'moved'],
  ['same page, trailing slash and www', 'https://www.x.edu.au/scholarships/merit-award/', 'https://x.edu.au/scholarships/merit-award', 'same'],
  ['no final address', 'https://x.edu.au/a', null, 'same'],
]
const MAPS = [
  ['UNSW 12 Oct: refused by the budget', ['map:budget'], 0, 'deferred'],
  ['refused by the scholarship share', ['map:scholarship_share'], 0, 'deferred'],
  ['rate limited', ['map:429'], 0, 'deferred'],
  ['a second source refused while the first found nothing', ['map_search(0)', 'map:credits_refused'], 0, 'deferred'],
  ['ran and found nothing: empty (evidence of zero for this map)', ['map_search(0)'], 0, 'empty'],
  ['UNSW 2 Nov 19:50: map_search(72)', ['map_search(72)'], 72, 'mapped'],
]
test('F7 moved and redirected sources; F3 a refused or failed map is deferred, never empty', async () => {
  const { redirectOutcome, mapOutcome } = await cat()
  for (const [c, a, b, out] of MOVES) expect(redirectOutcome(a, b), c).toBe(out)
  for (const [c, methods, kept, out] of MAPS) expect(mapOutcome(methods, kept), c).toBe(out)
})

test('worker v0.59.0 wiring: sources, deferred maps, section and redirect reads, paginated listings, settings instead of literals', () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.59\.0";/)
  expect(worker).toContain('import { awardSections, mapOutcome, nextPage, pagingState, redirectOutcome, sectionCode, sectionHtml, statedTotal } from "./catalogue.ts";')
  expect(worker).toContain('const outcome = mapOutcome(methods, cands.length);  // v0.58.0 (F3)')
  expect(worker).toContain('const srcs = [...new Set([site.origin, ...((p.sources || []).filter((u) => /^https?:\\/\\//i.test(u)))])].slice(0, wsNum("scholarship.sources_per_provider_max", 5));')
  expect(worker.match(/await readSchPage\(it\.url, it\.provider_id\)/g)?.length).toBe(2) // scholarship_read and the candidates phase
  expect(worker).toContain('await rpc("svc_scholarship_listing_record_v2", { p_id: r.id, p_status: pages > 0 ? "read" : "failed", p_http_status: http, p_items: [...items.values()], p_error: err, p_paging: paging });')
  expect(worker).not.toContain('svc_scholarship_listing_record", {')
  // the scholarship reader and the scholarship modes carry no literal sizes (other modes are outside this change)
  const sch = worker.slice(worker.indexOf('const readSch = async'), worker.indexOf('if (mode === "discover")')) +
    worker.slice(worker.indexOf('if (mode === "scholarship_discover")'), worker.indexOf('if (mode === "scholarship_reextract")'))
  expect(sch).not.toMatch(/waitFor: 1500|body\.limit \|\| 3\), 6\)|read_limit \|\| 30\), 60\)|slice\(0, 6000\)|limit \|\| 6\), 20\)/)
  expect(sch).toContain('waitFor: waitMs')
  // every scholarship worker setting the worker reads is registered by the migration and returned by svc_worker_settings_v1
  const keys = [...new Set([...worker.matchAll(/wsNum\("(scholarship\.[a-z_]+)"/g)].map((x) => x[1]))]
  expect(keys.length).toBeGreaterThanOrEqual(9)
  for (const k of keys) expect(m, k).toContain(`('pipeline', '${k}', `)
  expect(m).toContain("or (s.toolset_key = 'pipeline' and s.key like 'scholarship.%'));")
})

test('consumer semantics kept (G3 untouched): a passed close date is "closed", never "open"; round states are a report beside it', () => {
  // the migration writes no consumer object (s57 guards the rest); the classification is its own pipeline table and never changes publication
  expect(m).not.toMatch(/create or replace function (api\.|public\.website_|public\.zoho_)/i)
  const rs = m.slice(m.indexOf('create or replace function security.scholarship_round_state_refresh_v1'), m.indexOf('-- F2: what a worker call achieved'))
  expect(rs).not.toMatch(/update scholarship\.scholarships|publication_status\s*=/)
  expect(rs).toContain("when s.application_close_date is not null and s.application_close_date < current_date then 'closed_round'")
})
