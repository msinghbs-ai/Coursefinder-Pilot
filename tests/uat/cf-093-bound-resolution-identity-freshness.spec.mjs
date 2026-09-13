import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const migration = fs.readFileSync('supabase/migrations/20260913062000_cf_093_bound_resolution_identity_freshness_reconcile.sql','utf8')

test('CF-093 bound resolver only consumes selected candidates from the exact Preview token',()=>{
  expect(migration).toContain('join pipeline.layer2_provider_attempts pa on pa.id=dc.provider_attempt_id')
  expect(migration).toContain('join pipeline.jobs j on j.id=pa.job_id')
  expect(migration).toContain("coalesce(j.payload->>'scheduler_preview_token','')=v_binding.preview_token::text")
  expect(migration).toContain('dc.created_at>=v_binding.activated_at')
})

test('CF-093 terminal freshness is invalidated when Layer 1 identity changes',()=>{
  expect(migration).toContain("coalesce(trim(d.match_basis->>'expected_course_code'),'')=coalesce(trim(s.course_code),'')")
  expect(migration).toContain("d.match_basis->>'expected_title'")
  expect(migration).toContain("coalesce(s.canonical_title,s.display_title,'')")
  expect(migration).toContain("d.status in ('ambiguous','identity_mismatch')")
  expect(migration).toContain("d.status='current_page_not_found'")
})

test('CF-093 forward reconciliation preserves authority and ACL boundaries',()=>{
  expect(migration).toContain("if current_user not in ('service_role','postgres')")
  expect(migration).toContain('scheduler async bound profile/course identity changed before discovery Evidence write')
  expect(migration).toContain('revoke all on function public.layer2_discovery_context_scope_bound_v1')
  expect(migration).toContain('grant execute on function public.layer2_discovery_context_scope_bound_v1')
  expect(migration).toContain('revoke all on function security.scheduler_workflow_scope_state_v1')
  expect(migration).toContain('grant execute on function security.scheduler_workflow_scope_state_v1')
})