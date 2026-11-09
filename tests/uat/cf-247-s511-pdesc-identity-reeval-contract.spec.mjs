// Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): a provider held for identity by another reader than the one running is offered to the running reader once more on the same stored page, in the picker and in the lease; the running reader is one stored row kept by the worker's own stamp (O(1), newest stamp wins); the evidence signature is not changed, so every other failure keeps its recovery memory; a hold of the running reader, another rule, a rejection, an empty setting or a manual lock stays parked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109185000_cf247_pdesc_identity_reeval.sql'
const M = fs.readFileSync(MIG, 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)
const run = fs.readFileSync('tests/fixtures/pdesc-identity-reeval/run.sh', 'utf8')
const scenarios = fs.readFileSync('tests/fixtures/pdesc-identity-reeval/scenarios.sql', 'utf8')
const expected = fs.readFileSync('tests/fixtures/pdesc-identity-reeval/expected.txt', 'utf8').split('\n').filter(Boolean)
const workflow = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const res = (label) => { const l = expected.find((x) => x.startsWith(label + '|')); expect(l, label).toBeTruthy(); return l.slice(label.length + 1) }

test('housekeeping: Replaces and Retires lines, comments, revokes, a table comment, nothing dropped, no job, the consumer API is not edited', () => {
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(C).not.toMatch(/\bdrop\s+(function|table|index|trigger)|\bdelete\s+from|\btruncate\b/i)
  expect(C).not.toMatch(/cron\.schedule|cron\.alter_job/i)
  expect(C).toContain("comment on table pipeline.pdesc_reader_state is '")
  expect(C).toContain("comment on function security.pdesc_reader_behaviour_v1() is '")
  expect(C).toContain("comment on function security.pdesc_reader_stamp_v1() is '")
  expect(C).toContain('revoke all on function security.pdesc_reader_behaviour_v1() from public, anon, authenticated;')
  expect(C).toContain('revoke all on pipeline.pdesc_reader_state from public, anon, authenticated;')
  const edits = [...C.matchAll(/pg_temp\.edit_all\('([^']+)'/g)].map((m) => m[1])
  expect(edits).toEqual(['security.provider_description_selection_v1(jsonb)', 'public.svc_provider_description_next(integer)'])
  expect(edits.filter((e) => /website_|zoho_|^api\./.test(e))).toEqual([])
  expect([...C.matchAll(/create or replace function ([a-z_]+\.[a-z_0-9]+)/g)].map((m) => m[1]).filter((n) => !n.startsWith('pg_temp.'))).toEqual(['security.pdesc_reader_stamp_v1', 'security.pdesc_reader_behaviour_v1'])
  // the migration writes no data of the pipeline: its only insert is the settings row and the reader-state seed (the lease's own held-update is the existing statement being edited)
  expect(C).not.toMatch(/(insert\s+into|update|delete\s+from)\s+(pipeline\.layer4_|catalogue\.providers|pipeline\.ops_remedy)/i)
  expect(C).not.toMatch(/insert\s+into\s+pipeline\.provider_description_reads/i)
})

test('the edits are guarded by the body md5 (live picker; the lease as 20261109182000 leaves it) and the recorded after md5, and the migration refuses until 20261109182000 is applied', () => {
  const hdr = [...M.matchAll(/^--   ([a-z0-9_.]+\([^)]*\)) ([0-9a-f]{32}) -> ([0-9a-f]{32})/gm)].map((m) => [m[1], m[2], m[3]])
  expect(hdr.map((h) => h[0])).toEqual(['security.provider_description_selection_v1(jsonb)', 'public.svc_provider_description_next(integer)'])
  expect(hdr.map((h) => h[1])).toEqual(['c8dd7882a5a6c5b174a829972d475d40', '90275ff3bc7da9989c2a3430b16cb94f'])
  for (const [sig, before, after] of hdr) expect(C, sig).toContain(`'${sig}', '${before}', '${after}'`)
  expect(C).toContain('(apply 20261109182000 first)')
  expect(C).toContain('differs from the definition this change edits')
  expect(C).toContain('must apply exactly once')
  for (const t of ['the changed functions differ from the edited ones', 'the migration changed setting values', 'the second run was not a no-op', 'case "$DB" in g_*)', 'apply 20261109182000 first', 'the evidence signature changed']) expect(run).toContain(t)
})

test('G2: the identity rules are a setting with label, range, unit, section and used_by; no rule list is written into a function', () => {
  expect(C).toMatch(/\('pipeline', 'pdesc\.identity_reeval_rules', 'Provider descriptions: [^']+',/)
  expect(C).toContain(`'list', '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]'::jsonb, 0, null, 'rules', 1023, 'Provider descriptions', 'security.provider_description_selection_v1',`)
  expect(C).toContain('on conflict (toolset_key, key) do nothing;')
  expect(C).toContain("security.toolset_setting('pipeline','pdesc.identity_reeval_rules')")
  expect(C).toContain("security.toolset_setting('pipeline', 'pdesc.identity_reeval_rules')")
  const fns = C.slice(C.indexOf("select pg_temp.edit_all('security.provider_description_selection_v1"))
  expect(fns.match(/'provider_name_(conflict|not_proved)'|'provider_subunit_source'/g) || []).toEqual([])
  expect(res('setting')).toBe('["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]|list|rules|Provider descriptions|true|true')
})

test('the running reader is one stored row (O(1)), kept by the worker\'s own stamp: no scan of the reads, no index on them, no highest-label rule', () => {
  const rb = C.slice(C.indexOf('create or replace function security.pdesc_reader_behaviour_v1()'), C.indexOf("comment on function security.pdesc_reader_behaviour_v1()"))
  expect(rb).toContain('select s.version from pipeline.pdesc_reader_state s where s.singleton')
  expect(rb).not.toMatch(/provider_description_reads|distinct|order by/i)
  expect(C).not.toMatch(/create (unique )?index/i)
  expect(C).toContain('singleton boolean primary key default true check (singleton)')
  // two row triggers: a stamp that is new on an insert, or an update that changes it
  expect(C).toContain("when (new.checks->'identity'->>'reader_behavior_version' is not null) execute function security.pdesc_reader_stamp_v1();")
  expect(C).toMatch(/after update of checks on pipeline\.provider_description_reads for each row\s+when \(new\.checks->'identity'->>'reader_behavior_version' is not null and new\.checks->'identity'->>'reader_behavior_version' is distinct from old\.checks->'identity'->>'reader_behavior_version'\)/)
  expect(res('new_stamp_current')).toBe('provider-description-source-guard-v10')
  expect(res('old_row_touched_unchanged')).toBe('provider-description-source-guard-v10')   // an old row touched again (same stamp) does not make its reader current
  expect(res('prefix_rename_current')).toBe('identity-reader-2027-a')                      // a renamed prefix is picked up
  expect(res('rolled_back_current')).toBe('provider-description-source-guard-v2')         // a worker rolled back makes its reader current again
  expect(res('update_changing_stamp_current')).toBe('provider-description-source-guard-v3')
  expect(res('reader_state_rows')).toBe('1')
})

test('the evidence signature is NOT edited, so the recovery memory of every other failure is kept', () => {
  expect(C).not.toContain('provider_description_signature_v1')
  expect(res('sig_independent_of_reader')).toBe('true')
  // the lease: an identity hold of another reader is leased again; the running reader\'s hold, another kind of failure and a non-identity rule keep their memory
  expect(res('lease_reoffer')).toBe('p2,p5,p6,p8')
  expect(res('lease_blocked')).toBe('p3=held:recovery_knowledge_unchanged_failure,p4=held:recovery_knowledge_unchanged_failure,p7=held:recovery_knowledge_unchanged_failure')
  expect(res('lease_setting_empty')).toBe('p8')
  expect(res('lease_rolled_back_reader')).toBe('p3,p6,p8')
  const nx = C.slice(C.indexOf("select pg_temp.edit_all('public.svc_provider_description_next"))
  // found once per lease, from the latest finished read of each provider, not per row
  expect(nx).toContain('v_reoffer := array(select l.provider_id from (select distinct on (o.provider_id)')
  expect(nx).toContain('r.provider_id = any(v_reoffer)')
  expect(nx).toContain('not (x.provider_id = any(v_reoffer))')
  expect(nx.match(/pdesc_reader_behaviour_v1\(\)/g)).toHaveLength(1)
})

test('positive: a hold made by another reader is offered again by the picker; negative: the running reader\'s hold, other rules, a rejection, an empty setting and a manual lock stay parked', () => {
  expect(res('current_reader')).toBe('provider-description-source-guard-v2')
  for (const r of ['v1_conflict_offered', 'v1_not_proved_offered', 'v1_subunit_offered', 'unstamped_conflict_offered']) expect(res(r), r).toBe('eligible')
  expect(res('no_reader')).toBe('(none)')
  expect(res('v1_only_parked')).toBe('provider-description-source-guard-v1|unchanged_unsuitable_evidence')
  expect(res('v2_conflict_parked')).toBe('unchanged_unsuitable_evidence')
  for (const r of ['v1_verbatim_parked', 'v1_quote_parked', 'v1_not_stated_parked', 'rejected_parked', 'setting_empty_parked', 'judged_again_parked']) expect(res(r), r).toBe('unchanged_unsuitable_evidence')
  expect(res('manual_lock_wins')).toBe('manual_lock')
  expect(res('setting_narrowed')).toBe('eligible|unchanged_unsuitable_evidence')
  expect(C.match(/and not \(r\.state='held' and v_idr \? r\.rule and coalesce\(r\.checks->'identity'->>'reader_behavior_version',''\) is distinct from coalesce\(v_cur,''\)\)/g)).toHaveLength(2)
  expect(C).not.toMatch(/pdesc\.ai_usd_max|pdesc\.firecrawl_reads_max/)
})

test('the harness runs in the workflow and every printed scenario is in the expected output', () => {
  expect(workflow).toContain('bash tests/fixtures/pdesc-identity-reeval/run.sh')
  expect(workflow).toContain('tests/uat/cf-247-s511-pdesc-identity-reeval-contract.spec.mjs')
  const printed = [...scenarios.matchAll(/select '([a-z0-9_]+)\|'/g)].map((m) => m[1])
  for (const p of new Set(printed)) expect(expected.some((e) => e.startsWith(p + '|')), p).toBe(true)
  expect(scenarios).not.toMatch(/\bcommit\b/i)
  expect(res('grants')).toBe('false|false|false|false')
})
