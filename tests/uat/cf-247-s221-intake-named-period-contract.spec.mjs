// Guards: Intake dates "Named period only" (Platform Admin decision 2 Nov 2026 ~14:50)
// "Exact start dates are filled only where the course's own page names the period (e.g. "Semester 1", "Trimester 2") and that named period has
// a dated start in the approved calendar. A month-only row keeps its month only. A year is filled only when it is printed (on the page, or in
// the same calendar quote as the named period). No month-to-period inference." With it, the AU CRICOS admission write keeps held dates as the
// common admission write does (open question 1 of the v2.15.405 report).
// The behaviour runs on isolated fixtures by tests/fixtures/intake-dates/run.sh (scratch PostgreSQL; both intake migrations applied twice to
// definitions rebuilt from this repository and checked against the live md5s); this spec holds the contract and the fixture coverage.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261102100000_cf247_intake_named_period.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/intake-dates'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/before.mjs`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); return m.slice(a, m.indexOf('array[1, ', a)) }

test('both functions are edited only from their live md5 and checked after; the fixtures rebuild them and check live first', () => {
  expect(m).toContain("select pg_temp.edit_once('security.intake_dates_plan_v1(uuid[],integer)', 'a528b06b5fb7cd3a1cb4ec923e789328', '4e3847587271c68e70018de23d0b74b6'")
  expect(m).toContain("select pg_temp.edit_once('public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean)', 'ec4a0997cb1b97bc4b390b1d5beebaeb', 'cfd84c9f3348772b983ffd3c0fc92f57'")
  expect(code).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(code).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(run).toContain('"a528b06b5fb7cd3a1cb4ec923e789328 2ee1ce769cb5de8d300d9ad6e1bdbf7f ac4fa97ddf0c572750113404ae1804bb"')  // live after v2.15.405
  expect(run).toContain('ec4a0997cb1b97bc4b390b1d5beebaeb"')
  expect(run).toContain("grep -c 'already applied' | grep -qx 2")
  expect(before).toContain('20260901211500_m2_5_universal_layer4_block_enforcement')
})

test('the period must be named in the stored reading of the page behind the intake; no month-to-period inference', () => {
  const p = edit('security.intake_dates_plan_v1(uuid[],integer)')
  // the page reader's intake quotes for the same address, or the AI reading whose evidence is the intake's (its verbatim quote, not its paraphrase)
  expect(p).toContain("where g.course_id = r.course_id and (g.url = v_url or g.candidates->>'final_url' = v_url)")
  expect(p).toContain("g.candidates->'intake_context'")
  expect(p).toContain("where f.course_id = r.course_id and f.field = 'intakes' and f.state = 'filled' and f.evidence_id = r.evidence_id and nullif(btrim(f.quote), '') is not null) z;")
  expect(p).not.toContain("f.value")
  expect(p).toContain("and v_pq ~ ('\\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\\M');")
  expect(p).toContain("'the course page names no study period of the calendar (month only)'")
  // only the named periods, in the intake's month; the year only when printed in the period's calendar quote or on the page
  expect(p).toContain("where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year is not null\n       and (s.quote ~ ('\\m' || s.year || '\\M') or v_pq ~ ('\\m' || s.year || '\\M'))")
  expect(p).toContain("s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year = v_year\n       and (s.quote ~ ('\\m' || s.year || '\\M') or v_pq ~ ('\\m' || s.year || '\\M'));")
  expect(p).toContain("'the year of the named period is not printed (month only)'")
  // the guards before it (E16 page check, refusals, locks, holds) and the only-empty-columns rule are untouched: the edits replace nothing else
  expect((p.match(/array\[\$o\$/g) || []).length).toBe(4)
})

test('the AU CRICOS admission write keeps held dates; an older year never replaces a later one', () => {
  const c = edit('public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean)')
  expect(c).toContain('insert into catalogue.course_intakes as ci(course_id,intake_year,')
  expect(c).toContain('do update set intake_year=case when excluded.intake_year is null or excluded.intake_year<ci.intake_year then ci.intake_year else excluded.intake_year end')
  expect(c).toContain('start_date=case when excluded.intake_year>ci.intake_year then excluded.start_date when excluded.intake_year<ci.intake_year then ci.start_date else coalesce(excluded.start_date,ci.start_date) end')
  expect(c).toContain('application_deadline=case when excluded.intake_year>ci.intake_year then excluded.application_deadline when excluded.intake_year<ci.intake_year then ci.application_deadline else coalesce(excluded.application_deadline,ci.application_deadline) end')
})

test('the per-row AI reading lookup is keyed: an index beside pipeline.field_enrich_items', () => {
  expect(m).toContain('create index if not exists field_enrich_items_course_field_idx on pipeline.field_enrich_items (course_id, field);')
  expect(m).toContain("raise exception 'named period post-check: the AI reading index is missing'")
})

test('nothing is switched on, changed in the catalogue or dropped; the consumer API is untouched', () => {
  expect(m).toContain("raise exception 'named period post-check: the setting must be off'")
  expect(m).toContain("raise exception 'named period post-check: the job must be paused'")
  const outside = code.replace(/\$function\$[\s\S]*?\$function\$/g, '').replace(/\$[on]\$[\s\S]*?\$[on]\$/g, '')
  expect(outside).not.toMatch(/\b(update|delete)\s+(catalogue|search)\./)
  expect(outside).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(outside).not.toMatch(/cron\.(schedule|alter_job)/)
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function api\./)
})

test('the fixtures cover the named-period rule and the CRICOS write', () => {
  for (const p of ['PASS named period only: no month-to-period inference', 'PASS the AU CRICOS admission write keeps held dates', 'PASS month-only stays month-only',
    'PASS exact date and year kept', 'PASS chain: stored reading -> intake row -> search projection -> consumer API']) expect(fixtures).toContain(`raise notice '${p}';`)
  for (const w of ["'no month-to-period inference: '", "'AI reading quote names the period'", "'a reading of another page is not used'",
    "'year only from a heading: not printed with the period'", "'the year printed on the page with the named period'", "'the named period, not another in the month'",
    "'CRICOS re-admission without a year keeps year, date and deadline'", "'CRICOS: an older year never replaces a later one'"]) expect(fixtures).toContain(w)
  expect(fixtures).toContain("pg_temp.course('monthnamed', 'harbour', 'harbour.edu.au', 'MC279', 'Master of Statistics', 'Starts in March')")
  expect(run).toContain('MIG2=supabase/migrations/20261102100000_cf247_intake_named_period.sql')
})
