import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { writeRunEnvironment } from './support/runtime-evidence.mjs'

// CF-054 source-contract trigger including legacy HTTP-origin → HTTPS same-host reconciliation.
test.describe('M2.5 Layer 3 source-pattern operator execution contract',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-5-layer3-source-pattern-operator-contract',change_control:'CF-CHG-20260901-054'})})

  test('preserves manual-governed A23 boundary and deterministic Layer 2 hand-back',async()=>{
    const [handoff,legacy,legacyHost,worker,ui,a23]=await Promise.all([
      fs.readFile('supabase/migrations/20260901091500_m2_5_layer3_source_pattern_operator_handback.sql','utf8'),
      fs.readFile('supabase/migrations/20260901091800_m2_5_layer3_source_pattern_legacy_completion_guard.sql','utf8'),
      fs.readFile('supabase/migrations/20260901092500_m2_5_layer3_source_pattern_legacy_http_host_reconcile.sql','utf8'),
      fs.readFile('supabase/functions/layer3-interpret/index.ts','utf8'),
      fs.readFile('src/m2-3-intelligence-entry.jsx','utf8'),
      fs.readFile('supabase/migrations/20260831115800_m2_4_4_a23_qualification_finalizer_handoff.sql','utf8'),
    ])

    expect(a23).toContain("'queued_for_governed_operator_execution'")
    expect(a23).not.toContain('functions/v1/layer3-interpret')

    expect(handoff).toContain("security.current_role_rank()<3")
    expect(handoff).toContain("'source_pattern'=any(mp.allowed_task_classes)")
    expect(handoff).toContain("v_i.task_class<>'source_pattern'")
    expect(handoff).toContain("'pattern_dispatch_version_id',v_new_version")
    expect(handoff).toContain("'identity_control_required','3_of_3'")
    expect(handoff).toContain("security.layer2_discovery_scope_dispatch_v2(lp.id,v_ids,3,null,v_ids)")
    expect(handoff).toContain("'path','layer4_source_resolution'")
    expect(handoff).toContain("'provider_qualified',false")
    expect(handoff).toContain("'canonical_mutation_authorised',false")
    expect(handoff).not.toContain("set authority_class='first_party_qualified'")

    expect(legacy).toContain("v_i.task_class<>'source_pattern'")
    expect(legacyHost).toContain("v_candidate!~'^https://[^[:space:]]+$'")
    expect((legacyHost.match(/\^https\?:\/\/\(\[\^\/:\?\#\]\+\)/g)||[]).length).toBeGreaterThanOrEqual(3)
    expect(legacyHost).toContain("'source-pattern candidate host mismatch'")
    expect(legacyHost).toContain("'provider_qualified',false")
    expect(legacyHost).not.toContain("set authority_class='first_party_qualified'")

    expect(worker).toContain('source_pattern_request_id')
    expect(worker).toContain('layer3_source_pattern_request_context_service')
    expect(worker).toContain('governedEvidenceLinks')
    expect(worker).toContain('candidate_url_must_be_same_host')
    expect(worker).toContain('candidate_url_must_be_evidence_link')
    expect(worker).toContain('source_pattern_same_host')
    expect(worker).toContain('source_pattern_evidence_link_match')
    expect(worker).toContain('layer3_source_pattern_handoff_service')
    expect(worker).toContain('m2.5-cf054-source-pattern-v1')

    expect(ui).toContain('data-layer3-source-pattern-queue')
    expect(ui).toContain("rpc('layer3_source_pattern_queue',{p_limit:50})")
    expect(ui).toContain("body:{source_pattern_request_id:requestId}")
    expect(ui).toContain('Run source-pattern interpretation')
    expect(ui).not.toContain('Run all source-pattern')
  })
})
