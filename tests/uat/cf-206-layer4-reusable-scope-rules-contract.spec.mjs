import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'

const ui=fs.readFileSync('src/layer4-scope-rules-entry.jsx','utf8')
const migration=fs.readFileSync('supabase/migrations/20260905032600_cf_206_layer4_reusable_scope_rules.sql','utf8')
const state=fs.readFileSync('supabase/migrations/20260905033100_cf_206_layer4_scope_rule_state_control.sql','utf8')
const index=fs.readFileSync('index.html','utf8')
const release=fs.readFileSync('src/release-currentness-entry.js','utf8')
const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')

test('CF-206 reusable scope rules are evidence-bound and provider-bound',()=>{
  assert.match(migration,/unique\(scholarship_id,candidate_reason,evidence_id\)/)
  assert.match(migration,/r\.evidence_id=v_c\.evidence_id/)
  assert.match(migration,/r\.provider_id=v_s\.provider_id/)
  assert.match(migration,/provider_mismatch/)
  assert.match(migration,/layer4_reusable_rule:/)
})

test('CF-206 future candidates reuse exact retained rule but changed Evidence falls back to review',()=>{
  assert.match(migration,/trg_layer4_scope_rule_candidate/)
  assert.match(migration,/no_matching_rule/)
  assert.match(migration,/new\.evidence_id is not null/)
})

test('CF-206 mass rule creation is guarded and does not publish',()=>{
  assert.match(migration,/pipeline_operator role required/)
  assert.match(migration,/SAVE RULE/)
  assert.match(migration,/publication_changed',false/)
  assert.match(ui,/SAVE RULE/)
  assert.match(ui,/Changed Evidence always returns here|changed Evidence ID/i)
  assert.match(state,/state-change reason must be at least 8 characters/)
})

test('v2.15.66 loads reusable rules while CF-102 ProviderLogo remains present',()=>{
  assert.match(index,/layer4-mass-operations-entry\.jsx/)
  assert.match(index,/layer4-scope-rules-entry\.jsx/)
  assert.match(index,/v2\.15\.66/)
  assert.match(release,/VERSION='2\.15\.66'/)
  assert.match(release,/CF-102 Provider logo/)
  assert.match(logo,/sessionStorage|inflight|cache/i)
})
