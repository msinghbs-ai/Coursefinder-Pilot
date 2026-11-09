// Guards: F-PDESC P0 (Platform Admin directive, 9 Nov 2026: unique, source-backed university descriptions; Operating Model Consolidation 10 Nov 2026: one switch, no new threshold settings): an admitted register-fact profile stays eligible for source-backed enrichment only while pdesc.registry_upgrade_on is 1 (created OFF), a lock, rejection, withdrawal or hand-edited text always keeps the provider out, the prior version is kept, and queued reads that cannot pass the identity test are held.
// Source contract over migration 20261110040000 and its forward recovery; the behaviour is proved by the isolated PostgreSQL fixture tests/fixtures/pdesc-basic-upgrade/run.sh (scenarios, md5 guards, refusal, forward recovery).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261110040000_cf247_pdesc_basic_profile_upgrade.sql', 'utf8')
const code = mig.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const rec = fs.readFileSync('supabase/held/pdesc_basic_profile_upgrade_forward_recovery.sql', 'utf8')
const LIVE = { blocked: '46634e38c0469cbcbd6c23158dfadc94', admit: '5decbd99c8ecd5e0b072d22ed6f68962', selection: '04acb9419b9965b5d6aab420059c7e84', enqueue: '803478538da3dd9594ba08be38284c3e', next: '7583808609dc2dea1d3fc251607405a1' }

test('five edits are guarded on the live body md5, apply exactly once, and the recovery restores the live text', () => {
  for (const m of Object.values(LIVE)) { expect(mig).toContain(m); expect(rec).toContain(m) }
  expect((code.match(/select pg_temp\.edit_all\(/g) || []).length).toBe(5)
  expect(code).toContain('must apply exactly once')
  expect(code).toContain('already applied')
  expect(code).toContain('differs from the definition this change edits')
  expect(rec).toContain('differs from both texts this recovery knows')
})

test('exactly one new setting: the switch, created OFF, with label, range, unit and used_by; no threshold becomes a setting', () => {
  const rows = [...code.matchAll(/\('pipeline', '(pdesc\.[a-z_]+|batch\.[a-z_]+)', '/g)].map((m) => m[1])
  expect(rows).toEqual(['pdesc.registry_upgrade_on'])
  expect(code).toMatch(/'number', to_jsonb\(0\), 0, 1, 'on\/off', \d+, 'Provider descriptions', '[^']*machine_admit_v1/)
  expect(code).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  // the bounds are derived from existing settings
  expect(code).toContain("security.pipeline_num_v1('pdesc.queue_per_run',10)")
  expect(code).toContain("security.pipeline_num_v1('pdesc.queue_cap',60)")
  expect(code).toContain("security.pipeline_num_v1('batch.provider_description', 3)")
  expect(mig).toMatch(/created OFF/)
})

test('every guard that protects a description still applies to a profile; only the "already held" tests step aside, and only for the profile the provider holds', () => {
  // the one rule for a profile: switch on, text exactly the live registry_factual admission, that admission's read is the admitted registry_factual read
  expect(code).toContain("security.pipeline_num_v1('pdesc.registry_upgrade_on', 0) >= 1")
  expect(code).toContain("btrim(p.description) = btrim(a.after_description)")
  expect(code).toContain("a.tier = 'registry_factual'")
  expect(code).toContain("r.rule = 'registry_factual' and r.worker = 'registry-factual-v1'")
  // machine_blocked: the lock, rejection, withdrawal, finding and name checks are not edited out
  expect(code).toContain("is not null and security.provider_description_basic_profile_v1(p.id) is null then")
  const blockedEdit = code.slice(code.indexOf("select pg_temp.edit_all('security.provider_description_machine_blocked_v1(uuid)'"), code.indexOf("select pg_temp.edit_all('security.provider_description_machine_admit_v1(uuid)'"))
  for (const rule of ['manual_lock', 'prior_human_rejection', 'withdrawn_awaiting_review', 'identity_', 'name_not_clean']) expect(blockedEdit).not.toContain(`'${rule}`)
  // admission: only a source tier with the profile as the before text, a different text, and at least pdesc.min_sentences quoted sentences
  expect(code).toContain("v_tier in ('stored', 'direct', 'firecrawl') and btrim(coalesce(i.before_value->>'description', '')) = btrim(v_basic->>'text')")
  expect(code).toContain("'upgrade_too_short_or_unchanged'")
  expect(code).toContain("security.pipeline_num_v1('pdesc.min_sentences', 2)")
  expect(code).toContain("and not v_upg and i.before_value->>'description' is not null")
  expect(code).toContain("not (v_upg and v_now = btrim(v_basic->>'text'))")
})

test('the prior version is kept: closed (never deleted) admission, before_description, upgrade provenance, superseded read', () => {
  expect(code).toContain("withdrawn_reason = 'Upgraded to a source-verified description from '")
  expect(code).toContain("case when v_upg then v_basic->>'text' end, v_text")
  expect(code).toContain("jsonb_build_object('upgrade', jsonb_build_object('from_tier', 'registry_factual', 'prior_admission_id'")
  expect(code).toContain("'source_url', v_url, 'source_hash', v_hash, 'evidence_id', i.evidence_id")
  expect(code).not.toMatch(/delete\s+from\s+pipeline\.provider_description_machine_admissions/i)
})

test('the identity hold takes only wrong_host and provider_host_conflict, reuses the stored copy found once, rotates through the queue, and a held read is offered again once the provider passes', () => {
  expect(code).toContain("nullif(current_setting('cf.pdesc_cohort',true),'') is null")
  expect(code).toContain("pp.lifecycle_status='active' and pp.publication_status='published'")
  const pass = mig.slice(mig.indexOf("-- identity hold (10 Nov 2026)"), mig.indexOf("-- identity re-offer (9 Nov 2026): a provider whose latest finished read was held$new$"))
  expect(pass.length).toBeGreaterThan(500)
  // only the two outcomes hold; provider_inactive and identity_<finding> leave the read queued
  expect(pass).toContain("i.v->>'rule' in ('wrong_host','provider_host_conflict')")
  expect(pass).toContain("state=case when h.hold then 'held' else r.state end")
  // the stored copy comes from v_stored (found once, above); the pass never calls provider_description_stored_v1 itself
  expect(pass).toContain("(v_stored->>o.provider_id::text)::uuid")
  expect(pass).not.toContain('provider_description_stored_v1')
  // the tested read is marked, and the least recently tested go first
  expect(pass).toContain("jsonb_build_object('identity_checked_at',now())")
  expect(pass).toContain("order by (x.checks->>'identity_checked_at') nulls first")
  expect(pass).toContain("jsonb_build_object('identity_hold',true)")
  // the pass sits after v_stored is built, not before it
  expect(mig.indexOf("-- identity hold (10 Nov 2026)")).toBeGreaterThan(mig.indexOf("$old$-- identity re-offer (9 Nov 2026)"))
  // the selection offers a read held by the pass again once the provider passes the identity test (no new setting)
  expect(code).toContain("coalesce(r.checks ? 'identity_hold',false) and coalesce((security.provider_description_identity_v1(p.id,coalesce(a.source_url,p.website))->>'ok')::boolean,false)) then 'retry_wait'")
})

test('no consumer API object, drop, schedule, ceiling or word list is touched; housekeeping lines are present', () => {
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|api\./)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code).not.toMatch(/cron\.(schedule|alter_job)/i)
  expect(code).not.toMatch(/ai_usd_max|firecrawl_reads_max|machine_refused_words|evidence_claim_words/)
  expect(mig).toMatch(/^-- Replaces: /m)
  expect(mig).toMatch(/^-- Retires: nothing/m)
  expect(code).toMatch(/comment on function security\.provider_description_basic_profile_v1\(uuid\)/)
  expect(code).toMatch(/revoke all on function security\.provider_description_basic_profile_v1\(uuid\)/)
})

test('the isolated PostgreSQL fixture proves locks, rejection, edit, withdrawal and race never touch a provider, an upgrade keeps the prior version, and the recovery returns the live bodies', () => {
  const run = fs.readFileSync('tests/fixtures/pdesc-basic-upgrade/run.sh', 'utf8')
  for (const m of Object.values(LIVE)) expect(run).toContain(m)
  expect(run).toContain('pdesc_basic_profile_upgrade_forward_recovery.sql')
  expect(run).toContain('the five bodies return to the live md5 byte for byte')
  const exp = fs.readFileSync('tests/fixtures/pdesc-basic-upgrade/expected.txt', 'utf8')
  for (const l of ['off_profile_held|null|description_already_held', 'on_prior_version_kept|true|true|registry_factual|true|2|true', 'lock_blocked|manual_lock', 'rejected_blocked|prior_human_rejection', 'edited_profile|null|description_already_held',
    'withdrawn_blocked|null|withdrawn_awaiting_review', 'race_read|held/description_changed_after_lease', 'declined_person_result|true|', 'idhold_after|held/wrong_host/true', 'reoffer_corrected|eligible/true', 'worker_hold_parked|retry_wait/false', 'conflict_held|held/provider_host_conflict/true/true', 'inactive_kept|queued/-/none/true', 'rotate_call2|0|queued/-/none/true|held/wrong_host/true/true', 'settings|pdesc.registry_upgrade_on=0/0-1/on/off/true']) expect(exp).toContain(l)
})
