// Guards: F-PDESC (Platform Admin decision 9 Nov 2026, all-provider autonomous description delivery): constrained machine admission (tiers stored, direct, firecrawl, registry_factual) is a separate audited path that is off by default, never calls the human Layer 4 decision, can be withdrawn; the queue is per country and sized from settings; an empty list setting is allowed only where the setting says so (migrations 20261109020000 and 20261109030000)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { listMin, listValid, listError, listPlaceholder, parseList, listShown } from '../../src/lib/settings-list.js'

const M2 = fs.readFileSync('supabase/migrations/20261109020000_cf247_pdesc_machine_admission.sql', 'utf8')
const M3 = fs.readFileSync('supabase/migrations/20261109030000_cf247_pdesc_whole_platform_queue.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C2 = code(M2)
const C3 = code(M3)
const run = fs.readFileSync('tests/fixtures/pdesc-machine/run.sh', 'utf8')
const expected = fs.readFileSync('tests/fixtures/pdesc-machine/expected.txt', 'utf8').split('\n').filter(Boolean)
const scenarios = fs.readFileSync('tests/fixtures/pdesc-machine/scenarios.sql', 'utf8')
const workflow = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const fnBody = (c, name) => { const i = c.indexOf(`create or replace function ${name}(`); expect(i, name).toBeGreaterThan(-1); const j = c.indexOf('end $f$;', i); return c.slice(i, j) }

test('list settings: a minimum number of values from the setting itself; none recorded means one, 0 allows an empty list', () => {
  expect(listMin({ min: null })).toBe(1)
  expect(listMin({})).toBe(1)
  expect(listMin({ min: 0 })).toBe(0)
  expect(listMin({ min: '0' })).toBe(0)
  expect(listMin({ min: 2 })).toBe(2)
  expect(parseList(' AU, NZ ,,CA ')).toEqual(['AU', 'NZ', 'CA'])
  expect(parseList('')).toEqual([])
  expect(listShown(['a', 'b'])).toBe('a, b')
  // the keys list: empty is every provider
  expect(listValid({ min: 0 }, '')).toBe(true)
  expect(listValid({ min: 0 }, ' , ')).toBe(true)
  expect(listValid({ min: 1 }, '')).toBe(false)
  expect(listValid({ min: null }, '')).toBe(false)
  expect(listValid({ min: null }, 'AU')).toBe(true)
  expect(listValid({ min: 2 }, 'AU')).toBe(false)
  expect(listError({ min: null })).toBe('At least one value.')
  expect(listError({ min: 2 })).toBe('At least 2 values.')
  expect(listError({ min: 0 })).toBe('')
  expect(listPlaceholder({ min: 0 })).toBe('Empty means all')
  expect(listPlaceholder({ min: 1 })).toBe('')
  const ui = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')
  expect(ui).toContain("from'./lib/settings-list.js'")
  expect(ui).toContain('listValid(s,v)')
  expect(ui).not.toContain("'At least one value.'")
})

test('settings: the list branch of the governed write honours min_value as a minimum count; the two reader lists may be empty, the countries may not', () => {
  expect(C2).toContain("if v_set.min_value is not null and jsonb_array_length(v_val) < v_set.min_value then raise exception 'give at least % value(s)', v_set.min_value; end if;")
  expect(C2).toMatch(/update pipeline\.platform_toolset_settings set min_value = 1 where toolset_key = 'pipeline' and key = 'pdesc\.countries'/)
  expect(C2).toMatch(/update pipeline\.platform_toolset_settings set min_value = 0,[\s\S]{0,400}key = 'pdesc\.provider_keys'/)
  expect(C2).toMatch(/update pipeline\.platform_toolset_settings set min_value = 0,[\s\S]{0,400}key = 'pdesc\.provider_types'/)
  expect(C2).not.toContain("key = 'pdesc.refused_path_words'")
  expect(C3).not.toContain('refused_path_words')
  for (const l of ['set_empty_keys_now|[]', 'set_empty_types_now|[]', 'set_empty_countries|give at least 1 value(s)', 'set_not_a_person|Platform Admin required']) expect(expected).toContain(l)
})

test('scope: an empty type list is every type and a provider with no type (all 1,130 Canadian providers) is "unclassified"; one function decides it for the reader and the funnel', () => {
  expect(C2).toContain("coalesce(nullif(btrim(p_code), ''), 'unclassified')")
  expect(C2).toContain('security.pdesc_type_in_scope_v1(t.code)')
  expect((C2.match(/pdesc_type_in_scope_v1\(t\.code\)/g) || []).length).toBe(2)
  for (const l of ['scope_default|true|false', 'scope_unclassified|false|true', 'scope_both|true|true', 'scope_empty_all|true|true|true|true', 'scope_empty_keys_all|17|17']) expect(expected).toContain(l)
})

test('machine admission is off by default; every number is a setting; the ceilings are not enlarged', () => {
  for (const k of ['machine_admit_on', 'registry_factual_on', 'machine_numbers_allowed']) expect(M2).toMatch(new RegExp(`'pdesc\\.${k}',[\\s\\S]{0,1800}?'number', '0'::jsonb, 0, 1,`))
  expect(C2).toContain("security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1")
  expect(C3).toContain("security.pipeline_num_v1('pdesc.machine_admit_on',0)")
  for (const k of ['ai_usd_max', 'firecrawl_reads_max', 'pending_max']) { expect(C2).not.toMatch(new RegExp(`(insert into|update)[^;]*'pdesc\\.${k}'`)); expect(C3).not.toMatch(new RegExp(`(insert into|update)[^;]*'pdesc\\.${k}'`)) }
  expect(run).toContain('pdesc.machine_admit_on, pdesc.registry_factual_on and pdesc.machine_numbers_allowed are 0')
  for (const k of ['target_hours', 'queue_cap', 'dispatch_max', 'backlog_hours', 'rate_window_hours', 'concurrency_max', 'read_cost_floor_usd', 'registry_min_facts', 'registry_per_run', 'machine_settle_per_run']) expect(M2).toContain(`'pdesc.${k}'`)
})

test('admission path: the system automation account, a machine rule on the decision, never the human decision procedure, one description written in two places only', () => {
  expect(C2).toContain("'c0ffee00-0000-4000-8000-000000000150'")
  expect(C2).not.toMatch(/layer4_review_decide_impl|layer4_provider_description_apply_impl|admin_layer4_decide|layer4_decide\(/)
  expect(C3).not.toMatch(/layer4_review_decide_impl|layer4_provider_description_apply_impl|admin_layer4_decide|layer4_decide\(/)
  const writes = [...C2.matchAll(/update catalogue\.providers set description/g)].length
  expect(writes).toBe(2) // the admission and its withdrawal
  expect(C3).not.toMatch(/update catalogue\.providers/)
  const admit = fnBody(C2, 'security.provider_description_machine_admit_v1')
  expect(admit).toContain("'machine_rule'")
  expect(admit).toContain("'actor_kind', 'machine'")
  expect(admit).toContain('Not a person')
  expect(admit).toContain('provider_description_machine_gate_v1')
  expect(admit).toContain('website_v2_provider(')
  expect(expected).toContain('on_decision_actor|c0ffee00-0000-4000-8000-000000000150|pdesc-machine-v1|machine|true')
})

test('objective rule: lock, human rejection, description held, identity finding, withdrawn, unpublished and the text rule each stop admission with a named reason', () => {
  const gate = fnBody(C2, 'security.provider_description_machine_gate_v1')
  for (const r of ['machine_admission_off', 'provider_not_live', 'out_of_scope', 'manual_lock', 'description_already_held', 'prior_human_rejection', 'withdrawn_awaiting_review', "'identity_' || v_find", 'no_description', 'machine_text_']) expect(gate, r).toContain(r)
  for (const l of ['gate_off|machine_admission_off', 'gate_lock|manual_lock', 'gate_has_description|description_already_held', 'gate_human_rejection|prior_human_rejection', 'gate_identity_finding|identity_identity_unconfirmed',
    'gate_unpublished|provider_not_live', 'gate_clean|pdesc-machine-v1', 'withdrawn_gate|withdrawn_awaiting_review', 'year_ok|clean']) expect(expected).toContain(l)
  expect(expected.some((l) => l.startsWith('decline_campus|held|machine_declined_machine_text_refused_word'))).toBe(true)
  expect(expected.some((l) => l.startsWith('decline_figure|held|machine_declined_machine_text_figure'))).toBe(true)
  // a declined proposal is kept for a person, with the reason, and the existing items are settled or left, never discarded
  expect(expected).toContain('decline_proposal_kept|true')
  expect(expected.some((l) => l.startsWith('settle_9|1|(none)|Machine rule pdesc-machine-v1 did not admit this'))).toBe(true)
  expect(expected).toContain('settle|{"on": true, "errors": 0, "admitted": 1, "left_for_a_person": 1}')
})

test('tier registry_factual: only verified register, provider record and active course facts; thin facts give insufficient_verified_facts; Canada with no type works', () => {
  const profile = fnBody(C2, 'security.provider_description_registry_profile_v1')
  expect(profile).toContain('insufficient_verified_facts')
  expect(profile).not.toMatch(/website|net\.http|firecrawl|openrouter/i)
  for (const t of ["'cricos'", "'nzqa'", "'ircc_dli'"]) expect(C2).toContain(t)
  expect(expected.some((l) => l.startsWith('reg_profile|true|registry_factual|Aurora Maritime University is a university in Melbourne, Victoria, Australia.'))).toBe(true)
  for (const l of ['reg_thin|false|insufficient_verified_facts|2 verified fact(s) held (register, type); 3 needed for a useful, truthful profile.',
    'reg_no_wording|There is no profile wording for register scheme fixture_ca.', 'reg_no_listing|The provider has no active register listing with stored evidence.', 'tier_off|{"on": false}', 'tier_off_registry_switch|{"on": false}',
    'tier_again|{"on": true, "held": 0, "errors": 0, "admitted": 0}']) expect(expected).toContain(l)
  expect(expected.some((l) => l.startsWith('reg_ca_untyped_min2|true|Maple Snow University is located in Toronto, Ontario, Canada.'))).toBe(true)
  // a "campus" style junk city is not stated as a place
  expect(expected.some((l) => l.startsWith('reg_junk_city|true|Maple Snow University is located in Ontario, Canada.'))).toBe(true)
  // the register's own fixed wording ("... for Overseas Students") is not treated as a claim, so Australian register profiles can be admitted
  expect(expected.some((l) => l.startsWith('tier_admitted|No Source University is a university in Melbourne'))).toBe(true)
  expect(expected).toContain('tier_audit|registry_factual|pdesc-machine-v1|admitted|true|true')
})

test('withdrawal: Platform Admin or release owner only, a reason, restores the earlier text unless a person changed it, keeps the audit, holds the provider for a person', () => {
  const w = fnBody(C2, 'security.provider_description_machine_withdraw_v1')
  expect(w).toContain('coalesce(security.current_role_rank(), 0) < 6')
  expect(w).toContain('give a reason')
  expect(w).toContain('description_changed_since_admission')
  expect(w).toContain("'pdesc_machine_withdraw'")
  for (const l of ['withdraw|true|null', 'withdraw_again|no_live_machine_admission', 'withdraw_person_edit|description_changed_since_admission|A person rewrote this description by hand.', 'withdraw_no_reason|give a reason (kept in the log)', 'tier_withdraw|true|(none)', 'parity_withdrawn|null|0']) expect(expected).toContain(l)
})

test('queues: one bounded queue a country sized from what is left and the observed rate, fair rotation, concurrency and spend bounds, dispatch sized from the due reads', () => {
  for (const l of ['tp_shape|15|AU=13,CA=1,NZ=1|15|1', 'queued_by_country|AU=12,CA=1,NZ=1', 'enqueue_again|0', 'tp_spread|12|2|18', 'tp_cap|1', 'enqueue_off|2',
    'lease_concurrency|1', 'lease_concurrency_full|review_full', 'lease_spend|ai_spend_committed', 'lease_fair|NZ', 'lease_off_waiting_cap|review_full',
    'fire_on_7_max2|7|2|2', 'fire_on_7_max3|7|3|3', 'fire_on_2_max3|2|1|1', 'fire_off_7_max3|7|1|1', 'fire_second|0']) expect(expected).toContain(l)
  const tp = fnBody(C2, 'security.provider_description_throughput_v1')
  expect(tp).toContain('observed_per_hour')
  expect(tp).toContain('remaining_by_country')
  expect(C3).toContain("security.pipeline_num_v1('pdesc.concurrency_max', 12)")
  expect(C3).toContain("security.pipeline_num_v1('pdesc.dispatch_max',3)")
  expect(C3).toContain("security.pipeline_num_v1('pdesc.queue_cap',60)")
  // the lease keeps its claim and recovery rules: only the cap and the order are edited
  expect(C3).not.toMatch(/leased_until\s*=\s*now\(\)\s*\+/)
  // off: the reader is as before
  for (const l of ['off_proposal_waits|1|(none)|0', 'off_selection_size_limit|cohort size must be between 1 and 10', 'off_fire_sends_one|1']) expect(expected).toContain(l)
})

test('consumer parity: the existing publication check reads the Website and Zoho back; the report counts mismatches; no consumer API function is created or replaced', () => {
  for (const l of ['parity_after|true|true|true|true', 'parity_website_text|true', 'report_parity|1|1|1|0|0', 'report_mismatch|1']) expect(expected).toContain(l)
  const names = [...(C2 + C3).matchAll(/create or replace function ([a-z_]+\.[a-z_0-9]+)/g)].map((m) => m[1]).filter((n) => !n.startsWith('pg_temp.'))
  expect(names.length).toBeGreaterThan(8)
  for (const n of names) expect(n.startsWith('security.'), n).toBe(true)
  const edits = [...(C2 + C3).matchAll(/pg_temp\.edit_all\('([^']+)'/g)].map((m) => m[1])
  expect(edits.filter((e) => /website_|zoho_|^api\./.test(e))).toEqual([])
})

test('the edits are guarded by live md5 and the harness checks everything else is unchanged, then applies each migration twice', () => {
  for (const [sig, before] of [['security.provider_description_scope_v1(uuid)', '3f16959316449464576f5d77a951460a'], ['public.admin_provider_description_funnel_v1()', 'b8ba600e9d7a67e9c493f062bfda0b99'], ['public.admin_toolsets_write(text,jsonb)', '1e511b25277897b870d185c2ea727ae0']])
    expect(M2).toMatch(new RegExp(`--   ${sig.replace(/[()]/g, '\\$&')} ${before} -> [0-9a-f]{32}`))
  for (const [sig, before] of [['security.provider_description_selection_v1(jsonb)', 'eaebe3d0a6c188f0b4f6b6c3fcf659ba'], ['security.provider_description_enqueue_v1()', '0a1897bb7f56697a9f01d4ec3e8befc0'], ['public.svc_provider_description_next(integer)', '559407dc479753698b858231b2e7eb93'],
    ['public.svc_provider_description_record(jsonb)', 'd95f0bafc894b662468a309254544444'], ['security.provider_description_fire_v1()', 'b334fbefe8a7fb2b8cfd2feda570a616']])
    expect(M3).toMatch(new RegExp(`--   ${sig.replace(/[()]/g, '\\$&')} ${before} -> [0-9a-f]{32}`))
  expect(M2 + M3).not.toContain('@@AFTER@@')
  expect(C2.match(/pg_temp\.edit_all\('/g)?.length).toBe(3)
  expect(C3.match(/pg_temp\.edit_all\('/g)?.length).toBe(5)
  expect(C2).toContain('must apply exactly once')
  for (const t of ['the changed functions differ from the edited ones', 'the migration changed setting values', 'the second run was not a no-op', 'case "$DB" in g_*)', 'the earlier self-driving scenarios give the same result']) expect(run, t).toContain(t)
  expect(fs.readFileSync('tests/fixtures/pdesc-machine/schema.sql', 'utf8')).toMatch(/Scratch database only/)
  expect(workflow).toContain('bash tests/fixtures/pdesc-machine/run.sh')
  expect(workflow).toContain('tests/uat/cf-247-s501-pdesc-machine-admission-contract.spec.mjs')
  expect(expected.length).toBeGreaterThan(90)
  // every printed result in the scenarios is in the expected output
  for (const m of scenarios.matchAll(/select '([a-z0-9_]+)\|'/g)) expect(expected.some((l) => l.startsWith(m[1] + '|')), m[1]).toBe(true)
})
