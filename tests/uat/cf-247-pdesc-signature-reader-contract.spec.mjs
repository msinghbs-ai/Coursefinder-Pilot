// Guards: Platform Admin 9-10 Nov 2026 on-demand provider descriptions – identity fix must be able to reach the AI step
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261110090000_cf247_pdesc_signature_reader_version.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')   // the statements, without the comments
const HARNESS = fs.readFileSync('tests/fixtures/pdesc-signature-reader/run.sh', 'utf8')
const SCEN = fs.readFileSync('tests/fixtures/pdesc-signature-reader/scenarios.sql', 'utf8')
const EXPECTED = fs.readFileSync('tests/fixtures/pdesc-signature-reader/expected.txt', 'utf8')
const EXPECTED_BEFORE = fs.readFileSync('tests/fixtures/pdesc-signature-reader/expected-before.txt', 'utf8')
const HELD = fs.readFileSync('supabase/held/pdesc_signature_reader_forward_recovery.sql', 'utf8')
const WF = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const REEVAL = fs.readFileSync('supabase/migrations/20261109185000_cf247_pdesc_identity_reeval.sql', 'utf8')
const BEFORE = 'b48bbd5b345f2e7b9a1fc6df9958163b'
const AFTER = '2002daebe8768dc9504b8c53131472e0'

test('the migration names what it replaces and retires, records the live md5 before and after, and edits one function only', () => {
  expect(MIG).toMatch(/^-- Replaces: .*security\.provider_description_signature_v1/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain(`security.provider_description_signature_v1(text,text,text) ${BEFORE} -> ${AFTER}`)
  expect(CODE.match(/pg_temp\.edit_all\('/g)).toHaveLength(1)
  expect(CODE).toContain(`edit_all('security.provider_description_signature_v1(text,text,text)', '${BEFORE}', '${AFTER}'`)
  // the callers are named and none is edited: the recorder and the checkers keep one signature
  for (const caller of ['provider_description_learning_trg_v1', 'svc_provider_description_reserve_v1', 'svc_provider_description_next', 'provider_description_selection_v1'])
    expect(MIG, caller).toContain(caller)
  expect(CODE).not.toMatch(/create or replace function (?!pg_temp)/i)
})

test('it refuses, and changes nothing, when the live function is not the one it was written against, and is a no-op the second time', () => {
  expect(CODE).toContain("raise exception 'live % differs from the definition this change edits")
  expect(CODE).toContain("return p_sig || ': already applied'")
  expect(CODE).toContain("raise exception '% after the edit has body md5 %, expected %'")
  expect(CODE).toContain("raise exception 'required % is missing (apply 20261109185000 first)'")
  expect(HARNESS).toContain('is refused by the migration and by the forward recovery (nothing applied)')
  expect(HARNESS).toContain('applied again: no change')
})

test('the signature carries the running reader, from the one-row reader state, and adds nothing when there is no reader', () => {
  // the edit appends the reader to the end of the signature expression, and only there
  expect(CODE).toContain("pdesc.superlatives')),''))$old$")
  expect(CODE).toContain("pdesc.superlatives')),'')||coalesce('|'||security.pdesc_reader_behaviour_v1(),''))$new$")
  // the reader function is the one 20261109185000 made: one primary-key row, never the reads
  expect(REEVAL).toContain('select s.version from pipeline.pdesc_reader_state s where s.singleton')
  expect(HARNESS).toContain('never reads the reads')
  expect(SCEN).toContain("'no_reader_signature_is_legacy|'")
})

test('no operational value, setting, job, table or trigger is added, and nothing is dropped or deleted (G1, G2)', () => {
  expect(CODE).not.toMatch(/\b(insert into|delete from|drop |truncate|alter table|create table|create trigger|create index|cron\.schedule)\b/i)
  expect(CODE).not.toMatch(/platform_toolset_settings/)
  expect(CODE.replace(/apply 20261109185000 first/, '').replace(/chr\(13\)/g, '')).not.toMatch(/[^\w$'.](\d+\.\d+|\d{2,})[^\w$'.]/)   // no number in the statements (the migration number in a message and the carriage-return code of the line-ending fix are names, not values)
  expect(MIG).toContain('No operational number is written into code (G2) and no setting or job is added (G1).')
  expect(MIG).toContain('Consumer API (G3): not touched')
  expect(HARNESS).toContain('no other function, setting, table, column, trigger, index, recorded outcome, read, Layer 4 item or job added or changed')
})

test('the harness proves the fault, then the fix: a failure under reader v2 no longer blocks v3, a failure under v3 still blocks v3, and the other gates stand', () => {
  const lines = (s) => new Set(s.split('\n').filter(Boolean))
  const before = lines(EXPECTED_BEFORE), after = lines(EXPECTED)
  // the live fault (10 Nov 2026): the earlier reader's failure refuses the reservation of the current reader
  expect(before.has('v2_failure_blocks_v3|recovery_knowledge_unchanged_failure')).toBe(true)
  expect(after.has('v2_failure_blocks_v3|ok')).toBe(true)
  // a failure recorded under the current reader still blocks an unchanged retry; a later reader may try once
  expect(after.has('v3_failure_blocks_v3|recovery_knowledge_unchanged_failure')).toBe(true)
  expect(after.has('v3_failure_blocks_v4|ok')).toBe(true)
  expect(after.has('v2_failure_blocks_v2|recovery_knowledge_unchanged_failure')).toBe(true)
  // the picker and the lease use the same signature as the recorder
  expect(after.has('picker_v2_failure_under_v3|eligible')).toBe(true)
  expect(after.has('lease_v2_failure_under_v3|p10,p9')).toBe(true)
  expect(after.has('recorded_under_the_reader_that_wrote_it|true')).toBe(true)
  // rejected evidence and the AI ceiling are not weakened; no reader on record is the earlier signature
  expect(after.has('rejected_evidence_still_refused_v3|unchanged_rejected_evidence')).toBe(true)
  expect(after.has('ai_ceiling_still_applies|ai_ceiling')).toBe(true)
  expect(after.has('no_reader_signature_is_legacy|true')).toBe(true)
  // only the reader-dependent answers differ between before and after
  const changed = [...after].filter((l) => !before.has(l)).map((l) => l.split('|')[0]).sort()
  expect(changed).toEqual(['ai_ceiling_still_applies', 'ceiling_restored_reserve', 'lease_v2_failure_under_v3', 'no_reader_failure_blocks_v1', 'not_recorded_under_the_old_reader', 'picker_v2_failure_under_v3', 'sig_other_reader_differs', 'v2_failure_blocks_v3', 'v3_failure_blocks_v4'])
})

test('the forward recovery restores the earlier body byte for byte, guarded by the md5 of what is live', () => {
  expect(HELD).toContain(BEFORE)
  expect(HELD).toContain(AFTER)
  expect(HELD.match(/CREATE OR REPLACE FUNCTION/g)).toHaveLength(1)
  expect(HELD).toContain('differs from both texts this recovery knows')
  const body = HELD.slice(HELD.indexOf('AS $body$') + 'AS $body$'.length, HELD.indexOf('$body$;'))
  // the restored text is the text the migration replaces: the migration's own edit turns it into the new text
  expect(body.startsWith('\n select md5(coalesce(p_hash')).toBe(true)
  expect(body.endsWith("pdesc.superlatives')),''))\n")).toBe(true)
  expect(body.includes('pdesc_reader_behaviour_v1')).toBe(false)
  expect(HARNESS).toContain('restores body md5 $BEFORE_MD5 byte for byte')
})

test('the harness is wired into the provider-description workflow and the spec runs there', () => {
  expect(WF).toContain('bash tests/fixtures/pdesc-signature-reader/run.sh')
  expect(WF).toContain('tests/uat/cf-247-pdesc-signature-reader-contract.spec.mjs')
  expect(HARNESS).toMatch(/^# Guards: Platform Admin 9-10 Nov 2026 on-demand provider descriptions/m)
  expect(SCEN).toMatch(/^-- Guards: Platform Admin 9-10 Nov 2026 on-demand provider descriptions/m)
})
