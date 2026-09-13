import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const migration = fs.readFileSync('supabase/migrations/20260913063252_cf_093_bound_resolution_identity_freshness_reconcile.sql','utf8')
const retryFairness = fs.readFileSync('supabase/migrations/20260913074104_cf_093_bounded_retry_fairness_reconcile.sql','utf8')
const finalReview = fs.readFileSync('supabase/migrations/20260913082845_cf_093_final_review_authority_retry_reconcile.sql','utf8')

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

test('CF-093 bounded retry fairness honours governed max attempts without manufacturing terminal Evidence',()=>{
  expect(retryFairness).toContain("v_ctx#>>'{configuration,retry,max_attempts}'")
  expect(retryFairness).toContain("r->>'status' in ('failed','candidate')")
  expect(retryFairness).toContain('coalesce(a.retry_attempts,0)<v_retry_max')
  expect(retryFairness).toContain('order by coalesce(a.retry_attempts,0),c.canonical_title,c.id')
  expect(retryFairness).toContain("jsonb_agg(to_jsonb(x)-'retry_attempts' order by x.retry_attempts,x.canonical_title,x.id)")
  expect(retryFairness).not.toContain("status='current_page_not_found'")
  expect(retryFairness).not.toContain('insert into pipeline.layer2_course_discovery_candidates')
})

test('CF-093 final reconciliation enforces retry ceiling and full-set fairness before nonce dispatch',()=>{
  expect(finalReview).toContain("configuration#>>'{retry,max_attempts}'")
  expect(finalReview).toContain("r->>'status' in ('failed','candidate')")
  expect(finalReview).toContain('coalesce(a.attempts,0)<v_retry_max')
  expect(finalReview).toContain("'status','retry_exhausted'")
  expect(finalReview).toContain("'operator_review_required',true")
  expect(finalReview).toContain("'course_ids',to_jsonb(v_ordered)")
  expect(finalReview).toContain('order by coalesce(a.attempts,0),q.course_id')
  expect(finalReview).not.toContain('least(greatest(coalesce(nullif(v_ctx#>>\'{configuration,retry,max_attempts}\'')')
})

test('CF-093 final reconciliation aggregates retry history once and rejects unapproved acquisition targets',()=>{
  expect(finalReview).toContain('with retry_counts as (')
  expect(finalReview).toContain('group by (r->>\'course_id\')::uuid')
  expect(finalReview).toContain('left join retry_counts a on a.course_id=c.id')
  expect(finalReview).toContain('scheduler_workflow_queueable_url_allowed_v1(v_profile_id,p_request_url)')
  expect(finalReview).toContain('Layer 2 acquisition target is outside the governed profile host allowlist')
})

test('CF-093 discovery-subset handoff requires exact Preview-token candidate provenance',()=>{
  expect(finalReview).toContain('when v_bound and c.id=any(v_binding.discovery_course_ids) then (')
  expect(finalReview).toContain("j.payload->>'scheduler_preview_token'=v_binding.preview_token::text")
  const discoveryBranch = finalReview.split('when v_bound and c.id=any(v_binding.discovery_course_ids) then (')[1].split('when v_bound then coalesce')[0]
  expect(discoveryBranch).not.toContain("nullif(c.course_url,'')")
})

test('CF-093 forward reconciliation preserves authority and ACL boundaries',()=>{
  expect(migration).toContain("if current_user not in ('service_role','postgres')")
  expect(migration).toContain('scheduler async bound profile/course identity changed before discovery Evidence write')
  expect(migration).toContain('revoke all on function public.layer2_discovery_context_scope_bound_v1')
  expect(migration).toContain('grant execute on function public.layer2_discovery_context_scope_bound_v1')
  expect(migration).toContain('revoke all on function security.scheduler_workflow_scope_state_v1')
  expect(migration).toContain('grant execute on function security.scheduler_workflow_scope_state_v1')
  expect(retryFairness).toContain("if current_user not in ('service_role','postgres')")
  expect(finalReview).toContain("if current_user not in ('service_role','postgres')")
  expect(finalReview).toContain('revoke all on function security.layer2_discovery_scope_dispatch_v2')
  expect(finalReview).toContain('grant execute on function security.layer2_discovery_scope_dispatch_v2')
  expect(finalReview).toContain('revoke all on function public.layer2_scope_profile_batch_service')
  expect(finalReview).toContain('grant execute on function public.layer2_scope_profile_batch_service')
})