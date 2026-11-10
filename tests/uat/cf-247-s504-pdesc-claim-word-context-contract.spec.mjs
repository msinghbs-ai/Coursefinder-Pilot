// Guards: F-PDESC Directive 3 Blocker A (Platform Admin, 9 Nov 2026): the machine admission rule allows the neutral population words in pdesc.machine_neutral_words (students, staff, alumni) only when every sentence that uses one is supported by its exact official quote, keeps refusing ranking, outcome, accreditation, award, facility, superlative, finance, visa and figure claims, reads the words from a setting (G2) and re-evaluates declined proposals only through the existing settlement (migration 20261109120000)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109120000_cf247_pdesc_claim_word_context.sql'
const M = fs.readFileSync(MIG, 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)
const run = fs.readFileSync('tests/fixtures/pdesc-claim-context/run.sh', 'utf8')
const scenarios = fs.readFileSync('tests/fixtures/pdesc-claim-context/scenarios.sql', 'utf8')
const expected = fs.readFileSync('tests/fixtures/pdesc-claim-context/expected.txt', 'utf8').split('\n').filter(Boolean)
const workflow = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/description.ts', 'utf8')
const fnBody = (name) => { const i = C.indexOf(`create or replace function ${name}(`); expect(i, name).toBeGreaterThan(-1); const j = C.indexOf('\n$f$;', i); return C.slice(i, j) }

test('housekeeping: Replaces and Retires lines, comments and revokes on the new functions, nothing dropped, no table or job added', () => {
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(C).not.toMatch(/\bdrop\s+(function|table|index|trigger)|\bdelete\s+from|\btruncate\b/i)
  expect(C).not.toMatch(/create table|cron\.schedule/i)
  for (const sig of ['security.pdesc_machine_neutral_supported_v1(text, jsonb)', 'security.pdesc_machine_text_check_ctx_v1(uuid, text, text[], jsonb)']) {
    expect(C).toContain(`comment on function ${sig} is '`)
    expect(C).toContain(`revoke all on function ${sig} from public, anon, authenticated;`)
  }
  expect(C).toContain('comment on function security.pdesc_machine_text_check_v1(uuid, text, text[]) is')
  // the consumer API (G3) is neither edited nor created
  const edits = [...C.matchAll(/pg_temp\.edit_all\('([^']+)'/g)].map((m) => m[1])
  expect(edits).toEqual(['security.pdesc_machine_text_check_v1(uuid,text,text[])', 'security.provider_description_machine_gate_v1(uuid,text,jsonb)', 'security.provider_description_machine_admit_v1(uuid)', 'public.svc_provider_description_record(jsonb)'])
  expect(edits.filter((e) => /website_|zoho_|^api\./.test(e))).toEqual([])
  expect([...C.matchAll(/create or replace function ([a-z_]+\.[a-z_0-9]+)/g)].map((m) => m[1]).filter((n) => !n.startsWith('pg_temp.')).sort())
    .toEqual(['security.pdesc_machine_neutral_supported_v1', 'security.pdesc_machine_text_check_ctx_v1'])
})

test('the edits are guarded by the live body md5 and the recorded after md5 is the one each edit checks', () => {
  const hdr = [...M.matchAll(/^--   ([a-z0-9_.]+\([^)]*\)) ([0-9a-f]{32}) -> ([0-9a-f]{32})/gm)].map((m) => [m[1], m[2], m[3]])
  expect(hdr.map((h) => h[0])).toEqual(['security.pdesc_machine_text_check_v1(uuid,text,text[])', 'security.provider_description_machine_gate_v1(uuid,text,jsonb)', 'security.provider_description_machine_admit_v1(uuid)', 'public.svc_provider_description_record(jsonb)'])
  // the live bodies read on 9 Nov 2026 (project fxcwkweaxjtknorudmwp)
  expect(hdr.map((h) => h[1])).toEqual(['d432bc25734a4e6cab634f4b709ad8e5', '60cb6d649d95f63e99b6e6a90db62810', '3a13bb31181106c9b128c4c905f7b874', '3114f845b25fc31ed97eaab0f56ee297'])
  for (const [sig, before, after] of hdr) expect(C, sig).toContain(`'${sig}', '${before}', '${after}'`)
  expect(M).not.toContain('@@')
  expect(C).toContain('select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure')
  expect(C).toContain('differs from the definition this change edits')
  expect(C).toContain('must apply exactly once')
  for (const t of ['the changed functions differ from the edited ones', 'the migration changed setting values', 'the second run was not a no-op', 'case "$DB" in g_*)', 'differs from the definition this change edits', 'the only new setting should be pdesc.machine_neutral_words']) expect(run, t).toContain(t)
})

test('G2: the neutral words are a setting with label, range, unit, section and used_by; no word list is written into the functions', () => {
  expect(C).toMatch(/\('pipeline', 'pdesc\.machine_neutral_words', 'Provider descriptions: [^']+',/)
  expect(C).toContain(`'list', '["students", "staff", "alumni"]'::jsonb, 0, null, 'words', 1022, 'Provider descriptions', 'security.pdesc_machine_text_check_ctx_v1, security.pdesc_machine_neutral_supported_v1',`)
  expect(C).toContain('on conflict (toolset_key, key) do nothing;')
  // the words are read from the setting, never written in a function body
  const helper = fnBody('security.pdesc_machine_neutral_supported_v1')
  expect(helper).toContain("security.toolset_setting('pipeline', 'pdesc.machine_neutral_words')")
  const ctx = fnBody('security.pdesc_machine_text_check_ctx_v1')
  for (const w of ['students', 'staff', 'alumni']) { expect(helper).not.toMatch(new RegExp(`'${w}'`)); expect(ctx).not.toMatch(new RegExp(`'${w}'`)) }
  // the figure rule still reads its setting; the figure limits are not loosened here
  expect(ctx).toContain("security.pipeline_num_v1('pdesc.machine_numbers_allowed', 0) < 1")
  expect(C).not.toMatch(/update pipeline\.platform_toolset_settings|machine_numbers_allowed.*insert/i)
})

test('the exemption is narrow: only claim words and the French list, only supported words; every other list and the figure rule still refuse', () => {
  const ctx = fnBody('security.pdesc_machine_text_check_ctx_v1')
  expect(ctx).toContain("array['pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr']")
  expect(ctx).toContain("if l in ('pdesc.claim_words', 'pdesc.machine_refused_words_fr') and lower(w) = any(v_ok) then continue; end if;")
  const helper = fnBody('security.pdesc_machine_neutral_supported_v1')
  // provenance: on_page, a quote that holds the same word and does not negate it, and a text that is exactly the sentences
  for (const t of ["(s->>'on_page')::boolean", 'security.pdesc_has_term_v1(s->>\'quote\', w)', "security.pdesc_claim_check_v1(s->>'text', s->>'quote', w) is not null", 'v_norm is distinct from']) expect(helper, t).toContain(t)
  expect(helper).toContain('v_seen and not v_bad')
  // the strict form (no sentences) is kept for the register-fact profile
  expect(C).toContain("return security.pdesc_machine_text_check_ctx_v1(p_provider, p_text, p_codes, '[]'::jsonb);")
  // the gate, the admission and the reader pass the sentences; the register-fact tier passes none
  expect(C).toContain("security.pdesc_machine_text_check_ctx_v1(p.id, p_text, v_codes, coalesce(p_ctx->'sentences', '[]'::jsonb))")
  expect(C).toContain("'sentences', case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end")
  expect(C).toContain("jsonb_build_object('tier',r.read_via,'sentences',x->'answer'->'sentences')")
  expect(C).toContain("'neutral_words', to_jsonb(security.pdesc_machine_neutral_supported_v1(")
  // validation and the worker are not changed: validation already requires a claim word to be in its own quote; the worker reads no word list
  expect(C).not.toContain("pg_temp.edit_all('security.provider_description_validate_v1")
  expect(worker).not.toMatch(/claim_words|machine_neutral/)
})

test('admitted: the UNSW and Monash sentences with their exact quotes, two supported sentences, and a proposal recorded by the reader', () => {
  for (const l of ['unsw_admitted|true|pdesc-machine-v1|', 'unsw_short_admitted|true|pdesc-machine-v1|', 'monash_admitted|true|pdesc-machine-v1|', 'two_sentences_admitted|true|pdesc-machine-v1|',
    'record_admitted|admitted|machine|pdesc-machine-v1|1|0', 'record_description|true']) expect(expected).toContain(l)
  // the real quotes of the two declined proposals are in the fixture
  expect(scenarios).toContain('It is found in our students, our staff, our alumni and our generous donors.')
  expect(scenarios).toContain('When our first students began their studies at our foundation campus in Clayton in 1961')
  // provenance kept: source address, hash, evidence id, every sentence with its exact quote, the neutral words relied on, the machine actor
  expect(expected).toContain('record_audit|admitted|stored|true|true|true|3|true|true|true|["students", "staff", "alumni"]|true')
  expect(expected).toContain('record_decision_is_machine|machine|pdesc-machine-v1')
})

test('still refused: ranking, rating, outcome, accreditation, award, facility, superlative, finance, visa, availability, campus and figure claims, even with a supported neutral word', () => {
  const refused = {
    ranking: 'refused_word:ranked', ranking_plain: 'refused_word:ranked', rating: 'refused_word:rating', outcome_employment: 'refused_word:employability', outcome_salary: 'refused_word:salaries',
    outcome_employers: 'refused_word:employers', outcome_earnings_figure: 'figure:90,000', accreditation: 'refused_word:accredited', accreditation_noun: 'refused_word:accreditation', award: 'refused_word:awards',
    facilities: 'refused_word:facilities', superlative_best: 'refused_word:best', superlative_leading: 'refused_word:leading', superlative_world_class: 'refused_word:world-class', visa: 'refused_word:visa',
    fees: 'refused_word:fees', scholarships: 'refused_word:scholarships', guaranteed: 'refused_word:guaranteed', campus_beside_students: 'refused_word:campus', partnership: 'refused_word:partnership',
    figure_count: 'figure:400', figure_percentage: 'figure:95', figure_year_out_of_range: 'figure:1500',
  }
  for (const [k, w] of Object.entries(refused)) expect(expected.some((l) => l.startsWith(`${k}|false|machine_text_`) && l.endsWith(`|${w}`)), k).toBe(true)
  expect(expected).toContain('markup|false|machine_text_entity_encoded|entity_encoded:page markup')
  // a neutral word that the quote does not support (absent, another form, negated, not on the page, text is not the sentences, one of two sentences)
  for (const k of ['quote_lacks_word', 'quote_has_other_form', 'quote_negates_word', 'quote_not_on_page', 'text_is_not_the_sentences', 'one_of_two_unsupported', 'word_in_second_sentence_only_unsupported', 'unsw_without_sentences', 'unsw_sentences_null'])
    expect(expected.some((l) => l.startsWith(`${k}|false|machine_text_refused_word`)), k).toBe(true)
  // the two proposals as actually declined still carry other words (campus and a figure; the French list's "unique"): reported, not hidden
  expect(expected).toContain('monash_as_proposed|false|machine_text_refused_word|refused_word:campus')
  expect(expected).toContain('unsw_as_proposed|false|machine_text_refused_word|refused_word:unique')
  // figures are not loosened
  expect(expected).toContain('numbers_not_loosened|0')
  expect(expected).toContain('claim_words_untouched|true')
  expect(expected).toContain('tier4_strict|refused_word:students|clean')
})

test('the setting is the control, and a promotional proposal still waits for a person with the reason on the item', () => {
  for (const l of ['setting_empty|false|machine_text_refused_word|refused_word:students', 'setting_alumni_only_students_refused|false|machine_text_refused_word|refused_word:students', 'setting_alumni_only_alumni_admitted|true|pdesc-machine-v1|',
    'setting|["students", "staff", "alumni"]|list|0|words|Provider descriptions|true|true|true|true']) expect(expected).toContain(l)
  // RETIRED 10 Nov 2026 (migration 20261110210000, sentence-subset recovery): a reading with ONE promotional sentence among clean ones is no longer left whole for a person; the clean sentences are admitted and the promotional one is left out.
  // record_tally, record_declined, waiting_promotional_settle and waiting_promotional are no longer expected; the superseding scenarios are promotional_* in tests/fixtures/pdesc-subset-recovery. The setting stays the control, and a reading that cannot be recovered still waits with the reason.
  for (const n of ['record_tally', 'record_declined', 'waiting_promotional_settle', 'waiting_promotional']) {
    expect(expected.some((l) => l.startsWith(n + '|')), n).toBe(false)
    expect(scenarios).toContain("'RETIRED_" + n + "|'")
  }
})

test('re-evaluation: a proposal declined for a neutral word is admitted by the existing settlement of waiting items, with no row written by the migration', () => {
  for (const l of ['waiting_declined|1|(none)|refused_word:students', 'settle_within_the_hour|{"on": true, "errors": 0, "admitted": 0, "left_for_a_person": 0}|1',
    'settle_after_the_hour|{"on": true, "errors": 0, "admitted": 1, "left_for_a_person": 0}|0|1|true', 'settle_audit|declined:-,admitted:true', 'settle_step_is_the_scheduled_path|true|true']) expect(expected).toContain(l)
  // the migration writes no row of Layer 4, reads, admissions, descriptions or jobs: the only insert is the setting
  expect([...C.matchAll(/^\s*insert into ([a-z_.]+)/gm)].map((m) => m[1])).toEqual(['pipeline.platform_toolset_settings'])
  expect(C).not.toMatch(/\bupdate\s+(pipeline|catalogue)\./i)
  for (const t of ['no Layer 4 item, read, admission, description or job changed', 'earlier: the']) expect(run, t).toContain(t)
})

test('the harness mirrors production, runs in the workflow, and every printed scenario is in the expected output', () => {
  expect(run).toContain('tests/fixtures/pdesc-machine/run.sh')
  expect(run).toContain('tests/fixtures/pdesc-machine/scenarios.sql')
  expect(workflow).toContain('bash tests/fixtures/pdesc-claim-context/run.sh')
  expect(workflow).toContain('tests/uat/cf-247-s504-pdesc-claim-word-context-contract.spec.mjs')
  expect(expected.length).toBeGreaterThan(50)
  for (const m of scenarios.matchAll(/select '([a-z0-9_]+)\|'/g)) expect(expected.some((l) => l.startsWith(m[1] + '|')), m[1]).toBe(true)
})
