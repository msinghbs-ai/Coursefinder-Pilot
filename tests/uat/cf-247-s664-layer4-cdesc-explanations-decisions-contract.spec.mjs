// Guards: Layer 4 course description cards explain every hold in plain English and offer four purpose-built decisions (Platform Admin 18 Nov 2026, chat S1-Courses, s664): "Why this is held & recommended action" maps each cdesc-machine-v2 hold (identity_margin_thin, first_provider_sample, sentence_count_over_2, boilerplate_detected, quote_mismatch and the rest) to words without raw codes, with the page match score, quote check and sentence count; the buttons are Approve as read, Re-read (1-2 sentences), Approve all verified for provider (count confirmed) and Reject (bad page / wrong course); university descriptions keep their two.
// CF-247 S664. src/lib/cdesc-hold.js (CD_HOLD, cdHoldKey, cdChoices), src/CourseDescriptionPanel.jsx (CdWhy), src/Layer4Inbox.jsx, migration 20261119084000 (md5-guarded edits of security.layer4_inbox_kinds_v1, security.layer4_inbox_items_v2, public.admin_layer4_inbox). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119084000_cf247_s662_s664_cdesc_one_two_sentences_identity_proof.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const INBOX = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
let P
test.beforeAll(async () => { P = await import('../../src/lib/cdesc-hold.js') })

test('every machine hold maps to a plain-English explanation with an action, never the raw code', () => {
  const codes = { identity_margin_thin: 'identity_margin_thin', '': 'first_provider_sample', check_sentence_count: 'sentence_count_over_2', policy_refused_word: 'boilerplate_detected',
    check_quote_not_on_page: 'quote_mismatch', check_unsupported_sentence: 'quote_mismatch', binding_ambiguous: 'binding_ambiguous', evidence_moved: 'evidence_moved',
    wrong_page_kind: 'wrong_page_kind', duplicate_exact_waiting: 'duplicate', rejected_before_course: 'rejected_before', something_new: 'other' }
  for (const [c, k] of Object.entries(codes)) expect(P.cdHoldKey(c), c).toBe(k)
  for (const [k, h] of Object.entries(P.CD_HOLD)) {
    expect(h.title && h.why && h.action, k).toBeTruthy()
    for (const t of [h.title, h.why, h.action]) expect(t, k).not.toMatch(/[a-z]+_[a-z_]+/)
  }
  expect(P.CD_HOLD.sentence_count_over_2.action).toContain('Re-read (1-2 sentences)')
})

test('the card shows the match score, the quote check and the sentence count', () => {
  const src = fs.readFileSync('src/CourseDescriptionPanel.jsx', 'utf8')
  for (const a of ['data-l4-cd-why-match', 'data-l4-cd-why-quotes', 'data-l4-cd-why-count', 'Why this is held:', 'Recommended action:']) expect(src).toContain(a)
  expect(INBOX).toContain("{it.kind==='provider_description'&&isCourseDescription(d)&&<CdWhy d={d}/>}")
  // the detail the box reads: the latest decline, the binding and the limits, for course descriptions only
  expect(code).toContain("select pg_temp.edit_all('security.layer4_inbox_items_v2(uuid,text,text[],boolean)', '14e939ac0df0320a116e450da20109c0', '9c30f272f44e09661724c621049da862'")
  expect(code).toContain("|| case when r.field_code = 'course_description_first_read' then jsonb_build_object(")
  expect(code).toContain("'binding', (select jsonb_build_object('status', gb.status, 'basis', gb.basis, 'identity_basis', gb.identity_basis, 'score', gb.score, 'runner_up', gb.runner_up, 'url', gb.url)")
})

test('four decisions on a course description, in order and named for what they do; two on a university description', () => {
  const all = [{ key: 'approve', label: 'Approve as read' }, { key: 'reject', label: 'Reject' }, { key: 'reread', label: 'Re-read (1-2 sentences)' }, { key: 'approve_provider', label: 'Approve all verified for provider', input: 'count' }]
  expect(P.cdChoices(all, true).map((c) => c.label)).toEqual(['Approve as read', 'Re-read (1-2 sentences)', 'Approve all verified for provider', 'Reject (bad page / wrong course)'])
  expect(P.cdChoices(all, false).map((c) => c.key)).toEqual(['approve', 'reject'])
  // s802 (20 Nov 2026): Edit & Approve opens the editor; its edit_approve choice is not one of the card's listed decisions
  expect(INBOX).toContain("const cdChoiceList=it.kind==='provider_description'?cdChoices(choices.filter(c=>c.key!=='edit_approve'),isCourseDescription(d)):choices")
  expect(INBOX).toContain('{cdChoiceList.map(c=>')
  expect(INBOX).toContain("{open.input==='count'&&<input")
  expect(code).toContain("select pg_temp.edit_all('security.layer4_inbox_kinds_v1()', '8c820d6912a240ece0e731221261e6de', 'e56cf8d360ff6413638a77dd3a34d8ac'")
  expect(code).toContain('{"key": "reread", "label": "Re-read (1-2 sentences)"')
  expect(code).toContain('{"key": "approve_provider", "label": "Approve all verified for provider", "input": "count"')
})

test('Re-read re-queues the stored page without marking the course bad', () => {
  expect(code).toContain("select pg_temp.edit_all('public.admin_layer4_inbox(text,jsonb)', 'e5f79c1bc29578e053cba6411d6a5d05', 'aa5333b31a5f3563d6d8212fd9d4ee08'")
  const rr = code.slice(code.indexOf("elsif v_kind = 'provider_description' and v_choice = 'reread' then"), code.indexOf("elsif v_kind = 'provider_description' and v_choice = 'approve_provider' then"))
  expect(rr).toContain("set status = 'superseded'")
  expect(rr).toContain("set reason = left('reread: a person asked in Layer 4")
  expect(rr).not.toMatch(/'rejected'|manual_locks|enrichment_flags|catalogue\.courses/)
  expect(code).toContain("raise exception 'this choice is for course descriptions only'")
})

test('Approve all verified for provider admits only own-page, quote-verified descriptions, after the person confirms the count', () => {
  const ap = code.slice(code.indexOf("elsif v_kind = 'provider_description' and v_choice = 'approve_provider' then"), code.indexOf("  elsif v_kind = 'provider_description' then\n    -- CF-247 P1"))
  expect(ap).toContain("gq.identity_basis in ('cricos_code', 'nzqa_code', 'exact_title')")
  expect(ap).toContain("coalesce((security.course_description_check_v1(cq.id, fq.value)->>'ok')::boolean, false)")
  expect(ap).toContain("nullif(btrim(cq.description), '') is null")
  expect(ap).toContain('v_value::int <> v_cd_n')
  expect(ap).toContain("jsonb_build_object('ok', false")
  expect(ap).toContain("public.layer4_review_decide(v_prov, 'approve'")
})
