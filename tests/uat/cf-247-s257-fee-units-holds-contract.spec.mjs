// Guards: Integration issue IQ-00111 (P0 fee integrity; Layer 4 integrator handover 3 Nov 2026 Priority 1 items 1-5, evidence recovery mandate
// 20:47 §2): the AI fee reader distinguishes units from credit points, uses the page's own full-time load, holds an unclear yearly figure for a
// person instead of dividing, never admits a page fee while a fee hold or fee-check exclusion is active, and wrong active values are contained
// and corrected only by count-guarded Platform Admin pastes. The behaviour runs on isolated fixtures by tests/fixtures/fee-units-holds/run.sh
// (scratch PostgreSQL; the four live definitions loaded from their live text and checked against the live md5s; the 2 Nov defects reproduced on
// them; the migration refused without A's contract, applied with it, applied again unchanged; every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104140000_cf247_fee_units_holds.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/fee-units-holds'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const fees = fs.readFileSync('supabase/functions/coverage-sweep/fees.ts', 'utf8')
const index = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const PASTE = 'docs/paste/PASTE-20261104-fee-units-holds'
const contain = fs.readFileSync(`${PASTE}-containment.sql`, 'utf8')
const rollback = fs.readFileSync(`${PASTE}-containment-rollback.sql`, 'utf8')
const correction = fs.readFileSync(`${PASTE}-correction.sql`, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')

const LIVE = {
  'public.svc_fee_ai_record(uuid,jsonb,numeric,text)': '0fb74c639ca69349ef18813282b0f987',
  'security.fee_course_pages_enqueue_v1()': '91b2591e44bf9755950619006bf78e32',
  'security.fee_row_units_v1(jsonb)': '8d534a87af685cfd5d0d8a7bd54f6388',
  'security.uni_adapter_excluded(uuid,text)': '7359e28cc207833c658be6f169aa695c',
}
const EDITED = {
  'public.svc_fee_ai_record(uuid,jsonb,numeric,text)': '5ec65e53403933b98381bd5c9c79b6d1',
  'security.fee_course_pages_enqueue_v1()': '67b1b7db62dbd3c8e90053296f54a46a',
}

test('the fixture loads the live text of every definition it runs; only the reader record and its queue are edited, md5-guarded both ways', () => {
  for (const [sig, b] of Object.entries(LIVE)) {
    const file = `${FX}/live/${sig.slice(sig.indexOf('.') + 1, sig.indexOf('('))}.def`
    expect(md5(fs.readFileSync(file, 'utf8')), file).toBe(b)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  for (const [sig, a] of Object.entries(EDITED)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${LIVE[sig]}', '${a}', array[`)
    expect(m).toContain(`--   ${sig} ${LIVE[sig]} -> ${a}`)
  }
  expect(m).toContain("'security.fee_row_units_v1(jsonb)', '8d534a87af685cfd5d0d8a7bd54f6388'")
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null then")
  expect(run).toContain("without A's contract: refused, nothing changed")
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('the 2 Nov defects are reproduced on the live definitions', () => {
  expect(before).toContain("'before: Murdoch 37,800 one-year course admitted as 12,600 (the defect)'")
  expect(before).toContain("'before: WSU page fee admitted while its fee check hold is raised (the defect)'")
})

test('a fee for a stated count is made yearly from the page load, the country load of the same kind, or the course length; unclear is held', () => {
  expect(m).toContain("alter table pipeline.fee_country_profiles add column if not exists units_are text check (units_are in ('units', 'credit_points'));")
  expect(m).toContain("update pipeline.fee_country_profiles set units_are = case country_code when 'AU' then 'units' else 'credit_points' end")
  expect(m).toContain("elsif v_kind is not null and v_kind = pr.units_are and pr.full_time_units_a_year > 0 then")
  expect(m).toContain("if v_years is not null and (v_whole or v_implied > 1) and abs(v_implied - v_years) > v_tol * greatest(v_years, 1) then")
  expect(m).toContain("security.pipeline_num_v1('fees.units_agreement_pct', 20)")
  expect(m).toContain("if c.hold is not null and v_outcome <> 'same' then\n        if v_outcome = 'admitted' then v_outcome := 'review'; end if;")
  expect(m).toContain("when c.hold is not null then 'Fee reader: the per-year figure is not clear'")
  for (const c of ['Murdoch: 37,800 admitted (whole fee of a 1-year course)', 'switch off: the earlier rule (count / country load) runs as before',
    'UNSW: nothing admitted (course shorter than a year, no load on the page)', 'UNSW: one Layer 4 item, the published figure and the reason',
    'UNSW with a stated load of 48: 31,500 for 24 points is 63,000 a full-time year', 'HELI: Layer 4 proposes 24,600 (49,200 over 2 years)',
    'Reach: not admitted; Layer 4 proposes 13,500', 'Barton: 28,000 admitted (16 units over a 2-year course)', 'VIT: 17,000 admitted (24 units over 3 years)',
    'NZ: 60 points of a 120-point year, 39,859.68 a year (as before)', 'NZ: 120 points is a full-time year, 27,300 annual (as before)'])
    expect(fixtures).toContain(c)
})

test('a raised fee hold or a fee-check exclusion keeps the page fee out, and no AI read is queued for it', () => {
  expect(m).toContain("fl.reason_code = 'fee_crosscheck' and fl.state = 'raised')")
  expect(m).toContain("v_hold := case when v_respect and v_outcome <> 'same' then security.fee_reader_hold_v1(c.course_id) end;")
  expect(m).toContain("if v_hold is not null then v_outcome := 'held'; v_note := v_note || '; not admitted: ' || v_hold; end if;")
  expect(m).toContain("and not (security.pipeline_num_v1('fees.respect_holds_on', 1) >= 1 and security.fee_reader_hold_v1(g.course_id) is not null)")
  expect(m).toContain("update pipeline.fee_course_requests set queued_at = now(), outcome = 'held' where course_id = rq.course_id;")
  for (const c of ['WSU: raised fee check hold, page fee not admitted', 'WSU: no second Layer 4 question', '088407E: fee check decision keeps the 44,300 page fee out',
    'other exclusion: AI second reading admitted as designed (switch off)', 'switch on: every fee exclusion keeps the page fee out',
    'queue: 088407E (fee check decision) not queued for an AI read', 'queue: an Enrich fields request for a held course closes as held, not read'])
    expect(fixtures).toContain(c)
})

test('settings: the correctness fix and the hold respect ship on; extending holds to every exclusion ships off', () => {
  const val = (k) => m.match(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}',[\\s\\S]*?'number', to_jsonb\\((\\d+)\\)`))?.[1]
  expect(val('fees.units_load_fix_on')).toBe('1')
  expect(val('fees.respect_holds_on')).toBe('1')
  expect(val('fees.respect_all_exclusions_on')).toBe('0')
  expect(val('fees.units_agreement_pct')).toBe('20')
  expect(m).toMatch(/^-- Replaces: .+/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
})

test('root causes and remedies are registered through workstream A\'s contract; the auto remedy only measures', () => {
  expect(m).toContain("('fee_reader_units_misread', jsonb_build_object('class', 'rule'")
  expect(m).toContain("('fee_reader_hold_bypass', jsonb_build_object('class', 'rule'")
  expect(m).toContain("'fee:ai\\_reader\\_credit\\_point\\_unit%'")
  expect(m).toMatch(/\('fee_integrity_recheck', [\s\S]*?'authority', 'auto',\n\s+'action_fn', 'security\.fee_integrity_recheck_v1\(bigint\)', 'verify_fn', 'security\.fee_integrity_verify_v1\(bigint\)'/)
  expect(m).toContain("select jsonb_build_object('ok', true, 'changed', false, 'evidence', security.fee_integrity_measure_v1())")
  expect(m).toContain("('fee_wrong_value_withdraw', jsonb_build_object(")
  expect(fixtures).toContain('verify: an AI fee active on a raised hold fails the check')
})

test('the worker asks for the count kind, the page load, the course length and whether the amount is the whole course', () => {
  expect(index).toContain('const WORKER = "coverage-sweep-worker-v0.59.6";')
  for (const k of ['units_kind', 'full_time_load', 'course_years', 'whole_course']) {
    expect(fees).toContain(`"${k}"`)
    expect(fees).toContain(`- ${k}: `)
  }
  expect(fees).toContain('Credit points are never units.')
  expect(fees).toContain('Never copy it from the country line.')
})

test('containment and correction are count-guarded Platform Admin pastes that never delete and never touch a manual value', () => {
  for (const p of [contain, rollback, correction]) {
    expect(p).not.toMatch(/\bdelete\s+from\b/i)
    expect(p).toContain('fxcwkweaxjtknorudmwp')
  }
  expect(contain).toContain("if v_upd <> 13 then raise exception 'withdrew %, expected 13; rolled back', v_upd; end if;")
  expect(contain).toContain('pipeline.manual_locks')
  expect(contain).toContain("set status = 'inactive', valid_to = current_date")
  expect(contain).toContain('perform scholarship.refresh_course_financial_calculations(r.course_id, null);')
  expect(rollback).toContain("if v_n <> 13 then raise exception 'restored %, expected 13; rolled back', v_n; end if;")
  expect(correction).toContain('pipeline.manual_locks')
  expect(correction).toMatch(/raise exception 'guard: .*nothing changed/)
  expect(m).not.toMatch(/\b(drop|delete|truncate)\s+(table|function|from)\b/i)
})
