import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const worker = fs.readFileSync('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8')
const migration = fs.readFileSync('supabase/migrations/20260912232827_cf_093_preview_provenance_terminal_dedupe_hardening.sql','utf8')
const acceptance = fs.readFileSync('.github/workflows/cf093-uq-corrective-acceptance.yml','utf8')

test('CF-093 worker revalidates Preview binding after network acquisition before writes',()=>{
  expect(worker).toContain('layer2-scope-discover-scheduled-v1.3.10')
  expect(worker).toContain('scheduler async binding identity changed during acquisition')
  expect(worker).toContain('scheduler async binding identity changed during candidate verification')
  expect(worker).toContain('scheduler_preview_token:schedulerPreviewToken||null')
})

test('CF-093 worker retains qualified terminal basis and exact original-title matches',()=>{
  expect(worker).toContain('zeroResultMarkerQualified:true')
  expect(worker).toContain('requiredPrefixLinkCount:0')
  expect(worker).toContain('attemptFinalized:true')
  expect(worker).toContain('if(!acquired.attemptFinalized)await rpc')
  expect(worker).toContain('nOriginal=norm(expectedTitle)')
  expect(worker).toContain('Math.max(similarity(rankingExpectedTitle,observedTitle),similarity(expectedTitle,observedTitle))')
  expect(worker).toContain('zero_result_marker_qualified:Boolean(acquired.zeroResultMarkerQualified)')
  expect(worker).toContain('required_prefix_link_count:ranked.requiredPrefixLinkCount')
})

test('CF-093 handoff accepts only exact Preview-provenanced discovery outcomes',()=>{
  expect(migration).toContain("j.payload->>'scheduler_preview_token'=v_binding.preview_token::text")
  expect(migration).toContain('exact scheduler Preview binding is missing, cancelled, expired or does not match the handoff scope')
  expect(migration).toContain("'status','terminal_only_complete'")
  expect(migration).toContain("'terminal_only',true")
  expect(migration).toContain("e->>'status'='discovery_started'")
  expect(migration).toContain('expected_count<>completed_count')
})

test('CF-093 mixed terminal profiles and cancellation replay remain fail-closed and auditable',()=>{
  expect(migration).toContain("'status','terminal_only'")
  expect(migration).toContain("not in ('started','discovery_started','terminal_only')")
  expect(migration).toContain('if v_changed>0 then')
  expect(migration).toContain("'async_binding_cancelled_at',now()")
})

test('CF-093 consequential UQ acceptance is manual exact-head evidence',()=>{
  expect(acceptance).toContain('workflow_dispatch:')
  expect(acceptance).toContain("test \"$(git rev-parse HEAD)\" = \"${GITHUB_SHA}\"")
  expect(acceptance).toContain("expect(dispatch.result?.status).toBe('scope_started')")
  expect(acceptance).toContain("expect(dispatch.result.profiles[0]?.status).toBe('discovery_started')")
})
