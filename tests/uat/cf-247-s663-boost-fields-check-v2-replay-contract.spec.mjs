// Guards: Boost multi-field qualification (Platform Admin 18 Nov 2026 17:02 item 3, REQ-61, REQ-69, REQ-70): page check boost-fields-check-v2 accepts a description only when it is prose about the course, a month only where the quote says the course starts then, and a fee only when its currency, year, period and whole amount are supported by the quote or the page; the replay mode boost_fields_replay reads stored pages of courses that already hold a value with the route's one model and stages, admits and qualifies nothing.
// CF-247 S663. Worker coverage-sweep v1.0.18 (boost-fields.ts, index.ts mode boost_fields_replay), scripts/boost-fields-replay.mjs and workflow boost-fields-replay.yml. No migration. The quotes below are answers Qwen3 30B gave on live pages on 18 Nov 2026 that check v1 had accepted. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const replay = IX.slice(IX.indexOf('if (mode === "boost_fields_replay") {'), IX.indexOf('if (mode === "boost_extract") {'))
let B, F
test.beforeAll(async () => {
  const load = async (f) => { const out = await build({ entryPoints: [f], bundle: true, format: 'esm', write: false, logLevel: 'silent' }); return import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64')) }
  F = await load('supabase/functions/coverage-sweep/boost-fields.ts'); B = await load('supabase/functions/coverage-sweep/boost.ts')
})
const check = (lane, a, page) => F.verifyBoostField(lane, a, B.boostFlat(page ?? a.quote), page ?? a.quote)

test('the check has its own version and the prompt is unchanged, so the route qualification row is untouched', () => {
  expect(F.BOOST_FIELDS_CHECK_VERSION).toBe('boost-fields-check-v3')  // v3 from s726
  expect(F.BOOST_FIELDS_PROMPT_VERSION).toBe('boost-fields-v2')  // v2 from s723 and s726
  expect(IX).toContain('fields = lanes.map((l) => verifyBoostField(l, (ra as any).a?.[l], flat, page))')
  expect(IX).toContain('selector, check_version: BOOST_FIELDS_CHECK_VERSION, status, note, fields,')
})

test('intakes: a month counts only where the quote says the course starts then', () => {
  const ok = [
    [['February', 'July'], 'Intakes: February and July.'],
    [['March', 'July', 'November'], 'Start in March Start in July Start in November'],
    [['February'], 'Commencement 2 February 2027'],
    [['October'], 'October 2026 Intake: 15% Off Tuition Fees (T&Cs Apply)'],
    [['January', 'February'], 'January 2027 VET intake and February 2027 HE intake now open'],
    [['February', 'July'], 'Semester 1 (February) and Semester 2 (July) intakes are available.'],
    [['December', 'March'], 'Summer Intake – Starts 1 st December 2025 and application deadline 1 st November 2025 Autumn Intake – Starts 2 nd March 2026 and application deadline 2 nd February 2026'],
  ]
  for (const [months, quote] of ok) expect(check('intakes', { months, quote }).status, quote).toBe('verified')
  const refused = [
    [['February'], 'February 21, 2023'],                                                         // a post date
    [['July'], 'Workshop Tour | Trades Practical Classes | Week 1 Term 3 2026 July 23, 2026'],   // an event
    [['September', 'February'], 'Magill Newsletter September 2024 Magill Newsletter February 2025'],
    [['August'], 'Applications open - Last Friday in August of the preceding year'],
    [['November'], 'BFA (Hons) Applications are open until Monday 16 November 2026.'],
    [['April', 'June'], 'I’ve attended the FCE class from April to June and I really enjoyed my time here.'],
    [['January', 'April', 'July', 'October'], 'Semester 1 Term 1: January – April Term 2: April – July Semester 2 Term 3: July – September Term 4: October – December'],
    [['January', 'June'], 'Semester January - March - Internal keyboard_arrow_down Start year: 2019 End year - Attendance type: Part Time, Full Time Semester June - September - Internal'],
    [['November'], 'Summer Intake – Starts 1 st December 2025 and application deadline 1 st November 2025 Autumn Intake – Starts 2 nd March 2026'],  // the deadline month
    [['February'], 'Next intake: 3 March 2027. Applications close 1 February 2027.'],
  ]
  for (const [months, quote] of refused) {
    const v = check('intakes', { months, quote })
    expect(v.status, quote).toBe('rejected')
    expect(v.problems.join(' '), quote).toContain('the quote does not say the course starts in')
  }
  const all = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
  expect(check('intakes', { months: all, quote: 'Intake Dates For 2025 JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC International Students 6 th 21 st 14 th 6 th' }).problems).toContain('too many months to be a list of intakes (a calendar header)')
  expect(F.monthIsAnIntake('Classes commence in late January.', 'january')).toBe(true)
  expect(F.monthIsAnIntake('Start year: 2019 Semester June', 'june')).toBe(false)
})

test('fees: the whole amount, the currency, the period and the year must be supported', () => {
  const Q = 'International tuition fee: A$38,400 per year (2027).'
  expect(check('course_fees', { amount: 38400, currency: 'AUD', period: 'year', audience: 'international', year: 2027, quote: Q }).status).toBe('verified')
  expect(check('course_fees', { amount: 8400, currency: 'AUD', period: 'year', quote: Q }).problems).toContain('the amount is not in the quote')  // part of a larger number
  expect(check('course_fees', { amount: 38400, currency: 'NZD', period: 'year', quote: Q }).problems).toContain('the quote names AUD, not NZD')
  expect(check('course_fees', { amount: 38400, currency: 'AUD', period: 'semester', quote: Q }).problems).toContain('the quote does not say the fee is per semester')
  expect(check('course_fees', { amount: 38400, currency: 'AUD', period: 'year', year: 2026, quote: Q }).problems).toContain('the fee year 2026 is not in the quote')
  const bare = 'Offshore study 2026 fee: $47,321.60 (for 120 points) ($46,100 tuition fees + $1,221.60 student services levy)'
  const a = { year: 2026, quote: bare, amount: 47321.6, period: 'total', audience: 'international', currency: 'NZD' }
  expect(check('course_fees', a).problems).toEqual(['the page does not name the currency NZD'])   // a bare "$" rests on the page
  expect(check('course_fees', a, `All fees are shown in NZD. ${bare}`).status).toBe('verified')
  expect(check('course_fees', a, `Fees in NZD; overseas payments in USD. ${bare}`).problems).toEqual(['the page names more than one currency (NZD, USD) and the quote names none'])
  expect(F.currenciesNamed('NZ$ 55,484.00 or £20,000')).toEqual(['NZD', 'GBP'])
  expect(F.currenciesNamed('$15,000 per year')).toEqual([])
})

test('course description: prose about the course, not a title, a menu, a call to action or raw markup', () => {
  const good = [
    'This program provides students with knowledge and skills to work in professional roles in the tourism travel, hospitality and event management sectors in Australia and internationally.',
    'The Bachelor of Nursing prepares you to work as a registered nurse in hospitals and community settings across Australia.',
    'Gain a comprehensive legal education. Develop critical skills. Interpret complex ideas.',
  ]
  for (const quote of good) expect(check('course_description', { quote }).status, quote).toBe('verified')
  const bad = {
    'Bachelor of Creative Arts (Game Production) - Flinders University Skip to content New students My course Support and services Uni life Finance & admin': "the quote holds navigation or a call to action, not the course's overview",
    'Join Polytechnic Victoria now Begin your Educational Journey Today. Apply Now': "the quote holds navigation or a call to action, not the course's overview",
    'Explore human behaviour with Psychology - YouTube Tap to unmute Explore human behaviour with Psychology Charles Sturt University 8.25K subscribers Watch on Make a difference': "the quote holds navigation or a call to action, not the course's overview",
    'Certificate III in Painting and Decorating Level : Certificate III Method : Hands-on Training, Lecture': 'the quote is a title or a list of headings, not prose about the course',
    'SIS30619 Certificate III in Outdoor Leadership (102655A) - Gold Coast Dive Centre & Marine Training College': 'the quote is a title or a list of headings, not prose about the course',
    'FNS50922 Diploma of Banking Services Management &#8211; Institute of Business and Management': 'the quote holds unconverted HTML entities',
  }
  for (const [quote, problem] of Object.entries(bad)) { const v = check('course_description', { quote }); expect(v.status, quote).toBe('rejected'); expect(v.problems, quote).toContain(problem) }
})

test('the replay mode reads as the live mode reads and writes nothing', () => {
  expect(replay.length).toBeGreaterThan(500)
  expect((replay.match(/await cascadeFetch\(fetch, \{ service: "boost_fields_extract" \}, "https:\/\/openrouter\.ai\/api\/v1\/chat\/completions"/g) || []).length).toBe(1)
  expect(replay).toContain('const route = await rpc("svc_boost_fields_route_v1", {});')
  expect(replay).toContain('`answered by ${out.model}, not the routed model`')
  expect(replay).toContain('boostFieldsRequest(model, String(it.title || ""), lanes, sec.text, maxTokens)')
  expect(replay).toContain('.slice(0, BOOST_REPLAY_MAX_PAGES)')
  expect(replay).not.toMatch(/\.upload\(|svc_boost_fields_claim|svc_boost_fields_done|svc_boost_promote|boost_model_qualifications|ai_route_qualifications|catalogue\./)
  expect(F.BOOST_REPLAY_MAX_PAGES).toBe(24)
})

test('the replay script builds its gold set from the catalogue, only reads tables, and never qualifies', () => {
  const S = fs.readFileSync('scripts/boost-fields-replay.mjs', 'utf8'), W = fs.readFileSync('.github/workflows/boost-fields-replay.yml', 'utf8')
  expect(S).toContain("i.status = 'active' and i.start_date is not null")
  expect(S).toContain("f.status = 'active'")  // the fee basis of the gold query is guarded by s665
  expect(S).toContain("e.evidence_type = 'provider_course_page_text'")
  expect(S).toContain("await worker(`jsonb_build_object('mode', 'boost_fields_replay', 'items', jsonb_build_array(")
  expect((S.match(/await worker\(/g) || []).length).toBe(1)
  expect(S).not.toMatch(/\b(insert into|update|delete from|drop|truncate|alter)\s+[a-z_]+\.[a-z_]+/i)
  expect(S).not.toMatch(/boost_model_qualifications|ai_route_qualifications/)
  expect(W).toContain('workflow_dispatch:')
  expect(W).not.toMatch(/pull_request|schedule:/)
})
