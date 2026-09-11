import{test,expect}from'@playwright/test'
import fs from'node:fs'

const sql=fs.readFileSync('supabase/migrations/20260912010000_cf_093_scheduler_preview_bound_async_discovery.sql','utf8')
const foundFix=fs.readFileSync('supabase/migrations/20260912010100_cf_093_scheduler_async_binding_found_state_fix.sql','utf8')
const cancelFix=fs.readFileSync('supabase/migrations/20260912010200_cf_093_scheduler_async_binding_cancel_failclosed.sql','utf8')
const retryChain=fs.readFileSync('supabase/migrations/20260912010300_cf_093_scheduler_retry_context_and_token_chain.sql','utf8')
const retryContext=fs.readFileSync('supabase/migrations/20260912010400_cf_093_scheduler_bound_discovery_context_retry.sql','utf8')
const worker=fs.readFileSync('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8')

test('CF-CHG-20260910-093 binds discovery continuations to exact Preview inputs without broadening authority',()=>{
 expect(sql).toContain('pipeline.scheduler_workflow_async_bindings')
 expect(sql).toContain("status in ('prepared','active','handoff_started','cancelled')")
 expect(sql).toContain('alter table pipeline.scheduler_workflow_async_bindings enable row level security')
 expect(sql).toContain('revoke all on table pipeline.scheduler_workflow_async_bindings from public,anon,authenticated')
 expect(sql).toContain('scheduler_workflow_profile_binding_snapshot_v1')
 expect(sql).toContain("p.profile_id::text,p.current_version_id::text,r.course_id::text")
 expect(sql).toContain('queueable_fingerprint')
 expect(sql).toContain("'preview_bound_discovery_count',v_discovery_count")
 expect(sql).toContain("'unsupported_discovery_count',0")
 expect(sql).toContain("'async_discovery_preview_bound',v_discovery_count>0")
 expect(sql).toContain("status='prepared',preview_expires_at")
 expect(sql).toContain("current_setting('coursefinder.scheduler_preview_token',true)")
 expect(sql).toContain('initial scheduler discovery dispatch must match the exact preview-bound discovery set')
 expect(sql).toContain("set status='active',activated_at=now(),execution_expires_at=now()+interval '6 hours'")
 expect(sql).toContain('v_binding.discovery_course_ids @> v_requested')
 expect(sql).toContain('scheduler async bound profile/course identity changed during discovery')
 expect(sql).toContain('d.created_at>=v_binding.activated_at')
 expect(sql).toContain('scheduler async discovery did not produce a current selected URL for every preview-bound discovery course')
 expect(sql).toContain('if v_bound and v_count<>cardinality(v_binding.sync_course_ids)')
 expect(sql).toContain("set status='handoff_started',handoff_started_at=now()")
 expect(sql).toContain("set_config('coursefinder.scheduler_preview_token',p_preview_token::text,true)")

 // Binding presence must be explicit and cancelled/handoff continuations must fail closed.
 expect(foundFix).toContain('v_bound boolean:=false')
 expect(foundFix).toContain('v_bound:=found')
 expect(foundFix).not.toContain('case when found then v_binding.preview_token else null end')
 expect(cancelFix).toContain("b.discovery_course_ids @> v_requested")
 expect(cancelFix).not.toContain("b.status in ('active','handoff_started')")
 expect(cancelFix).toContain('scheduler async binding is not active; continuation rejected')

 // The exact Preview token is retained in nonce payloads, while historical unresolved
 // dispositions remain retryable only for an active exact scheduler binding.
 expect(retryChain).toContain("'scheduler_preview_token',case when v_bound then v_preview_token else null end")
 expect(retryChain).toContain('historical_dispositions_are_retryable')
 expect(retryContext).toContain("b.status='active'")
 expect(retryContext).toContain('v_binding.discovery_course_ids @> v_requested')
 expect(retryContext).toContain("dc.created_at>=v_binding.activated_at")
 expect(retryContext).toContain("'scheduler_bound_retry',true")
 expect(retryContext).toContain("'historical_dispositions_preserved',true")
 expect(retryContext).toContain("dc.status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found')")
 expect(retryContext).not.toContain('delete from pipeline.layer2_course_discovery_candidates')

 // Existing worker continuations already carry actor/full sync scope and use the same
 // scoped context helper; the new DB contract changes retry semantics only while bound.
 expect(worker).toContain('auto_sync_actor')
 expect(worker).toContain('sync_course_ids')
 expect(worker).toContain('layer2_discovery_context_scope')
 expect(worker).toContain('layer2_discovery_scope_dispatch_v2')
 expect(worker).toContain('layer2_scope_profile_batch_service')
 expect(worker).toContain('remaining=courseIds.filter')

 // Preserve authority: only AU Course Facts acquisition is enabled; generic L3/L4 and
 // Search/Publication are not made scheduler side effects by this capability completion.
 expect(sql).toContain("v_workflow <> 'course_facts_l2'")
 expect(sql).toContain("upper(coalesce(trim(p_country_code),'')) <> 'AU'")
 expect(sql).toContain("v_mode <> 'acquisition_only'")
 expect(sql).toContain('Conditional Layer 3/L4 orchestration is not yet qualified')
 expect(sql).toContain('Reprocess governed Evidence')
 expect(sql).not.toContain("automatic_governed_pipeline','label','Automatic governed pipeline','enabled',true")
 expect(sql).not.toContain("reprocess_governed_evidence','label','Reprocess governed Evidence','enabled',true")
 expect(sql).not.toContain('insert into publishing.')
 expect(sql).not.toContain('insert into search.')

 // State/multi-provider scopes do not receive fabricated execution policies.
 expect(sql).toContain('scheduler_workflow_execution_policy_gap_count_v1')
 expect(sql).toContain('if v_policy_gaps>0')
 expect(sql).not.toContain('insert into pipeline.layer2_execution_policies')
 expect(retryContext).not.toContain('insert into pipeline.layer2_execution_policies')
})
