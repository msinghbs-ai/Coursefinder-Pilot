// Guards: Intake wording, explicit period pairs and excluded months (Platform Admin direction 2 Nov 2026 23:24 §1)
// "Treat the explicit phrase 'Semester 1 and 2' as evidence that both teaching periods are named. Do not derive exact calendar dates from semester
// labels alone." With it (Workstream D): pairs and lists name each period; a month the page only excludes ("throughout the year excluding January &
// December", UWA) is not an intake and its rows are withdrawn only by an approved paste file; every filled value keeps the page wording that named
// the period and the approved calendar's quote and document.
// The behaviour runs on isolated fixtures by tests/fixtures/intake-dates/run.sh (scratch PostgreSQL; the three intake migrations applied twice to
// definitions rebuilt from this repository and checked against the live md5s); this spec runs the page reader and holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const MIG = 'supabase/migrations/20261103050000_cf247_intake_semester_pairs.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/intake-dates'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('\n$function$;', a)) }
const PASTE = 'docs/paste/PASTE-20261103-intake-excluded-months-withdrawal.sql'
const ROLLBACK = 'docs/paste/PASTE-20261103-intake-excluded-months-withdrawal-rollback.sql'

test('edits only from the live md5s, checked after; plan v2 is built from the live plan v1', () => {
  expect(m).toContain("select pg_temp.edit_once('security.intake_dates_apply_v1(integer)', '2ee1ce769cb5de8d300d9ad6e1bdbf7f', 'd15c04c680dc0128ca5da33556426c43'")
  expect(m).toContain("select pg_temp.edit_once('security.enrich_parse_intakes_v1(text,text)', '28beada5c58b585bd9e655381231f20f', '4372e1ccce2242733433607aed8b6924'")
  expect(m).toContain("if md5(pg_get_functiondef('security.intake_dates_plan_v1(uuid[],integer)'::regprocedure)) <> '4e3847587271c68e70018de23d0b74b6' then")
  expect(code).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(run).toContain('"4e3847587271c68e70018de23d0b74b6 2ee1ce769cb5de8d300d9ad6e1bdbf7f 28beada5c58b585bd9e655381231f20f"')
  expect(run).toContain('MIG3=supabase/migrations/20261103050000_cf247_intake_semester_pairs.sql')
})

test('explicit pairs and lists name each period; a year is not a period; a label alone gives no date', () => {
  const t = fn('security.intake_period_text_v1')
  expect(t).toContain("'\\m(semester|trimester|term|study period|teaching period|session|block|quarter)s?\\s*([0-9](?:\\s*(?:,|&|\\mand\\M|\\mor\\M|/)\\s*[0-9])+)\\M'")
  expect(m).toContain("if security.intake_period_text_v1('Semester 1 and 2') !~ '\\msemester 2\\M' or security.intake_period_text_v1('Term 1, 2027') ~ '\\mterm 2\\M' then")
  const p = fn('security.intake_dates_plan_v2')
  expect(p).toContain('v_pq := security.intake_period_text_v1(v_raw);')
  // a date still needs the approved calendar's dated start of the named period (unchanged from v1)
  expect(p).toContain("where s.kind = 'start' and s.period = any (v_named) and s.month = v_m and s.year is not null\n       and (s.quote ~ ('\\m' || s.year || '\\M') or v_pq ~ ('\\m' || s.year || '\\M'))")
  expect(p).toContain('v_start := case when cardinality(v_starts) = 1 then v_starts[1] end;')
  // the guards of v1 are all kept
  for (const g of ["k.field in ('intakes', 'intake')", 'security.course_held_v1(r.course_id)', 'security.page_refused_v1(r.course_id, v_url)',
    "v_chk := security.course_page_check_v1(r.course_id, v_url, null, null);", 'new_year := case when r.intake_year is null then v_year end;']) expect(p).toContain(g)
  // a row an earlier rule looked at and did not fill is looked at once more; a filled row is not
  expect(p).toContain("and (d.rule is not distinct from v_rule or d.outcome = 'filled'))")
})

test('a month the page only excludes is not an intake; its rows are withdrawn only by an approved paste file', async () => {
  const n = fn('security.intake_month_negated_v1')
  // the word and at most two months joined by "and", "&", "or" or a comma; a run-together month list after the word is ambiguous (SSC adapter pattern)
  expect(n).toContain("(\\s*(,|&|\\mand\\M|\\mor\\M)\\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*)?\\M(?!\\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\M)")
  expect(fixtures).toContain("'clear excluding wordings only; a run-together list is ambiguous'")
  expect(fn('security.intake_dates_plan_v2')).toContain("reason := 'the page excludes this month (listed for withdrawal)'")
  expect(m).toContain('and not security.intake_month_negated_v1(p_quote, m.n)')
  expect(fn('security.intake_negated_months_v1')).toContain("where i.status = 'active'")
  // the page reader skips such windows too
  const out = path.join(os.tmpdir(), `extract-s224-${process.pid}.mjs`)
  execFileSync('npx', ['esbuild', 'supabase/functions/coverage-sweep/extract.ts', '--format=esm', `--outfile=${out}`, '--log-level=error'])
  const { intakes, intakeEvidence } = await import(out)
  expect(intakes('Part-time Delivery On-campus Starting dates Throughout the year excluding January & December, by agreement with supervisors')).toEqual([])
  expect(intakeEvidence('Starting dates Throughout the year excluding January & December, by agreement with supervisors')).toEqual([])
  expect(intakes('Intakes: February and July. Start date: 24 February')).toEqual(['February', 'July'])
  expect(intakes('Intake Dates Every month on the 15th (Except December)')).toEqual([])
  expect(intakes('Intakes in February and July, except for the Bachelor of Arts')).toEqual(['February', 'July'])
  expect(intakes('Intakes: Except January February March April May July')).toEqual(['January', 'February', 'March', 'April', 'May', 'July'])  // ambiguous: left as read
  // the withdrawal is a paste file with a guard and a rollback, never this migration
  const paste = fs.readFileSync(PASTE, 'utf8'), back = fs.readFileSync(ROLLBACK, 'utf8')
  expect(paste).toContain('-- PASTE FILE. Not applied by any migration.')
  expect(paste).toMatch(/if v_n <> \d+ or v_md5 <> '[0-9a-f]{32}' then raise exception/)
  expect(paste).toContain("set status = 'withdrawn'")
  expect(back).toContain("set status = 'active'")
  const outside = code.replace(/\$function\$[\s\S]*?\$function\$/g, '').replace(/\$[on]\$[\s\S]*?\$[on]\$/g, '')
  expect(outside).not.toMatch(/\b(update|delete)\s+(catalogue|search)\./)
  expect(outside).not.toMatch(/^\s*(drop|truncate)\b/im)
})

test('every filled value keeps the page wording and the approved calendar document; earlier values are completed', () => {
  for (const c of ['page_quote text', 'calendar_evidence_id uuid', 'calendar_url text', 'rule text']) expect(m).toContain(`alter table pipeline.course_intake_dates add column if not exists ${c};`)
  const p = fn('security.intake_dates_plan_v2')
  expect(p).toContain("select p.id, p.evidence_id, p.url into v_prop, calendar_evidence_id, calendar_url from pipeline.provider_policy_proposals p")
  expect(p).toContain('page_quote := left(v_raw, 600);')
  expect(m).toContain("where d.intake_id in (select d2.intake_id from pipeline.course_intake_dates d2 where d2.outcome = 'filled' and d2.calendar_url is null")
  expect(m).toContain("p.page_quote, p.calendar_evidence_id, p.calendar_url, p.rule")
  expect(m).toContain("set status = 'retiring', replaced_by = 'security.intake_dates_plan_v2', retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int")
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function api\./)
})

test('the fixtures cover pairs, lists, a label alone, excluded months and provenance', () => {
  for (const p of ['PASS explicit pairs and lists name each period', 'PASS a label alone gives no date', 'PASS a month the page excludes is not an intake',
    'PASS every filled value keeps its page wording and calendar evidence', 'PASS named period only: no month-to-period inference',
    'PASS chain: stored reading -> intake row -> search projection -> consumer API']) expect(fixtures).toContain(`raise notice '${p}';`)
  for (const w of ["'\"Semester 1 and 2\" names Semester 2'", "'a list names each period'", "'pairs and lists read; a year is not a period'",
    "'listed for withdrawal: exactly UWA''s two rows'", "'the AI month parser drops excluded months only'", "'every filled value has its evidence'",
    "'an earlier value''s evidence completed'"]) expect(fixtures).toContain(w)
})
