// Guards: Autonomous AI operations mandate 3 Nov 2026 (15:37 §8 and §9; acceptance mandate 15:52 §4 NEWGEN decision and §12), workstream G:
// provider website and identity validation is a permanent scheduled check that records findings and opens evidence-backed investigations but
// never corrects a website; a correction is proposed only on the platform's own verified site check and goes to the Platform Admin; lifecycle
// transitions (deregistered, closed, merged, temporarily unavailable, country retired) need authoritative evidence (never AI inference alone),
// produce a reviewed cascade plan, execute only on a Platform Admin decision with lifecycle.cascade_on (ships off), go through the existing
// archive and hide (G3 untouched), are verified downstream and are reversible; nothing is deleted. The behaviour runs on isolated fixtures by
// tests/fixtures/ops-provider-lifecycle/run.sh (scratch PostgreSQL; the live v2.15.426 definitions loaded from their live text and checked against
// the live md5s; workstream A's contract stubbed by its exact names; the migration applied twice; eleven passes asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104060000_cf247_ops_provider_identity_lifecycle.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-provider-lifecycle'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf('\n$$;', a)) }
const pasteA = fs.readFileSync('docs/paste/PASTE-20261104-newgen-03871f-a-website-check.sql', 'utf8')
const pasteB = fs.readFileSync('docs/paste/PASTE-20261104-newgen-03871f-b-website-correction.sql', 'utf8')

test('lands after workstream A; edits only the onboarding tick from its live md5; the fixture loads the same live text', () => {
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null then raise exception 'workstream A (20261104010000) has not landed")
  expect(m).toMatch(/security\.provider_onboarding_tick_v1\(\) +181fc3dd2d78930c32e70cc24fb0adbd -> [0-9a-f]{32}/)
  expect([...m.matchAll(/select pg_temp\.edit_once\('([^']+)'/g)].map(x => x[1])).toEqual(['security.provider_onboarding_tick_v1()'])
  for (const [sig, md5] of [['security.website_refusal_v1(text)', '2bf77cfa3474619d71b33c3e7877ae0d'], ['security.site_host_v1(text)', '04938c208412f46735c7a3f99348612c'],
    ['security.provider_archive_apply_v1(uuid,text,text,uuid,boolean)', '5a2af698d6de7e5e3bf5ef3a860236c8'], ['security.provider_restore_v1(uuid,text,uuid,boolean)', 'a5e479c7ebc5060f710da1ffb95dd60d']]) {
    expect(m).toContain(`('${sig}', '${md5}')`)
    expect(run).toContain(`["${sig}"]=${md5}`)
  }
  expect(run).toContain('["security.provider_onboarding_tick_v1()"]=181fc3dd2d78930c32e70cc24fb0adbd')
  expect(fs.readFileSync(`${FX}/stub-ops-contract.sql`, 'utf8')).toContain('create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb)')
})

test('the check records and reports only: four switches on, the paid candidate check and the cascade off', () => {
  for (const k of ['identity.check_on', 'identity.issue_on', 'identity.investigate_on', 'lifecycle.propose_on']) expect(m).toMatch(new RegExp(`'${k.replace('.', '\\.')}'[\\s\\S]{0,600}?'number', '1'::jsonb`))
  for (const k of ['identity.candidate_check_on', 'lifecycle.cascade_on']) expect(m).toMatch(new RegExp(`'${k.replace('.', '\\.')}'[\\s\\S]{0,700}?'number', '0'::jsonb`))
  expect(m).toContain("perform cron.schedule('provider-identity-check', '16 * * * *', $c$select security.provider_identity_check_v1()$c$);")
  const check = fn('security.provider_identity_check_v1')
  for (const code of ['website_malformed', 'identity_unconfirmed', 'domain_shared', 'redirected_or_parked', 'register_changed']) expect(check).toContain(`'${code}'`)
  expect(check).not.toMatch(/update catalogue\.providers/)
  expect(check).toContain("'fingerprint', v_fp")
})

test('registrable domains keep state school and provincial zones, so schools do not "share" vic.edu.au', () => {
  const d = fn('security.provider_identity_domain_v1')
  expect(d).toContain("'\\.(vic|nsw|qld|wa|sa|tas|act|nt)\\.(edu|gov)\\.au$'")
  expect(d).toContain("'\\.(ab|bc|mb|nb|nl|ns|nt|nu|on|pe|qc|sk|yk)\\.ca$'")
  expect(fixtures).toContain("'state school and provincial zones are not one shared domain'")
})

test('NEWGEN: no website derived from an email; blocked by evidence until the platform verifies a candidate; never applied by the platform', () => {
  const inv = fn('security.provider_identity_investigate_v1')
  expect(inv).not.toMatch(/split_part\([^)]*email/)
  expect(inv).toContain("set state = 'blocked_evidence'")
  expect(inv).toContain("c.verdict = 'verified'")
  expect(inv).not.toMatch(/admin_provider_website_set|provider_website_change_apply_v1|action\) *values *\([^)]*'change'/)
  expect(fn('security.provider_identity_evidence_v1')).toContain('a contact email domain is not evidence of a website; a site is never derived from it')
  expect(fn('public.admin_provider_identity')).toContain("say where the candidate comes from (a register entry or a first-party page), not how it was guessed")
  for (const s of ['NEWGEN blocked_evidence by name', 'no candidate derived from the email address', 'likely is not verified', 'never applied by the platform']) expect(fixtures).toContain(s)
  // the paste files: A asks for a check only; B corrects only on CRICOS 03871F found on newgen.edu.au by that check, through the existing path
  expect(pasteA).toContain("values (v_pid, 'https://newgen.edu.au/', 'check',")
  expect(pasteA).not.toMatch(/update catalogue\.providers|admin_provider_website_set/)
  expect(pasteB).toContain("x.verdict = 'verified' and coalesce((x.result->>'cricos_on_site')::boolean, false) and upper(coalesce(x.result->>'cricos_code', '')) = '03871F'")
  expect(pasteB).toContain('v_note := security.provider_website_change_apply_v1(v_id);')
  expect(pasteB).toContain("<> 'cf7fbf191d127d896c34af965163ea30'")
})

test('lifecycle: authoritative evidence only, a reviewed plan over every relationship, Platform Admin decision, cascade switch, verified and reversible', () => {
  expect(fn('security.provider_lifecycle_evidence_ok_v1')).toContain("e->>'kind' in ('register', 'first_party', 'admin_record')")
  const plan = fn('security.provider_lifecycle_plan_v1')
  for (const k of ['providers', 'consumer_projection', 'courses', 'scholarships', 'entry_requirements', 'source_mappings', 'tasks', 'onboarding', 'enrichment_plans',
    'layer4_items', 'campuses', 'provider_contacts', 'layer1_references', 'aer_records', 'layer23_work', 'search_projection', 'identity_investigations']) expect(plan).toContain(`'key', '${k}'`)
  const exec = fn('security.provider_lifecycle_execute_v1')
  expect(exec).toContain("if security.pipeline_num_v1('lifecycle.cascade_on', 0) < 1 then raise exception")
  expect(exec).toContain("if e.state <> 'approved' then raise exception")
  expect(exec).toContain('security.provider_archive_apply_v1(v_p,')
  expect(exec).not.toMatch(/\bdelete\s+from\b/i)
  expect(exec).not.toMatch(/website_v2_|zoho_|\bapi\./)
  expect(fn('security.provider_lifecycle_reverse_v1')).toContain('security.provider_restore_v1(')
  expect(fn('public.admin_provider_lifecycle')).toContain("if v_rank < 6 then raise exception 'Platform Admin required'")
  expect(fn('security.provider_lifecycle_held_v1')).toContain("e.transition = 'temporarily_unavailable' and e.state = 'executed'")
  for (const s of ['AI-only evidence refused', 'cascade_on 0 holds', 'nothing deleted', 'not retired, still published', 'restored as it was', 'both restored',
    'a reversed decision is not proposed again from the same evidence', 'verified and recorded by the job']) expect(fixtures).toContain(s)
})

test('remedies: only the non-destructive ones are automatic; correction and cascade are the Platform Admin\'s', () => {
  expect(m).toMatch(/\('provider_identity_investigate', '\{[^\n]*"authority": "auto"/)
  expect(m).toMatch(/\('provider_onboarding_stop_invalid_website', '\{[^\n]*"authority": "auto"/)
  expect(m).toMatch(/\('provider_lifecycle_plan', '\{[^\n]*"authority": "auto"/)
  expect(m).toMatch(/\('provider_website_correction', '\{[^\n]*"authority": "admin"/)
  expect(m).toMatch(/\('provider_lifecycle_cascade', '\{[^\n]*"authority": "admin"/)
  expect(m).not.toMatch(/\('provider_website_correction', '\{[^\n]*"action_fn"/)
  expect(run).toContain('all ops provider identity and lifecycle fixtures passed')
})
