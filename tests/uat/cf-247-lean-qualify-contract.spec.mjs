// Guards: CF-247 Lean AI Input Phase 1b-3 (Platform Admin 14 Nov 2026 17:20, admin docs/platform/LEAN-AI-INPUT-PHASE1B-3-QUALIFICATION-PLAN-FEES-INTAKES.md):
// the fees and intakes qualification reads each labelled stored page twice on the service's pinned route (today's input and the selected
// [B#] blocks) with the same instructions and context; answers are recorded only (nothing admitted, no value written); the database enforces
// the US$2.00 ceiling and the route holds; the job ships off; a pass switches nothing on.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { BLOCKS_LINE, FEE_CANDIDATE_PROMPT, INTAKE_CANDIDATE_PROMPT, INTAKE_PROMPT_SENTENCES, LEAN_QUALIFY, feeFound, feeRequest, intakeFound, intakeRequest, quoteHeld } from '../../supabase/functions/coverage-sweep/lean-qualify.ts'
import { FEE_AI_PROMPT, feeAiRequest } from '../../supabase/functions/coverage-sweep/fees.ts'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261114091500_cf247_lean_qualify_fees_intakes.sql', 'utf8')
const body = IX.slice(IX.indexOf('if (mode === "lean_qualify")'), IX.indexOf('if (mode === "lean_sections_eval")'))

test('both arms send the same instructions and context; the candidate adds only the blocks line; the intakes baseline is the live prompt sentence for sentence', () => {
  expect(LEAN_QUALIFY).toBe('lean-qualify-v1')
  for (const sentence of INTAKE_PROMPT_SENTENCES) expect(IX, sentence.slice(0, 60)).toContain(JSON.stringify(sentence).slice(1, -1))
  const base = intakeRequest('m', 'Uni', 'BSc', 'Starts February and July', false, 400), cand = intakeRequest('m', 'Uni', 'BSc', '[B1 @0] Starts February and July', true, 400)
  expect(cand.messages[0].content).toBe(base.messages[0].content + ' ' + BLOCKS_LINE)
  expect(cand.messages[1].content.replace('[B1 @0] ', '')).toBe(base.messages[1].content)
  expect(base.response_format).toEqual(cand.response_format)
  const it = { provider: 'Uni', country: 'AU', url: 'https://x', courses: [{ id: 'c1', title: 'BSc', level: 'bachelor' }], course_page: true }
  const fb = feeRequest('m', it, 'Fee A$46,500 per year', false, 900), fc = feeRequest('m', it, '[B3 @10] Fee A$46,500 per year', true, 900)
  expect(fb).toEqual(feeAiRequest('m', it, 'Fee A$46,500 per year', 900))
  expect(fc.messages[0].content).toBe(FEE_AI_PROMPT)
  expect(fc.messages[1].content).toContain(BLOCKS_LINE + '\n\nPage text:\n[B3 @10] Fee')
  expect([FEE_CANDIDATE_PROMPT, INTAKE_CANDIDATE_PROMPT]).toEqual(['fee-reader+blocks-v1', 'course-intakes+blocks-v1'])
})

test('judging: a label is found only when the proven answer gives it; a quote across two blocks is not held in the labelled text', () => {
  expect(intakeFound('February, July', ['February', 'July'])).toBe(true)
  expect(intakeFound('February', ['February', 'July'])).toBe(false)
  expect(intakeFound(null, ['February'])).toBe(false)
  expect(feeFound([{ amount_min: 46500, amount_max: null }], ['46500'])).toBe(true)
  expect(feeFound([{ amount_min: 46000, amount_max: 47990 }], ['47990'])).toBe(true)
  expect(feeFound([{ amount_min: 4650, amount_max: null }], ['46500'])).toBe(false)
  expect(quoteHeld('[B1 @0] Intakes: February\n[B2 @20] and July', 'Intakes: February')).toBe(true)
  expect(quoteHeld('[B1 @0] Intakes: February\n[B2 @20] and July', 'February and July')).toBe(false)
})

test('worker mode lean_qualify: stored copies only, the pinned route of each service, nothing admitted or written beyond the qualification record', () => {
  expect(IX).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(9[4-9]|\d{3,})\.\d+";/)
  expect(body).toContain('rpc("svc_lean_qualify_next_v1"')
  expect(body).toContain('rpc("svc_lean_qualify_record_v1"')
  expect(body).toContain('readEvidenceCopy(c, String(it.storage_path))')
  expect(body).toContain('service: f === "fees" ? "fee_reader" : "course_other_fields", source: "lean_qualify"')
  expect(body).toContain('models: it.models')
  expect(body).not.toMatch(/fcScrape|firecrawl|svc_fc_spend|svc_fee_ai_record|svc_enrich|_admit|layer4|publish/i)
  expect(body.match(/rpc\("/g)?.length).toBe(4)  // the credential profile, next, record, and nothing else
})

test('migration: ships off, ceiling and route holds enforced by the database, catalogued job, read-only report; nothing dropped or deleted', () => {
  expect(MIG).toMatch(/^-- Replaces: nothing\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\.$/m)
  expect(MIG).toContain("comment on table pipeline.lean_qualify_cases is 'CF-247 Lean AI Input Phase 1b-3")
  expect(MIG).toContain("'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1448")
  expect(MIG).toContain("'number', '2'::jsonb, 0, 5, 'US$', 1450")
  expect(MIG).toContain("if v_spent >= security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0) then return '[]'::jsonb; end if;")
  expect(MIG).toContain("coalesce((v_fee->>'held')::boolean, true) = false")
  expect(MIG).toContain("coalesce((v_int->>'held')::boolean, true) = false")
  expect(MIG).toContain("perform cron.schedule('lean-qualify', '* * * * *', 'select security.lean_qualify_fire_v1()');")
  expect(MIG).toContain("('lean-qualify', 'Course pages', 43,")
  expect(MIG).toContain("'admitted', 0,")
  expect(MIG).not.toMatch(/^\s*(drop|truncate|delete)\b/im)
  expect(MIG).not.toMatch(/insert into (pipeline\.(field_enrich|fee_rows|course_fee|layer4)|catalogue\.)/i)
})
