// Guards: Platform Admin 14 Nov 2026 item 2 "update the v2 prompt and verifier to split lead_in_quote and exact_quote (ordered proximity rule) and align with Lean AI Phase 1b's full-source header-preserved [B#] block input": prompt aer-v2-course-v3 reads the whole stored page as numbered lean-md-v1 blocks; each record cites one block for its exact quote and, apart, one for its lead-in, which must come before it, close to it and under the same heading; held only as evaluation versions with pinned providers (never picked by the paused shadow reader)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { leanText } from '../../supabase/functions/coverage-sweep/lean-input.ts'
import { AER_V3_CONTRACT, AER_V3_INPUT, AER_V3_SCHEMA, aerV2Refs, aerV3Blocks, aerV3Check, aerV3Request, aerV3User, aerV3Verify } from '../../supabase/functions/coverage-sweep/aer-v2.ts'

const M = fs.readFileSync('supabase/migrations/20261114011500_cf247_aer_v2_prompt_v3.sql', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

const page = '<html><nav>Menu</nav><main>' + '<p>About this course and its graduates.</p>'.repeat(50) +
  '<h2>Entry requirements</h2><p>Successful completion of one of the following:</p><ul><li>an Indian CBSE Class XII with an overall average of 75%</li>' +
  '<li>GCE A Levels with 9 points from three subjects</li></ul><h2>International students</h2>' +
  '<table><thead><tr><th>Country</th><th>Minimum</th></tr></thead><tbody><tr><td>Malaysia</td><td>STPM 2.5</td></tr></tbody></table>' +
  '<h3>English language</h3><p>IELTS 6.5 overall.</p></main></html>'
const lean = leanText(page)
const B = aerV3Blocks(lean, 'courseCode: B123')
const refs = aerV2Refs(['IN', 'MY', 'GB'], [{ code: 'GCE_AL', name: 'GCE A Levels' }])
const n = (t) => B.blocks.find((b) => b.text.includes(t)).n
const rec = (over) => ({ scope: 'course', course_name: null, audience: 'international', applicant_country: 'IN', qualification: 'CBSE Class XII', qualification_code: null,
  study_level: null, route: null, min_grade: '75%', min_value: 75, grade_scale: 'percentage', conditions: null,
  exact_block: n('CBSE Class XII'), exact_quote: 'an Indian CBSE Class XII with an overall average of 75%',
  lead_in_block: n('one of the following'), lead_in_quote: 'Successful completion of one of the following:', support: [], confidence: 0.9, ...over })

test('the whole page as numbered blocks: page data first, headings, items and table rows with their column headers, each with its stored-page offset', () => {
  expect(AER_V3_INPUT).toBe('lean-blocks-v1')
  expect(B.input).toBe('lean-blocks-v1/lean-md-v1')
  expect(B.blocks.length).toBe(lean.blocks.length + 1)
  expect(B.text.split('\n')[0]).toBe('[B1 @data] courseCode: B123')
  expect(B.text).toContain(`[B${n('Entry requirements')} @${B.blocks[n('Entry requirements') - 1].source_at}] ## Entry requirements`)
  expect(B.text).toContain('] - an Indian CBSE Class XII with an overall average of 75%')
  expect(B.text).toContain('] Country: Malaysia | Minimum: STPM 2.5')
  expect(B.text).not.toContain('Menu')
  for (const b of B.blocks.slice(1)) expect(page.slice(b.source_at, b.source_at + 1)).toBe('<')
  // never cut: every block of the page is there, the English section too
  expect(B.text).toContain('IELTS 6.5 overall.')
  expect(aerV3Blocks(lean, 'courseCode: B123')).toEqual(B)
})

test('ordered proximity: the lead-in apart, before the statement, close, under the same heading', () => {
  const ok = aerV3Check(rec({}), B, refs, 300, 3)
  expect(ok.reasons).toEqual([])
  expect(ok.pass).toBe(true)
  expect(ok.exact_source_at).toBe(B.blocks[n('CBSE Class XII') - 1].source_at)
  expect(ok.lead_in_source_at).toBe(B.blocks[n('one of the following') - 1].source_at)
  // the v2 trial failure: lead-in and item joined into one quote
  expect(aerV3Check(rec({ exact_quote: 'Successful completion of one of the following: an Indian CBSE Class XII with an overall average of 75%', lead_in_block: null, lead_in_quote: null }), B, refs, 300, 3).reasons).toContain('exact_quote_not_in_block')
  // the lead-in after the statement
  expect(aerV3Check(rec({ lead_in_block: n('GCE A Levels'), lead_in_quote: 'GCE A Levels with 9 points' }), B, refs, 300, 3).reasons).toContain('lead_in_not_before_exact')
  // too far above
  expect(aerV3Check(rec({}), B, refs, 300, 0).reasons).toContain('lead_in_too_far')
  // a heading between the lead-in and the statement
  const t = aerV3Check(rec({ exact_block: n('Malaysia'), exact_quote: 'Country: Malaysia | Minimum: STPM 2.5', min_grade: 'STPM 2.5', min_value: 2.5, applicant_country: 'MY', qualification: null }), B, refs, 300, 10)
  expect(t.reasons).toContain('lead_in_crosses_heading')
  // a heading may itself be the lead-in
  expect(aerV3Check(rec({ exact_block: n('Malaysia'), exact_quote: 'Country: Malaysia | Minimum: STPM 2.5', min_grade: 'STPM 2.5', min_value: 2.5, applicant_country: 'MY', qualification: null,
    lead_in_block: n('International students'), lead_in_quote: 'International students' }), B, refs, 300, 3).pass).toBe(true)
  // the lead-in quoted from a block it is not in, or repeated inside the exact quote
  expect(aerV3Check(rec({ lead_in_block: n('Entry requirements') }), B, refs, 300, 3).reasons).toContain('lead_in_not_in_block')
  expect(aerV3Check(rec({ lead_in_block: n('CBSE'), lead_in_quote: 'an Indian CBSE', exact_quote: 'an Indian CBSE Class XII with an overall average of 75%' }), B, refs, 300, 3).reasons).toContain('lead_in_not_before_exact')
  // no lead-in at all is fine
  expect(aerV3Check(rec({ lead_in_block: null, lead_in_quote: null }), B, refs, 300, 3).pass).toBe(true)
})

test('the minimum is printed inside the exact quote; quotes are inside the block they cite; country and qualification as in v2', () => {
  expect(aerV3Check(rec({ min_grade: 'an overall average of 75 per cent', min_value: 75 }), B, refs, 300, 3).reasons).toContain('minimum_not_in_exact_quote')
  expect(aerV3Check(rec({ min_value: 80 }), B, refs, 300, 3).reasons).toContain('value_not_printed_in_minimum')
  expect(aerV3Check(rec({ exact_block: n('GCE A Levels') }), B, refs, 300, 3).reasons).toContain('exact_quote_not_in_block')
  expect(aerV3Check(rec({ exact_block: 9999 }), B, refs, 300, 3).reasons).toContain('exact_block_unknown')
  expect(aerV3Check(rec({}), B, refs, 20, 3).reasons).toContain('exact_quote_too_long')
  expect(aerV3Check(rec({ support: [{ value: 'route', block: n('International students'), text: 'International students' }] }), B, refs, 300, 3).pass).toBe(true)
  expect(aerV3Check(rec({ support: [{ value: 'route', block: n('CBSE'), text: 'International students' }] }), B, refs, 300, 3).reasons).toContain('support_not_in_block')
  expect(aerV3Check(rec({ applicant_country: 'XX' }), B, refs, 300, 3).reasons).toContain('country_not_in_reference')
  expect(aerV3Check(rec({ qualification_code: 'NOPE' }), B, refs, 300, 3).reasons).toContain('qualification_not_in_reference')
  const v = aerV3Verify({ records: [rec({}), rec({ exact_block: 9999 })], seen_not_mapped: [{ statement: 'English', block: n('IELTS'), quote: 'IELTS 6.5 overall.' }] }, B, refs, 300, 3)
  expect([v.passed, v.failed]).toEqual([1, 1])
  expect(v.seen_not_mapped[0].on_page).toBe(true)
})

test('the request: strict v3 schema, require_parameters always, the version routing pinned, params never replace the model, schema or messages', () => {
  expect(AER_V3_CONTRACT).toBe('aer-v2-answer-v3')
  const r = aerV3Request('xiaomi/mimo-v2.6-flash', 'S', 'U', 12000, { order: ['xiaomi/fp8'], allow_fallbacks: false, require_parameters: false },
    { reasoning: { enabled: false }, model: 'openai/gpt-4.1-mini', response_format: null })
  expect(r.model).toBe('xiaomi/mimo-v2.6-flash')
  expect(r.provider).toEqual({ order: ['xiaomi/fp8'], allow_fallbacks: false, require_parameters: true })
  expect(r.reasoning).toEqual({ enabled: false })
  expect(r.response_format.json_schema.strict).toBe(true)
  expect(r.response_format.json_schema.schema).toBe(AER_V3_SCHEMA)
  expect(r.temperature).toBe(0)
  expect(AER_V3_SCHEMA.properties.records.items.required).toEqual(expect.arrayContaining(['exact_block', 'exact_quote', 'lead_in_block', 'lead_in_quote', 'support']))
  const u = aerV3User({ title: 'Bachelor of Science', provider: 'Example University', provider_country: 'AU' }, [{ code: 'GCE_AL', name: 'GCE A Levels' }], B)
  expect(u).toContain(`PAGE BLOCKS (${B.blocks.length} blocks, the whole page, in page order):\n[B1 @data]`)
})

test('the worker reads a v3 version over the whole page as blocks; v1 versions as before', () => {
  expect(IX).toContain('const v3 = String(ver.answer_contract || "") === AER_V3_CONTRACT, gapMax = wsNum("reading.aer_v3_lead_in_max_blocks", 3);')
  expect(IX).toContain('const blocks = v3 ? aerV3Blocks(leanText(raw), di) : null;')
  expect(IX).toContain('aerV3Request(model, system, aerV3User(')
  expect(IX).toContain('aerV3Verify(ans.a, blocks, refs, quoteMax, gapMax) : aerV2Verify(ans.a, text, refs, quoteMax)')
  expect(IX).toContain('a cut page is never read')
})

test('held as three evaluation versions with one prompt text and pinned providers; the paused reader, its trial version and the queue untouched; no GPT-4.1 mini', () => {
  expect(M).toContain("'aer-v2-course-v3-qwen3-30b',         'qwen/qwen3-30b-a3b-instruct-2507',         '{\"order\": [\"siliconflow/fp8\", \"nebius/fp8\"], \"allow_fallbacks\": false}'")
  expect(M).toContain("'aer-v2-course-v3-mistral-small-3.2', 'mistralai/mistral-small-3.2-24b-instruct'")
  expect(M).toContain("'aer-v2-course-v3-mimo-v2.6-flash',   'xiaomi/mimo-v2.6-flash'")
  expect(M).toContain("'{\"reasoning\": {\"enabled\": false}}'")
  expect(M).toContain("v.model, 300, 'evaluation',")
  expect(M).not.toContain('gpt-4.1-mini')
  expect(M).toContain("select pg_temp.edit_n('security.aer_v2_shadow_hold_v1()', 'b8d1f95c8a171c5346d2a4c88c9adbb3'")
  expect(M).toContain("if h->'version'->>'version' is distinct from 'aer-v2-course-v2' then raise exception")
  expect(M).toContain('Never join a lead-in and a list item into one quote')
  expect(M).not.toMatch(/key\s*=\s*'aer\.v2_shadow_on'|aer_v2_shadow_results\s+(set|where)|status\s*=\s*'trial'\s*where/i)
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(M).not.toMatch(/insert into catalogue\.|course_entry_review_apply_v1/)
  expect(M).toMatch(/^-- Replaces: /m)
})
