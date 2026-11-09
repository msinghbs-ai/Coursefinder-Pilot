// Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first) – one weak sentence must not sink a provider-description proposal whose other sentences are supported
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { copyNote, descriptionRequest, DESCRIPTION_SYSTEM, descriptionClaimCheck } from '../../supabase/functions/coverage-sweep/description.ts'

const MIG = fs.readFileSync('supabase/migrations/20261110120000_cf247_pdesc_sentence_filter.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')   // the statements, without the comments
const HARNESS = fs.readFileSync('tests/fixtures/pdesc-sentence-filter/run.sh', 'utf8')
const SCEN = fs.readFileSync('tests/fixtures/pdesc-sentence-filter/scenarios.sql', 'utf8')
const EXPECTED = fs.readFileSync('tests/fixtures/pdesc-sentence-filter/expected.txt', 'utf8')
const EXPECTED_BEFORE = fs.readFileSync('tests/fixtures/pdesc-sentence-filter/expected-before.txt', 'utf8')
const HELD = fs.readFileSync('supabase/held/pdesc_sentence_filter_forward_recovery.sql', 'utf8')
const REPLAY = fs.readFileSync('supabase/held/pdesc_sentence_filter_replay.sql', 'utf8')
const WF = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const VAL = 'security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'
const REC = 'public.svc_provider_description_record(jsonb)'
const VAL_BEFORE = 'c1d56ef145b0673d3c475fdaa677ae1d', VAL_AFTER = '7347f51b70a0c4a6cdd01a117080aad5'
const REC_BEFORE = '9b2137954bc05501e55e93c8ef9cf448', REC_AFTER = '5dab0348f912018e517671aef376c5b6'

test('the migration names what it replaces and retires, records the live md5 before and after, and edits the validator and the recorder only', () => {
  expect(MIG).toMatch(/^-- Replaces: .*provider_description_validate_v1.*svc_provider_description_record/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain(`${VAL} ${VAL_BEFORE} -> ${VAL_AFTER}`)
  expect(MIG).toContain(`${REC} ${REC_BEFORE} -> ${REC_AFTER}`)
  expect(CODE).toContain(`replace_body('${VAL}', '${VAL_BEFORE}', '${VAL_AFTER}'`)
  expect(CODE).toContain(`edit_all('${REC}', '${REC_BEFORE}', '${REC_AFTER}'`)
  expect(CODE).toContain("raise exception 'live % differs from the definition this change edits")
  expect(CODE).toContain("return p_sig || ': already applied'")
  expect(CODE).not.toMatch(/create or replace function (?!pg_temp)/i)
  expect(CODE).not.toMatch(/\b(insert into|delete from|drop |truncate|alter table|create table|create trigger|create index|cron\.schedule)\b/i)
  expect(MIG).toContain('Consumer API (G3): not touched')
})

test('the filter is opt-in: only the record of a new read asks for it, so the machine admission, the human approval and the picker re-check hold the answer on the first failing sentence as before', () => {
  expect(CODE).toContain("coalesce((p_result->>'drop_failing')::boolean, false)")
  expect(CODE).toContain("x->'answer' || jsonb_build_object('drop_failing', true)")
  // the recorder stores the KEPT sentences for a proposal, and nothing is rebound for a held answer
  expect(CODE).toContain("if v_chk->>'outcome' in ('propose', 'verified') and v_chk ? 'sentences' then x := jsonb_set(x, '{answer,sentences}', v_chk->'sentences'); end if;")
  expect(CODE.match(/drop_failing/g).length).toBeGreaterThanOrEqual(2)
  const callers = fs.readdirSync('supabase/migrations').filter((f) => f >= '20261109000000').map((f) => fs.readFileSync(`supabase/migrations/${f}`, 'utf8')).join('\n')
  expect(callers).not.toMatch(/'drop_failing',\s*true[^\n]*machine_admit/)   // the machine admission does not set it
})

test('no sentence rule is loosened: the rules and their order are the earlier text; a dropped sentence is recorded with its rule, reason and support', () => {
  const body = CODE.slice(CODE.indexOf("$nb$") + 4, CODE.lastIndexOf("$nb$"))
  const order = ['quote_not_on_page', 'unsupported_marketing', 'unsupported_claim', 'incomplete_sentence', 'unsupported_numeric_claim', 'verbatim_passage', 'historic_claim_context', 'unsupported_sentence']
  let at = -1
  for (const rule of order) { const i = body.indexOf(`'rule', '${rule}'`) >= 0 ? body.indexOf(`'rule', '${rule}'`) : body.indexOf(`'rule','${rule}'`); expect(i, rule).toBeGreaterThan(at); at = i }
  // thresholds still come from settings (G2): the minimum sentences, the length, the support share, the copy limit
  for (const key of ['pdesc.min_sentences', 'pdesc.max_sentences', 'pdesc.min_chars', 'pdesc.max_chars', 'pdesc.support_min_share', 'pdesc.verbatim_span_max_chars']) expect(body, key).toContain(key)
  // kept sentences below the minimum hold the read with the rule of the FIRST failing sentence
  expect(body).toMatch(/jsonb_array_length\(v_keep\) < security\.pipeline_num_v1\('pdesc\.min_sentences', 2\) then\s+return v_first/)
  expect(body).toContain("'dropped', v_dropped")
  const keys = body.slice(body.indexOf('v_dropped := v_dropped'), body.indexOf('v_dropped := v_dropped') + 600)
  for (const k of ["'index'", "'rule'", "'reason'", "'support'", "'text'"]) expect(keys, k).toContain(k)
  // no new setting, no operational number written into the statements (G2); the one setting touched already exists
  expect(CODE).not.toMatch(/insert into pipeline\.platform_toolset_settings/)
  expect(MIG).toContain('No operational number is written into code (G2)')
})

test('the harness proves the fault, then the fix: one unsupported, copied or off-page sentence no longer sinks the others; too few kept, all copied, six sentences and the unflagged call are still held', () => {
  const lines = (s) => new Set(s.split('\n').filter(Boolean))
  const before = lines(EXPECTED_BEFORE), after = lines(EXPECTED)
  // the live fault: the flag is ignored and one sentence holds the answer (the Sydney shape: an aim the quote does not state)
  expect(before.has('aim_flag_keeps_two|held|unsupported_sentence|kept=-1|dropped=-|chars=309')).toBe(true)
  expect(before.has('copy_flag_keeps_two|held|verbatim_passage|kept=-1|dropped=-|chars=333')).toBe(true)
  expect(before.has('off_flag_keeps_two|held|quote_not_on_page|kept=-1|dropped=-|chars=269')).toBe(true)
  expect(before.has('e2e_aim_read|held|unsupported_sentence|proposal=3|dropped=-|item=-|text_has_aim=false')).toBe(true)
  for (const [name, rule] of [['aim', 'unsupported_sentence'], ['copy', 'verbatim_passage'], ['off', 'quote_not_on_page'], ['marketing', 'unsupported_marketing'], ['ranking', 'unsupported_claim'], ['number', 'unsupported_numeric_claim'], ['fragment', 'incomplete_sentence']]) {
    const key = ['aim', 'copy', 'off'].includes(name) ? `${name}_flag_keeps_two` : `${name}_flag`
    expect(after.has(`${key}|propose|kept=2|dropped=${rule}|chars=203`), key).toBe(true)
  }
  // the proposal is made of the kept sentences and goes to Layer 4 with them
  expect(after.has('e2e_aim_read|proposed|missing|proposal=2|dropped=unsupported_sentence|item=2|text_has_aim=false')).toBe(true)
  // still held
  for (const held of ['aim_plain_holds|held|unsupported_sentence|kept=-1|dropped=-|chars=309', 'copy_plain_holds|held|verbatim_passage|kept=-1|dropped=-|chars=333', 'off_plain_holds|held|quote_not_on_page|kept=-1|dropped=-|chars=269',
                      'one_kept_holds_first_rule|held|unsupported_sentence|kept=-1|dropped=unsupported_sentence,verbatim_passage|chars=89', 'one_kept_holds_first_rule_b|held|verbatim_passage|kept=-1|dropped=verbatim_passage,unsupported_sentence|chars=89',
                      'all_copied_holds|held|verbatim_passage|kept=-1|dropped=verbatim_passage,verbatim_passage|chars=0', 'six_sentences_flag|held|sentence_count|kept=-1|dropped=-|chars=611', 'flag_false_holds|held|unsupported_sentence'])
    expect(after.has(held), held).toBe(true)
  // the answer given in full, with no failing sentence, is the same with or without the flag
  expect(after.has('two_good_plain|propose|kept=-1|dropped=-|chars=203')).toBe(true)
  expect(after.has('two_good_flag|propose|kept=2|dropped=-|chars=203')).toBe(true)
  expect([...after].some((l) => l.startsWith('dropped_detail|1|unsupported_sentence|2|The university is dedicated'))).toBe(true)
  expect(HARNESS).toContain('applied again: no change')
  expect(HARNESS).toContain('are each refused by the migration and by the forward recovery (nothing applied)')
})

test('the setting that re-offers earlier holds lists the sentence rules (existing setting, no new one) and the replay is a single read-only SELECT', () => {
  expect(CODE).toContain("update pipeline.platform_toolset_settings s")
  expect(CODE).toContain("s.key = 'pdesc.identity_reeval_rules'")
  for (const r of ['verbatim_passage', 'quote_not_on_page', 'unsupported_sentence', 'unsupported_claim', 'unsupported_numeric_claim']) expect(CODE, r).toContain(`'${r}'`)
  expect(CODE.slice(CODE.indexOf('update pipeline.platform_toolset_settings s'))).not.toMatch(/'not_stated'/)   // the model said the page does not describe the institution: not read again
  const rep = REPLAY.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')
  expect(rep).not.toMatch(/\b(insert|update|delete|drop|alter|create|truncate)\b/i)
  expect(rep.trim().startsWith('with p as')).toBe(true)
  expect(rep.trim().endsWith(';')).toBe(true)
  expect((rep.match(/;/g) || []).length).toBe(1)
  expect(HARNESS).toContain('keeps two of the three on a held read')
})

test('the forward recovery restores both earlier bodies byte for byte, guarded by the md5 of what is live, and the three identity rules', () => {
  for (const m of [VAL_BEFORE, VAL_AFTER, REC_BEFORE, REC_AFTER]) expect(HELD).toContain(m)
  expect(HELD.match(/CREATE OR REPLACE FUNCTION/g)).toHaveLength(2)
  expect(HELD).toContain('differs from both texts this recovery knows')
  expect(HELD).not.toContain('drop_failing')
  expect(HARNESS).toContain('restores body md5 $VAL_BEFORE and $REC_BEFORE byte for byte')
})

test('the worker asks for one short paraphrase per quote, states the copy limit, and does not hold a whole answer for a copied sentence (fails on the earlier worker)', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v0.60.0";')
  expect(IX).toContain('reader_behavior_version: "provider-description-source-guard-v4" };')
  expect(IX).not.toContain('reader_behavior_version: "provider-description-source-guard-v3" };')
  expect(IX).toContain('if (!claimCheck.ok && claimCheck.rule !== "verbatim_passage") {')
  expect(IX).toContain('Number(w.verbatim_span_max_chars))')
  expect(DESCRIPTION_SYSTEM).toMatch(/short/i)
  expect(DESCRIPTION_SYSTEM).toMatch(/own words/i)
  expect(DESCRIPTION_SYSTEM).toMatch(/one quote/i)
  expect(copyNote(120)).toBe('Copy limit: keep each sentence short (under 120 characters) and never repeat 120 or more characters in a row from its quote.\n')
  expect(copyNote(0)).toBe('')
  expect(copyNote(Number.NaN)).toBe('')
  const req = descriptionRequest('approved-model', 'Riverstone University', 'https://riverstone.example/about', 'Official institutional source text.', 1500, undefined, 120)
  expect(JSON.stringify(req)).toContain('never repeat 120 or more characters in a row')
  // the limit is the governed one, never a literal in the prompt text
  expect(DESCRIPTION_SYSTEM).not.toMatch(/\b120\b/)
  // the worker still checks the other claims: a copied sentence alone is the only rule it lets through to the database
  expect(descriptionClaimCheck({ sentences: [{ text: 'a'.repeat(120), quote: 'a'.repeat(120) }] }, 120).rule).toBe('verbatim_passage')
})

test('the harness and the spec are wired into the provider-description workflow, with a guard line', () => {
  expect(WF).toContain('bash tests/fixtures/pdesc-sentence-filter/run.sh')
  expect(WF).toContain('tests/uat/cf-247-pdesc-sentence-filter-contract.spec.mjs')
  expect(HARNESS).toMatch(/^# Guards: Platform Admin operating model v1\.5/m)
  expect(SCEN).toMatch(/^-- Guards: Platform Admin operating model v1\.5/m)
})
