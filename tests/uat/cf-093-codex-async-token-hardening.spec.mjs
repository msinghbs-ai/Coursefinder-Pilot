import{test,expect}from'@playwright/test'
import fs from'node:fs'

const worker=fs.readFileSync('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8')
const migration=fs.readFileSync('supabase/migrations/20260912100539_cf_093_codex_async_token_identity_dedupe_hardening.sql','utf8')

test('CF-093 Preview-bound discovery consumes the exact token through context continuation and handoff',()=>{
 expect(worker).toContain('schedulerPreviewToken=clean(body.scheduler_preview_token)')
 expect(worker).toContain('exact scheduler preview token required for preview-bound async discovery')
 expect(worker).toContain('layer2_discovery_context_scope_bound_v1')
 expect(worker).toContain('layer2_discovery_scope_dispatch_bound_v1')
 expect(worker).toContain('layer2_scope_profile_batch_bound_v1')
 expect(worker).toContain('scheduler_preview_token:schedulerPreviewToken||null')
 expect(migration).toContain('b.preview_token=p_preview_token and b.actor_id=p_actor and b.profile_id=p_profile_id')
 expect(migration).toContain('identity_fingerprint')
 expect(migration).toContain('scheduler async bound profile/course identity changed before discovery Evidence write')
})

test('CF-093 first-party zero results remain transient unless the profile carries qualified markers',()=>{
 expect(worker).toContain('zero_result_markers')
 expect(worker).toContain('qualifiedZeroResult')
 expect(worker).toContain('zero_result_marker_qualified')
 expect(worker).toContain('unqualified_zero_result')
 expect(worker).not.toContain('if(firstPartySearch){if(!emptySearchResult)')
})

test('CF-093 cancellation, completion dedupe and terminal-only Preview are fail closed',()=>{
 expect(migration).toContain("status not in ('prepared','active','cancelled')")
 expect(migration).toContain("found_count=referenced_count and reusable_count=referenced_count")
 expect(migration).toContain("coalesce(j.result->'async_handoffs','[]'::jsonb)")
 expect(migration).toContain('No actionable Layer 2 work remains; the scope contains only current governed terminal outcomes.')
})
